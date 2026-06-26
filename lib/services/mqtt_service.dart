import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../models/automation_history_entry.dart';
import '../models/automation_flow.dart';
import '../models/mqtt_settings.dart';
import '../models/power_station_status.dart';
import '../utils/logger.dart';

/// Manages the MQTT connection in both Gateway and Client modes.
///
/// ## History sync
/// Gateway publishes new history entries to `{prefix}/history` (not retained)
/// so clients receive them in real time. On connect, the gateway also
/// publishes a snapshot of recent history to `{prefix}/history/snapshot`
/// (retained, QoS 1) so freshly-connected clients get the full picture.
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

  void Function(String outlet, bool value)? onCommand;
  void Function(List<AutomationFlow> flows)? onFlowsReceived;
  void Function(List<AutomationHistoryEntry> entries)? onHistoryReceived;

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

  // ── Publish helpers ────────────────────────────────────────────────────────

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

  /// Gateway: publishes a single new history entry (not retained — live events).
  void publishHistoryEntry(AutomationHistoryEntry entry) {
    if (!_isConnected || _settings.mode != AppMode.gateway) return;
    _publish(
      '${_settings.topicPrefix}/history',
      jsonEncode(entry.toJson()),
      retain: false,
    );
  }

  /// Gateway: publishes a full history snapshot (retained so clients get it on connect).
  void publishHistorySnapshot(List<AutomationHistoryEntry> entries) {
    if (!_isConnected || _settings.mode != AppMode.gateway) return;
    final payload = jsonEncode(entries.map((e) => e.toJson()).toList());
    _publish(
      '${_settings.topicPrefix}/history/snapshot',
      payload,
      retain: true,
    );
    Log.i('MqttService', 'History snapshot published (${entries.length} entries)');
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
      c.onDisconnected = _onDisconnected;
      c.onFailedConnectionAttempt = (int attempt) {
        Log.w('MqttService', 'Connection attempt $attempt failed');
      };

      final connMsg = MqttConnectMessage()
          .withClientIdentifier(id)
          .startClean();

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
        _reconnectAttempts = 0;
        c.autoReconnect = true;
        c.onAutoReconnected = _onAutoReconnected;

        _isConnected = true;
        _isConnecting = false;
        _lastError = null;
        _subscribe();
        notifyListeners();
        Log.i('MqttService', 'Connected [${_settings.mode.name}]');
      } else {
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

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
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

  void _onAutoReconnected() {
    _isConnected = true;
    _lastError = null;
    _subscribe();
    notifyListeners();
    Log.i('MqttService', 'Auto-reconnected — re-subscribed');
  }

  void _onDisconnected() {
    final wasConnected = _isConnected;
    _isConnected = false;
    notifyListeners();
    Log.w('MqttService', 'Disconnected');

    final libraryOwnsReconnect = _client?.autoReconnect ?? false;
    if (wasConnected && _client != null && !libraryOwnsReconnect) {
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
        Log.i('MqttService', 'Gateway subscribed to commands + flows');

      case AppMode.client:
        c.subscribe(_settings.statusTopic, MqttQos.atLeastOnce);
        c.subscribe(_settings.flowsTopic, MqttQos.atLeastOnce);
        c.subscribe('${_settings.topicPrefix}/history', MqttQos.atLeastOnce);
        c.subscribe('${_settings.topicPrefix}/history/snapshot', MqttQos.atLeastOnce);
        Log.i('MqttService', 'Client subscribed to status + flows + history');

      case AppMode.standalone:
        break;
    }

    _msgSub = c.updates?.listen(_onMessages);
  }

  // ── Message dispatch ──────────────────────────────────────────────────────

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final pub = event.payload as MqttPublishMessage;
      final raw =
          MqttPublishPayload.bytesToStringAsString(pub.payload.message);
      try {
        if (event.topic == _settings.flowsTopic) {
          _handleFlowsSync(raw);
          continue;
        }

        // History: single entry
        if (event.topic == '${_settings.topicPrefix}/history') {
          _handleHistoryEntry(raw);
          continue;
        }

        // History: full snapshot
        if (event.topic == '${_settings.topicPrefix}/history/snapshot') {
          _handleHistorySnapshot(raw);
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

  void _handleHistoryEntry(String raw) {
    try {
      final entry = AutomationHistoryEntry.tryFromJson(
          jsonDecode(raw) as Map<String, dynamic>);
      if (entry != null) {
        onHistoryReceived?.call([entry]);
      }
    } catch (e) {
      Log.e('MqttService', 'Failed to parse history entry', e);
    }
  }

  void _handleHistorySnapshot(String raw) {
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final entries = list
          .map((j) => AutomationHistoryEntry.tryFromJson(
              j as Map<String, dynamic>))
          .whereType<AutomationHistoryEntry>()
          .toList();
      Log.i('MqttService', 'History snapshot received (${entries.length} entries)');
      if (entries.isNotEmpty) onHistoryReceived?.call(entries);
    } catch (e) {
      Log.e('MqttService', 'Failed to parse history snapshot', e);
    }
  }

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

  Future<String> testConnection(MqttSettings s) async {
    final testId =
        'ap_test_${DateTime.now().millisecondsSinceEpoch % 1000000}';
    final c = MqttServerClient.withPort(s.brokerHost.trim(), testId, s.port);
    c.secure = s.useTls;
    c.keepAlivePeriod = 10;
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

      final isSuccess = status?.state == MqttConnectionState.connected ||
          status?.returnCode == MqttConnectReturnCode.connectionAccepted;

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

  String _effectiveClientId() {
    final baseId = _settings.clientId.trim().isNotEmpty
        ? _settings.clientId.trim()
        : 'ap';
    final tag = _settings.mode == AppMode.gateway ? 'gw' : 'cl';
    return '${baseId}_${tag}_${DateTime.now().microsecondsSinceEpoch}';
  }

  String _friendlyError(Object e) {
    final s = e.toString();
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

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _msgSub?.cancel();
    _client?.disconnect();
    onCommand = null;
    onFlowsReceived = null;
    onHistoryReceived = null;
    super.dispose();
  }
}