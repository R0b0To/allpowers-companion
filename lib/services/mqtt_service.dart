import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../models/mqtt_settings.dart';
import '../models/power_station_status.dart';
import '../utils/logger.dart';
// Add import at top
import '../models/automation_flow.dart';

/// Manages the MQTT connection in both Gateway and Client modes.
///
/// ## Connect / reconnect lifecycle
///
/// 1. [configure] is called with the user's [MqttSettings].
/// 2. [_connect] creates a fresh [MqttServerClient] and calls [connect()].
///    **[autoReconnect] is intentionally NOT set before this call.**
///    Setting it before the initial connect changes how the library handles
///    failures: it suppresses the [NoConnectionException] but also swallows
///    the error, leaving the app in a permanently-stuck connecting state.
/// 3. If [connect()] succeeds, [autoReconnect] is enabled on the live client
///    so subsequent network drops are handled automatically.
/// 4. If [connect()] fails (or the broker never sends CONNACK), [_connect]
///    catches the error, updates [lastError], and schedules a retry via
///    [_scheduleReconnect] with exponential back-off (5 s → 60 s cap).
///
/// ## "Missing Connection Acknowledgement" cause
///
/// This error means the TCP handshake succeeded but the broker dropped the
/// connection before sending a CONNACK.  The most common cause with HiveMQ
/// Cloud is a TLS / port mismatch:
///   • Port 8883  →  TLS must be ON
///   • Port 1883  →  TLS must be OFF
/// HiveMQ Cloud Serverless only accepts TLS — always use 8883 + TLS ON.
///
/// ## Gateway mode
/// Publishes [PowerStationStatus] JSON to `{prefix}/status` (retained, QoS 1)
/// on every BLE update; subscribes to `{prefix}/cmd/+` for outlet commands.
///
/// ## Client mode
/// Subscribes to `{prefix}/status`; publishes outlet commands to
/// `{prefix}/cmd/{usb|ac|dc}`.
final class MqttService extends ChangeNotifier {
  MqttServerClient? _client;
  MqttSettings _settings = const MqttSettings();
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _msgSub;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  static const int _maxBackoffSeconds = 60;

  // ── Public state ───────────────────────────────────────────────────────────
  PowerStationStatus _remoteStatus = const PowerStationStatus();
  bool _bleConnectedRemote = false;
  DateTime? _lastRemoteUpdate;

  bool _isConnected = false;
  bool _isConnecting = false;
  String? _lastError;

  /// Gateway mode: invoked with outlet name ("usb"|"ac"|"dc") and requested
  /// state when a command packet arrives from a client phone.
  void Function(String outlet, bool value)? onCommand;


  PowerStationStatus get remoteStatus => _remoteStatus;
  bool get bleConnectedRemote => _bleConnectedRemote;
  DateTime? get lastRemoteUpdate => _lastRemoteUpdate;
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String? get lastError => _lastError;
  AppMode get mode => _settings.mode;
  MqttSettings get settings => _settings;

  // ── Configuration ─────────────────────────────────────────────────────────

  Future<void> configure(MqttSettings settings) async {
    if (_settings == settings) return;
    _settings = settings;
    await _disconnect();
    if (settings.mode != AppMode.standalone && settings.isConfigured) {
      unawaited(_connect());
    }
  }


  /// Called on both gateway and client when a flows update arrives from
/// the other side. The handler is responsible for updating local state
/// and storage; this service just delivers the parsed list.
void Function(List<AutomationFlow> flows)? onFlowsReceived;

/// Publishes the full flows list (retained, QoS 1) so the other side
/// picks it up immediately on connect.
void publishFlows(List<AutomationFlow> flows) {
  if (!_isConnected) return;
  if (_settings.mode == AppMode.standalone) return;
  _publish(
    _settings.flowsTopic,
    jsonEncode(flows.map((f) => f.toJson()).toList()),
    retain: true,
  );
  Log.i('MqttService', 'Flows published (${flows.length} flow(s))');
}

  // ── Connect ───────────────────────────────────────────────────────────────

  Future<void> _connect() async {
    if (_isConnecting || _isConnected) return;
    _isConnecting = true;
    _lastError = null;
    notifyListeners();

    try {
      final id = _effectiveClientId();
      final c = MqttServerClient.withPort(
        _settings.brokerHost.trim(),
        id,
        _settings.port,
      );

      c.secure = _settings.useTls;
      c.keepAlivePeriod = 30;
      c.logging(on: kDebugMode);

      // Register onDisconnected BEFORE connecting so we catch drops.
      c.onDisconnected = _onDisconnected;

      // CRITICAL FIX: supplying this callback prevents mqtt_client from
      // throwing NoConnectionException as an unhandled exception.
      // We read the failure from connect()'s return value instead.
      c.onFailedConnectionAttempt = (int attempt) {
        Log.w('MqttService', 'Connection attempt $attempt failed');
      };

      // DO NOT set autoReconnect here — see class-level doc comment.

      final connMsg = MqttConnectMessage()
    .withClientIdentifier(id)
    .startClean(); // Clean connection message without the incomplete Will QoS

      if (_settings.username.isNotEmpty) {
        connMsg.authenticateAs(_settings.username, _settings.password);
      }

      c.connectionMessage = connMsg;
      _client = c;

      Log.i('MqttService',
          'Connecting to ${_settings.brokerHost}:${_settings.port} '
          '(TLS: ${_settings.useTls}) [${_settings.mode.name}]');

      final status = await c.connect();

      if (status?.state == MqttConnectionState.connected) {
        // ── Success ──────────────────────────────────────────────────────
        _reconnectAttempts = 0;

        // Safe to enable auto-reconnect now that the first connect worked.
        c.autoReconnect = true;
        c.onAutoReconnected = _onAutoReconnected;

        _isConnected = true;
        _isConnecting = false;
        _lastError = null;
        _subscribe();
        notifyListeners();
        Log.i('MqttService', 'Connected [${_settings.mode.name}]');
      } else {
        // Broker responded but refused (e.g. bad credentials).
        final code = status?.returnCode?.name ?? 'no response';
        throw StateError('Broker refused connection: $code');
      }
    } catch (e) {
      Log.e('MqttService', 'Connect failed', e);
      _lastError = _friendlyError(e);
      _isConnected = false;
      _isConnecting = false;
      _client?.disconnect();
      _client = null;
      notifyListeners();
      _scheduleReconnect();
    }
  }

  // ── Reconnect back-off ────────────────────────────────────────────────────

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    // 5 s, 10 s, 15 s … capped at 60 s.
    final backoff = Duration(
      seconds: (_reconnectAttempts * 5).clamp(5, _maxBackoffSeconds),
    );
    Log.i('MqttService',
        'Retry in ${backoff.inSeconds}s (attempt $_reconnectAttempts)');
    _reconnectTimer = Timer(backoff, () {
      if (!_isConnected &&
          _settings.mode != AppMode.standalone &&
          _settings.isConfigured) {
        unawaited(_connect());
      }
    });
  }

  // ── Disconnect ────────────────────────────────────────────────────────────

  Future<void> _disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _msgSub?.cancel();
    _msgSub = null;
    _client?.disconnect();
    _client = null;
    _isConnected = false;
    _isConnecting = false;
    notifyListeners();
  }

  // ── Connection callbacks ──────────────────────────────────────────────────

  /// Called by mqtt_client after autoReconnect re-establishes the link.
  /// Re-subscribes because autoReconnect clears all existing subscriptions.
  void _onAutoReconnected() {
    _isConnected = true;
    _lastError = null;
    _subscribe();
    notifyListeners();
    Log.i('MqttService', 'Auto-reconnected — re-subscribed');
  }

  /// Called on an unsolicited disconnect (only fires when autoReconnect is
  /// false, i.e. during the initial connect attempt or after [_disconnect]).
  void _onDisconnected() {
    final wasConnected = _isConnected;
    _isConnected = false;
    notifyListeners();
    Log.w('MqttService', 'Disconnected');

    // Reconnect only for unexpected drops, not our own _disconnect() calls
    // (which null out _client first).
    if (wasConnected && _client != null) {
      _scheduleReconnect();
    }
  }

  // ── Subscribe ─────────────────────────────────────────────────────────────

  void _subscribe() {
    final c = _client;
    if (c == null) return;

    _msgSub?.cancel();

    switch (_settings.mode) {
      case AppMode.gateway:
  c.subscribe('${_settings.commandTopic}/+', MqttQos.atLeastOnce);
  c.subscribe(_settings.flowsTopic, MqttQos.atLeastOnce);
  Log.i('MqttService',
      'Gateway subscribed to commands + flows');

case AppMode.client:
  c.subscribe(_settings.statusTopic, MqttQos.atLeastOnce);
  c.subscribe(_settings.flowsTopic, MqttQos.atLeastOnce);
  Log.i('MqttService',
      'Client subscribed to status + flows');

      case AppMode.standalone:
        break;
    }

    _msgSub = c.updates?.listen(_onMessages);
  }


void _onMessages(List<MqttReceivedMessage<MqttMessage>> events) {
  for (final event in events) {
    final pub = event.payload as MqttPublishMessage;
    final raw =
        MqttPublishPayload.bytesToStringAsString(pub.payload.message);
    try {
      // Flows topic is shared — handled regardless of mode.
      if (event.topic == _settings.flowsTopic) {
        _handleFlowsSync(raw);
        continue;
      }

      if (_settings.mode == AppMode.client &&
          event.topic == _settings.statusTopic) {
        _handleStatus(raw);
      } else if (_settings.mode == AppMode.gateway &&
          event.topic.startsWith(_settings.commandTopic)) {
        _handleCommand(event.topic, raw);
      }
    } catch (e) {
      Log.e('MqttService', 'Parse error [${event.topic}]', e);
    }
  }
}

void _handleFlowsSync(String raw) {
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    final flows = list
        .map((j) => AutomationFlow.tryFromJson(j as Map<String, dynamic>))
        .whereType<AutomationFlow>()
        .toList();
    Log.i('MqttService', 'Flows received (${flows.length} flow(s))');
    onFlowsReceived?.call(flows);
  } catch (e) {
    Log.e('MqttService', 'Failed to parse flows payload', e);
  }
}

  // ── Message handlers ──────────────────────────────────────────────────────

  void _handleStatus(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final newStatus = PowerStationStatus.validated(
      batteryLevel: (j['batteryLevel'] as num? ?? 0).toInt(),
      inputWatts: (j['inputWatts'] as num? ?? 0).toInt(),
      outputWatts: (j['outputWatts'] as num? ?? 0).toInt(),
      minutesRemaining: (j['minutesRemaining'] as num? ?? 0).toInt(),
      isUsbOn: j['isUsbOn'] as bool? ?? false,
      isAcOn: j['isAcOn'] as bool? ?? false,
      isDcOn: j['isDcOn'] as bool? ?? false,
    );
    final bleConn = j['bleConnected'] as bool? ?? false;
    if (newStatus != _remoteStatus || bleConn != _bleConnectedRemote) {
      _remoteStatus = newStatus;
      _bleConnectedRemote = bleConn;
      _lastRemoteUpdate = DateTime.now();
      notifyListeners();
    }
  }

  void _handleCommand(String topic, String raw) {
    final outlet = topic.split('/').last;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final value = j['value'] as bool? ?? false;
    Log.i('MqttService', 'CMD received: $outlet=$value');
    onCommand?.call(outlet, value);
  }


  // ── Publish ───────────────────────────────────────────────────────────────

  /// Gateway: forward the latest BLE status to all subscribed clients.
  /// Published with [retain: true] so a freshly-connected client gets the
  /// current state immediately rather than waiting for the next BLE packet.
  void publishStatus(PowerStationStatus status, {bool bleConnected = true}) {
    if (!_isConnected || _settings.mode != AppMode.gateway) return;
    _publish(
      _settings.statusTopic,
      jsonEncode({
        'batteryLevel': status.batteryLevel,
        'inputWatts': status.inputWatts,
        'outputWatts': status.outputWatts,
        'minutesRemaining': status.minutesRemaining,
        'isUsbOn': status.isUsbOn,
        'isAcOn': status.isAcOn,
        'isDcOn': status.isDcOn,
        'bleConnected': bleConnected,
        'ts': DateTime.now().toUtc().millisecondsSinceEpoch,
      }),
      retain: true,
    );
  }



  /// Client: send an outlet-toggle command to the gateway.
  void sendCommand(String outlet, bool value) {
    if (!_isConnected || _settings.mode != AppMode.client) return;
    _publish(
      '${_settings.commandTopic}/$outlet',
      jsonEncode({'value': value}),
    );
    Log.i('MqttService', 'CMD sent: $outlet=$value');
  }

  void _publish(String topic, String payload, {bool retain = false}) {
    final c = _client;
    if (c == null ||
        c.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }
    final builder = MqttClientPayloadBuilder()..addString(payload);
    c.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!,
        retain: retain);
  }

  // ── One-shot connection test ───────────────────────────────────────────────

  /// Opens a temporary connection to verify broker reachability and
  /// credentials, then disconnects immediately.
  Future<String> testConnection(MqttSettings s) async {
    final testId =
        'ap_test_${DateTime.now().millisecondsSinceEpoch % 1000000}';
    final c = MqttServerClient.withPort(s.brokerHost.trim(), testId, s.port);
    c.secure = s.useTls;
    c.keepAlivePeriod = 10;
    // Suppress unhandled exception during the test connect.
    c.onFailedConnectionAttempt = (_) {};

    try {
  final connMsg = MqttConnectMessage()
      .withClientIdentifier(testId)
      .startClean();
  if (s.username.isNotEmpty) {
    connMsg.authenticateAs(s.username, s.password);
  }
  c.connectionMessage = connMsg;

  final status =
      await c.connect().timeout(const Duration(seconds: 10));

  // 1. Evaluate success BEFORE disconnecting (since disconnect mutates the state)
  final isSuccess = status?.state == MqttConnectionState.connected ||
      status?.returnCode == MqttConnectReturnCode.connectionAccepted;

  // 2. Safely close the temporary handshake connection
  c.disconnect();

  if (isSuccess) {
    return 'Connected to ${s.brokerHost}:${s.port} ✓';
  }
  
  return 'Connection failed — broker returned: '
      '${status?.returnCode?.name ?? 'no response'}';
} catch (e) {
  c.disconnect();
  return 'Error: ${_friendlyError(e)}';
}
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

 String _effectiveClientId() {
  final baseId = _settings.clientId.trim().isNotEmpty 
      ? _settings.clientId.trim() 
      : 'ap';
  final tag = _settings.mode == AppMode.gateway ? 'gw' : 'cl';
  
  // Appends '_gw' or '_cl' and a small random timestamp to guarantee uniqueness
  return '${baseId}_${tag}_${DateTime.now().millisecondsSinceEpoch % 100000}';
}

  String _friendlyError(Object e) {
    final s = e.toString();
    // The specific error the user hit — TLS / port mismatch.
    if (s.contains('NoConnectionException') ||
        s.contains('Connection Acknowledgement') ||
        s.contains('no response')) {
      return 'Broker did not respond.\n'
          'Check: host is correct, port 8883 requires TLS ON, port 1883 requires TLS OFF.';
    }
    if (s.contains('SocketException') ||
        s.contains('refused') ||
        s.contains('lookup')) {
      return 'Cannot reach broker — check the host name and your internet connection.';
    }
    if (s.contains('UNAUTHORIZED') ||
        s.contains('BAD_CREDENTIALS') ||
        s.contains('refused connection: notAuthorized')) {
      return 'Authentication failed — check username and password.';
    }
    if (s.contains('HandshakeException') || s.contains('TLS')) {
      return 'TLS handshake failed — make sure TLS is ON for port 8883.';
    }
    if (s.contains('TimeoutException') || s.contains('timed out')) {
      return 'Connection timed out — broker may be unreachable.';
    }
    return s.length > 140 ? '${s.substring(0, 140)}…' : s;
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _msgSub?.cancel();
    _client?.disconnect();
    super.dispose();
  }
}