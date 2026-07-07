import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models/automation_flow.dart';
import 'models/automation_history_entry.dart';
import 'models/automation_settings.dart';
import 'models/mqtt_rpc_methods.dart';
import 'models/mqtt_settings.dart';
import 'models/power_station_status.dart';
import 'models/tapo_device.dart';
import 'repositories/app_repositories.dart';
import 'services/ble_service.dart';
import 'services/energy_log_service.dart';
import 'services/flow_engine.dart';
import 'services/foreground_service.dart';
import 'services/history_service.dart';
import 'services/mqtt_service.dart';
import 'services/notification_service.dart';
import 'services/tapo_device_service.dart';
import 'services/tapo_service.dart';
import 'services/webhook_service.dart';
import 'utils/logger.dart';

/// Owns every service and all cross-service coordination logic.
///
/// [MainShell] creates one instance, listens to it as a [ChangeNotifier],
/// and reads the public state below to build the UI. It calls the public
/// mutation methods when the user makes a change.
///
/// ## Lifecycle
/// Call [init] once (e.g. in a post-frame callback). Dispose when the
/// root widget is removed — typically never in practice because [MainShell]
/// lives for the entire app lifetime.
final class AppCoordinator extends ChangeNotifier {
  AppCoordinator({AppRepositories? repos})
      : _repos = repos ?? AppRepositories();

  // ── Repository layer ───────────────────────────────────────────────────────
  final AppRepositories _repos;

  // ── Services (read by the UI) ──────────────────────────────────────────────
  final notifications = NotificationService();
  final webhooks = WebhookService();
  final tapo = TapoService();
  final mqtt = MqttService();

  late final HistoryService history;
  late final EnergyLogService energyLog;
  late final BleService ble;
  late final TapoDeviceService tapoDevices;
  late final FlowEngine _flowEngine;

  // ── Public state (read by MainShell to build the UI) ──────────────────────
  AutomationSettings settings = const AutomationSettings();
  MqttSettings mqttSettings = const MqttSettings();
  List<AutomationFlow> flows = [];
  bool permissionsPermanentlyDenied = false;
  bool isBootstrapped = false;

  // ── Private MQTT throttle state ────────────────────────────────────────────
  //
  // Tracks the last published values so we only push to the broker when
  // something actually changes or 5 seconds have elapsed.
  //
  // FIX: all four fields are reset to null in [_onBleStateChanged] when BLE
  // disconnects. Without this reset, _lastMqttPublishTime could hold a recent
  // timestamp that suppresses the first real status publish after reconnect
  // for up to 5 seconds, giving clients a stale picture of the station.
  DateTime? _lastMqttPublishTime;
  bool? _lastAcState;
  bool? _lastDcState;
  bool? _lastUsbState;

  // ── History sync guard ─────────────────────────────────────────────────────
  int _lastKnownHistoryCount = 0;
  bool _applyingRemoteFlows = false;

  // ── Timers ──────────────────────────────────────────────────────────────────
  //
  // [_flowEvalTimer] re-evaluates flows on a fixed cadence, independent of
  // BLE packets or Tapo polls. Without this, a flow whose time window opens
  // or closes while nothing else changes (no new BLE packet, no Tapo state
  // change) would never be re-checked — the window guard is correct, but
  // only actually gets *evaluated* when some other event happens to trigger
  // `_evaluateFlow`.
  //
  // [_mqttHeartbeatTimer] keeps the gateway's retained status message fresh
  // during long idle periods so a client that reconnects hours later sees a
  // recent timestamp rather than one that merely looks stale from inactivity.
  Timer? _flowEvalTimer;
  Timer? _mqttHeartbeatTimer;

  // ── Initialisation ─────────────────────────────────────────────────────────

  /// Must be called once, typically from a post-frame callback in
  /// [MainShell.initState].
  Future<void> init() async {
    history = HistoryService(_repos.history);
    energyLog = EnergyLogService(_repos.energyLog);
    ble = BleService(_repos.ble);
    tapoDevices = TapoDeviceService(tapo, _repos.tapo);
    _flowEngine =
        FlowEngine(ble, webhooks, tapo, tapoDevices, history, _repos.flows);

    await notifications.init();

    await _requestPermissions();

    // All three reads share the same SharedPreferencesSource — one native call.
    final results = await Future.wait([
      _repos.automationSettings.load(),
      _repos.mqttSettings.load(),
      _repos.flows.loadFlows(),
    ]);

    settings = results[0] as AutomationSettings;
    mqttSettings = results[1] as MqttSettings;
    flows = results[2] as List<AutomationFlow>;
    isBootstrapped = true;
    notifyListeners();

    ble.addListener(_onBleStateChanged);
    ble.onStatus = _onBleStatus;

    await history.init();
    _lastKnownHistoryCount = history.entries.length;
    history.addListener(_onHistoryChanged);

    await energyLog.init();
    tapoDevices.addListener(_onTapoDevicesChanged);
    await tapoDevices.init();

    await _flowEngine.init(flows);
    await ble.init();
    if (mqttSettings.mode == AppMode.client) {
  await ble.pause();   // ← don't hold a BLE link in client mode
}

    mqtt.onCommand = _onMqttCommand;
    mqtt.onFlowsReceived = _onMqttFlowsReceived;
    mqtt.onHistoryReceived = _onMqttHistoryReceived;
    mqtt.onRpcRequest = _onRpcRequest;
    mqtt.onTapoDevicesReceived = _onTapoDevicesReceived;
    mqtt.onConnected = _onMqttConnected;

    await mqtt.configure(mqttSettings);

    if (mqttSettings.mode != AppMode.client) {
      await ForegroundService.start();
      await ForegroundService.requestBatteryOptimizationExemption();
    }

    _flowEvalTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mqttSettings.mode != AppMode.client) {
        _flowEngine.evaluate(flows);
      }
    });

    _mqttHeartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mqttSettings.mode == AppMode.gateway && mqtt.isConnected) {
        mqtt.publishStatus(ble.status, bleConnected: ble.isConnected);
      }
    });
  }

  // ── Permissions ────────────────────────────────────────────────────────────

  Future<void> _requestPermissions() async {
    final permissions = [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
      if (Platform.isAndroid) Permission.notification,
    ];
    final statuses = await permissions.request();
    final denied = statuses.values.any((s) => s.isPermanentlyDenied);
    if (denied != permissionsPermanentlyDenied) {
      permissionsPermanentlyDenied = denied;
      // No notifyListeners() here — called before isBootstrapped is set,
      // so MainShell is still showing the loading screen.
    }
  }

  // ── BLE callbacks ──────────────────────────────────────────────────────────

  void _onBleStatus(PowerStationStatus status) {
    notifications.handleBatteryLevel(status.batteryLevel);

    if (mqttSettings.mode != AppMode.client) {
      _flowEngine.evaluate(flows);
    }

    energyLog.recordSample(status);
    ForegroundService.updateStatus(connected: true, status: status);

    if (mqttSettings.mode == AppMode.gateway) {
      final now = DateTime.now();
      final stateChanged = _lastAcState == null ||
          status.isAcOn != _lastAcState ||
          status.isDcOn != _lastDcState ||
          status.isUsbOn != _lastUsbState;

      if (stateChanged ||
          _lastMqttPublishTime == null ||
          now.difference(_lastMqttPublishTime!).inSeconds >= 5) {
        mqtt.publishStatus(status, bleConnected: ble.isConnected && !ble.isStale);
        _lastMqttPublishTime = now;
        _lastAcState = status.isAcOn;
        _lastDcState = status.isDcOn;
        _lastUsbState = status.isUsbOn;
      }
    }
  }

  void _onBleStateChanged() {
    ForegroundService.updateStatus(
      connected: ble.isConnected,
      status: ble.isConnected ? ble.status : null,
    );

    if (mqttSettings.mode != AppMode.gateway) return;

    if (!ble.isConnected) {
      mqtt.publishStatus(ble.status, bleConnected: false);

      // FIX: reset throttle state so the first real status packet after
      // reconnect is always published immediately. Without this reset,
      // _lastMqttPublishTime holds a recent timestamp and the stale-state
      // guard suppresses the first post-reconnect publish for up to 5 s,
      // leaving MQTT clients with an outdated view of the station.
      _lastMqttPublishTime = null;
      _lastAcState = null;
      _lastDcState = null;
      _lastUsbState = null;
    } else {
      // FIX: publish immediately on reconnect too, not just on disconnect.
      // Without this, clients can sit on a stale bleConnected:false for up
      // to 30s (until the next heartbeat tick) after the gateway already
      // recovered — a reconnect packet with values identical to before the
      // drop never triggers a publish via the normal change-detection path
      // in _onBleStatus, since nothing about the *data* changed.
      mqtt.publishStatus(ble.status, bleConnected: !ble.isStale);
      _lastMqttPublishTime = DateTime.now();
      _lastAcState = ble.status.isAcOn;
      _lastDcState = ble.status.isDcOn;
      _lastUsbState = ble.status.isUsbOn;
    }
  }

  // ── History listener ───────────────────────────────────────────────────────

  void _onHistoryChanged() {
    if (mqttSettings.mode != AppMode.gateway) return;
    final entries = history.entries;
    if (entries.length > _lastKnownHistoryCount && entries.isNotEmpty) {
      mqtt.publishHistoryEntry(entries.first);
      mqtt.publishHistorySnapshot(entries);
    }
    _lastKnownHistoryCount = entries.length;
  }

  // ── Tapo polling callback ──────────────────────────────────────────────────

  void _onTapoDevicesChanged() {
    if (mqttSettings.mode != AppMode.client) {
      _flowEngine.evaluateTapoTriggers(flows);
    }
    if (mqttSettings.mode == AppMode.gateway) {
      _publishTapoDevices();
    }
  }

  // ── MQTT callbacks ─────────────────────────────────────────────────────────

  /// Handles both the fire-and-forget `<prefix>/cmd/+` topic and the
  /// `outlet.set` RPC. Waits for the station's own status broadcast to
  /// confirm the change actually took effect, rather than trusting the
  /// characteristic write alone — a plug/relay can silently fail to apply
  /// a command even when the BLE write itself succeeds.
  Future<bool> _onMqttCommand(String outlet, bool value) async {
    if (mqttSettings.mode != AppMode.gateway) return false;
    if (!ble.isConnected) return false;
    final confirmed = switch (outlet) {
      'usb' => await ble.setUsbConfirmed(value),
      'ac' => await ble.setAcConfirmed(value),
      'dc' => await ble.setDcConfirmed(value),
      _ => false,
    };
    if (!confirmed) {
      Log.w('AppCoordinator',
          'Outlet "$outlet" command not confirmed by station');
    }
    return confirmed;
  }

  void _onTapoDevicesReceived(List<TapoDevice> devices) {
    if (mqttSettings.mode != AppMode.client) return;
    tapoDevices.replaceAll(devices);
  }

  /// Called by [MqttService] the instant a (re)connection succeeds — the
  /// initial connect and every automatic reconnect alike.
  ///
  /// On the gateway, this forces a full state re-publish: status, Tapo
  /// devices, and a full history snapshot. This is what actually fixes a
  /// client "stuck on an old state that a restart doesn't clear" — that
  /// symptom means the client is reading a stale *retained* broker message,
  /// which a client-side restart can never fix by itself since the client
  /// has no state of its own to discard; only a fresh publish from the
  /// gateway can replace what the broker is holding. Previously the gateway
  /// only republished when something happened to change, so a broker
  /// restart (which can wipe retained messages) or a flaky reconnect could
  /// leave clients with nothing current until the station's state next
  /// happened to change on its own.
  void _onMqttConnected() {
    if (mqttSettings.mode != AppMode.gateway) return;
    _lastMqttPublishTime = null;
    _lastAcState = null;
    _lastDcState = null;
    _lastUsbState = null;
    mqtt.publishStatus(ble.status, bleConnected: ble.isConnected && !ble.isStale,);
    _publishTapoDevices();
    mqtt.publishHistorySnapshot(history.entries);
  }

  Future<dynamic> _onRpcRequest(
    String method,
    Map<String, dynamic> params,
  ) async {
    switch (method) {
      case RpcMethod.setOutlet:
        final outlet = params['outlet'] as String;
        final value = params['value'] as bool;
        final confirmed = await _onMqttCommand(outlet, value);
        if (!confirmed) {
          throw StateError(
              'Outlet "$outlet" was not confirmed by the station');
        }
        return {'outlet': outlet, 'value': value};

      case RpcMethod.tapoSetOn:
        final deviceId = params['deviceId'] as String;
        final on = params['on'] as bool;
        final ok = await tapoDevices.setDeviceOn(deviceId, on);
        _publishTapoDevices();
        return {'ok': ok};

      case RpcMethod.tapoRefresh:
        await tapoDevices.refresh();
        _publishTapoDevices();
        return {'count': tapoDevices.devices.length};

      case RpcMethod.flowsReplace:
        final raw = params['flows'] as List<dynamic>;
        final updated = raw
            .map((j) =>
                AutomationFlow.tryFromJson(j as Map<String, dynamic>))
            .whereType<AutomationFlow>()
            .toList();
        await _applyFlows(updated);
        return {'count': updated.length};

      case RpcMethod.flowSetEnabled:
        final flowId = params['flowId'] as String;
        final enabled = params['enabled'] as bool;
        final updated = flows
            .map((f) => f.id == flowId ? f.copyWith(enabled: enabled) : f)
            .toList();
        await _applyFlows(updated);
        return {'ok': true};

      case RpcMethod.flowDelete:
        final flowId = params['flowId'] as String;
        final updated = flows.where((f) => f.id != flowId).toList();
        await _applyFlows(updated);
        return {'ok': true};

      case RpcMethod.flowRun:
        final flowId = params['flowId'] as String;
        final flow = flows.firstWhere((f) => f.id == flowId);
        _flowEngine.resetTriggeredForFlow(flowId);
        await _flowEngine.evaluateOnce(flow);
        return {'ok': true};

      case RpcMethod.historyClear:
        await history.clear();
        return {'ok': true};

      default:
        throw ArgumentError('Unknown RPC method: $method');
    }
  }

  void _publishTapoDevices() {
    if (!mqtt.isConnected) return;
    mqtt.publishTapoDevices(tapoDevices.devices);
  }

  // ── Settings mutations (called by the UI) ──────────────────────────────────

  Future<void> onSettingsChanged(AutomationSettings updated) async {
    settings = updated;
    notifyListeners();
    await _repos.automationSettings.save(updated);
  }

  Future<void> onMqttSettingsChanged(MqttSettings updated) async {
    final wasClient = mqttSettings.mode == AppMode.client;
    final nowClient = updated.mode == AppMode.client;

    mqttSettings = updated;
    notifyListeners();

    await _repos.mqttSettings.save(updated);
    await mqtt.configure(updated);

    if (!wasClient && nowClient) {
      await ble.pause();  
      await ForegroundService.stop();
    } else if (wasClient && !nowClient) {
      await ble.resume();   
      tapoDevices.resumeLocalPolling();
      await ForegroundService.start();
      await ForegroundService.requestBatteryOptimizationExemption();
    }
  }

  Future<void> onFlowsChanged(List<AutomationFlow> updated) async {
    await _applyFlows(updated);
    if (!_applyingRemoteFlows && mqttSettings.mode != AppMode.standalone) {
      mqtt.publishFlows(updated);
    }
  }

  // ── MQTT flow sync ─────────────────────────────────────────────────────────

  Future<void> _onMqttFlowsReceived(List<AutomationFlow> incoming) async {
    if (_applyingRemoteFlows) return;
    _applyingRemoteFlows = true;
    try {
      await _applyFlows(incoming);
    } finally {
      _applyingRemoteFlows = false;
    }
  }

  Future<void> _onMqttHistoryReceived(
      List<AutomationHistoryEntry> entries) async {
    if (mqttSettings.mode != AppMode.client) return;
    if (entries.length == 1) {
      await history.addEntry(entries.first);
    } else {
      await history.replaceAll(entries);
    }
  }

  // ── Flow application ───────────────────────────────────────────────────────

  Future<void> _applyFlows(List<AutomationFlow> updated) async {
    // Inform the engine about deleted flows so it can clean up trigger state.
    final deletedIds = flows
        .map((f) => f.id)
        .toSet()
        .difference(updated.map((f) => f.id).toSet());
    for (final id in deletedIds) {
      await _flowEngine.onFlowDeleted(id);
    }

    // Initialise the engine for newly added flows.
    final addedIds = updated
        .map((f) => f.id)
        .toSet()
        .difference(flows.map((f) => f.id).toSet());
    for (final flow in updated.where((f) => addedIds.contains(f.id))) {
      await _flowEngine.init([flow]);
    }

    flows = updated;
    notifyListeners();
    await _repos.flows.saveFlows(updated);
  }

  // ── Derived helpers ────────────────────────────────────────────────────────

  /// Number of bottom-nav tabs for the current mode.
  int get tabCount => mqttSettings.mode == AppMode.client ? 4 : 5;

  // ── Dispose ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _flowEvalTimer?.cancel();
    _mqttHeartbeatTimer?.cancel();

    history.removeListener(_onHistoryChanged);
    tapoDevices.removeListener(_onTapoDevicesChanged);
    ble.removeListener(_onBleStateChanged);

    ble.onStatus = null;
    mqtt.onCommand = null;
    mqtt.onFlowsReceived = null;
    mqtt.onHistoryReceived = null;
    mqtt.onRpcRequest = null;
    mqtt.onTapoDevicesReceived = null;
    mqtt.onConnected = null;

    ble.dispose();
    history.dispose();
    energyLog.dispose();
    tapoDevices.dispose();
    tapo.dispose();
    mqtt.dispose();

    super.dispose();
  }
}