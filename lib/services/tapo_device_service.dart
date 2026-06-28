import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/tapo_device.dart';
import '../repositories/tapo_repository.dart';
import '../utils/logger.dart';
import 'tapo_service.dart';

/// Manages the list of saved Tapo smart plugs, polls their live state,
/// and exposes toggle commands.
///
/// ## Local vs. client mode
/// In gateway/standalone mode, [init] loads devices from the repository and
/// starts the background poll timer. Each poll calls [TapoService] directly.
///
/// In client mode, [MainShell] calls [replaceAll] with device snapshots
/// received via MQTT. The poll timer is NOT started in this case — state
/// comes entirely from the gateway's publish. [setDeviceOn] should NOT be
/// called directly in client mode; use the RPC layer instead.
///
/// [replaceAll] sets [_mqttDriven] which suspends any locally-running poll
/// timer so that stale direct-poll data cannot overwrite gateway-provided
/// state.
final class TapoDeviceService extends ChangeNotifier {
  TapoDeviceService(this._tapo, this._repository);

  final TapoService _tapo;
  final TapoRepository _repository;

  static const pollInterval = Duration(seconds: 30);

  List<TapoDevice> _devices = [];
  bool _isLoaded = false;
  bool _mqttDriven = false;
  Timer? _pollTimer;

  List<TapoDevice> get devices => _devices;
  bool get isLoaded => _isLoaded;

  /// True when device state is being driven by MQTT (client mode).
  /// In this state local polling is suppressed.
  bool get isMqttDriven => _mqttDriven;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Initialises the service in local (gateway/standalone) mode.
  ///
  /// Loads persisted device configs and starts the background poll timer.
  /// Do NOT call [replaceAll] after [init] in gateway mode — let the poll
  /// timer manage state.
  Future<void> init() async {
    _devices = await _repository.loadDevices();
    _isLoaded = true;
    notifyListeners();
    _startPolling();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) {
      // Skip poll cycles while MQTT is driving state.
      if (_mqttDriven) return;
      _pollAll();
    });
    // Run an immediate poll unless we are already in MQTT-driven mode.
    if (!_mqttDriven) unawaited(_pollAll());
  }

  Future<void> _pollAll() async {
    if (_devices.isEmpty) return;
    bool changed = false;

    final updated = await Future.wait(
      _devices.map((d) => _pollDevice(d)),
    );

    for (var i = 0; i < _devices.length; i++) {
      if (_devices[i].isOnline != updated[i].isOnline ||
          _devices[i].isOn != updated[i].isOn ||
          _devices[i].model != updated[i].model) {
        changed = true;
      }
    }

    if (changed) {
      _devices = updated;
      notifyListeners();
    }
  }

  Future<TapoDevice> _pollDevice(TapoDevice device) async {
    try {
      final info = await _tapo.getDeviceInfo(
        ip: device.ip,
        email: device.email,
        password: device.password,
      );
      if (info == null) return device.copyWith(isOnline: false);
      return device.copyWith(
        isOnline: true,
        isOn: info['device_on'] as bool? ?? false,
        model: info['model'] as String? ?? '',
      );
    } catch (e) {
      Log.w('TapoDeviceService', 'Poll failed for ${device.name}: $e');
      return device.copyWith(isOnline: false);
    }
  }

  // ── MQTT-driven mode ───────────────────────────────────────────────────────

  /// Replaces the full device list with a snapshot received from the gateway
  /// over MQTT. Marks the service as MQTT-driven so local polling is
  /// suppressed.
  ///
  /// Called by [MainShell._onMqttTapoDevicesReceived] in client mode.
  void replaceAll(List<TapoDevice> devices) {
    _mqttDriven = true;
    _devices = devices;
    _isLoaded = true;
    notifyListeners();
    Log.i('TapoDeviceService',
        'replaceAll: ${devices.length} device(s) received via MQTT');
  }

  /// Reverts to local polling mode. Called when switching away from client
  /// mode, e.g. after the user changes the MQTT mode setting to standalone
  /// or gateway.
  void resumeLocalPolling() {
    if (!_mqttDriven) return;
    _mqttDriven = false;
    Log.i('TapoDeviceService', 'Resuming local polling');
    unawaited(_pollAll());
  }

  // ── Device management ──────────────────────────────────────────────────────

  Future<void> addDevice(TapoDevice device) async {
    _devices = [..._devices, device];
    notifyListeners();
    await _repository.saveDevices(_devices);
    unawaited(_pollDevice(device).then((updated) {
      final idx = _devices.indexWhere((d) => d.id == updated.id);
      if (idx != -1) {
        _devices = [..._devices]..[idx] = updated;
        notifyListeners();
      }
    }));
  }

  Future<void> updateDevice(TapoDevice device) async {
    _devices = _devices.map((d) => d.id == device.id ? device : d).toList();
    _tapo.resetSession(ip: device.ip, email: device.email);
    notifyListeners();
    await _repository.saveDevices(_devices);
    unawaited(_pollAll());
  }

  Future<void> removeDevice(String id) async {
    _devices = _devices.where((d) => d.id != id).toList();
    notifyListeners();
    await _repository.saveDevices(_devices);
  }

  // ── Commands ───────────────────────────────────────────────────────────────

  /// Turns the plug on or off directly (gateway/standalone mode only).
  ///
  /// In client mode this must NOT be called directly — use the RPC layer
  /// ([MqttService.call] → [RpcMethod.tapoSetOn]) so the command is routed
  /// through the gateway that holds the BLE/LAN connection.
  ///
  /// Optimistically updates local state, then confirms via a poll.
  Future<bool> setDeviceOn(String id, bool on) async {
    final idx = _devices.indexWhere((d) => d.id == id);
    if (idx == -1) return false;

    final device = _devices[idx];

    // Optimistic update.
    _devices = [..._devices]..[idx] = device.copyWith(isOn: on);
    notifyListeners();

    final ok = await _tapo.setOn(
      ip: device.ip,
      email: device.email,
      password: device.password,
      on: on,
    );

    // Confirm with a real poll (only meaningful in local mode).
    if (!_mqttDriven) {
      final refreshed = await _pollDevice(device.copyWith(isOn: on));
      final newIdx = _devices.indexWhere((d) => d.id == id);
      if (newIdx != -1) {
        _devices = [..._devices]..[newIdx] = refreshed;
        notifyListeners();
      }
    }

    return ok;
  }

  /// Forces an immediate re-poll of all devices (local mode only).
  Future<void> refresh() => _pollAll();

  /// Returns the current state of a specific device, or null if not found.
  TapoDevice? getDevice(String id) {
    try {
      return _devices.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}