import 'dart:async';

import 'package:flutter/material.dart';

import '../models/automation_flow.dart';
import '../models/automation_history_entry.dart';
import '../models/automation_settings.dart';
import '../models/tapo_device.dart';
import '../repositories/flow_repository.dart';
import '../utils/logger.dart';
import 'ble_service.dart';
import 'history_service.dart';
import 'tapo_device_service.dart';
import 'tapo_service.dart';
import 'webhook_service.dart';

/// Evaluates user-defined [AutomationFlow]s against live BLE status and
/// Tapo plug states, then executes their action sequences.
///
/// ## Trigger guards
/// Each flow uses an edge-triggered guard ([_triggered]) — it fires once when
/// the condition first becomes true and is suppressed until the condition resets.
/// The guard is persisted to [FlowRepository] so a restart mid-cycle does not
/// re-fire an already-handled event.
///
/// ## Tapo plug state trigger
/// For [FlowTriggerType.tapoPlugState] the engine checks whether the named
/// plug is in the expected state AND the current time is inside the window.
///
/// ## Concurrency
/// Flows run independently via [unawaited]; a per-flow [_running] lock
/// prevents the same flow from overlapping itself.
final class FlowEngine {
  FlowEngine(
    this._ble,
    this._webhooks,
    this._tapo,
    this._tapoDevices,
    this._history,
    this._flowRepository,
  );

  final BleService         _ble;
  final WebhookService     _webhooks;
  final TapoService        _tapo;
  final TapoDeviceService  _tapoDevices;
  final HistoryService     _history;
  final FlowRepository     _flowRepository;

  final Map<String, bool> _triggered = {};
  final Map<String, bool> _running   = {};
  bool _initialized = false;

  // ── Bootstrap ──────────────────────────────────────────────────────────────

  Future<void> init(List<AutomationFlow> flows) async {
    for (final flow in flows) {
      _triggered[flow.id] = await _flowRepository.getFlowTriggered(flow.id);
    }
    _initialized = true;
    Log.i('FlowEngine', 'init — ${flows.length} flow(s) loaded');
  }

  // ── Evaluation (called on BLE status update) ───────────────────────────────

  Future<void> evaluate(
    List<AutomationFlow> flows,
    AutomationSettings settings,
  ) async {
    if (!_initialized) return;
    for (final flow in flows) {
      if (!flow.enabled) continue;
      unawaited(_evaluateFlow(flow, settings));
    }
  }

  /// Evaluates Tapo-plug-state triggers. Called by [TapoDeviceService]
  /// after every poll cycle so plug-state changes are detected promptly.
  Future<void> evaluateTapoTriggers(
    List<AutomationFlow> flows,
    AutomationSettings settings,
  ) async {
    if (!_initialized) return;
    for (final flow in flows) {
      if (!flow.enabled) continue;
      if (flow.trigger.type != FlowTriggerType.tapoPlugState) continue;
      unawaited(_evaluateFlow(flow, settings));
    }
  }

  Future<void> _evaluateFlow(
    AutomationFlow flow,
    AutomationSettings settings,
  ) async {
    if (_running[flow.id] == true) return;

    // ── Time window guard ──────────────────────────────────────────────────
    if (!flow.trigger.isTimeInWindow(TimeOfDay.now())) {
      await _setTriggered(flow.id, false);
      return;
    }

    bool shouldFire  = false;
    bool shouldReset = false;

    switch (flow.trigger.type) {
      case FlowTriggerType.batteryFallsBelow:
        final level = _ble.status.batteryLevel;
        if (level <= 0) return;
        shouldFire  = level <= flow.trigger.threshold && _triggered[flow.id] != true;
        shouldReset = level >  flow.trigger.threshold;

      case FlowTriggerType.batteryRisesAbove:
        final level = _ble.status.batteryLevel;
        if (level <= 0) return;
        shouldFire  = level >= flow.trigger.threshold && _triggered[flow.id] != true;
        shouldReset = level <  flow.trigger.threshold;

      case FlowTriggerType.tapoPlugState:
        final deviceId    = flow.trigger.tapoDeviceId;
        final expectedOn  = flow.trigger.tapoExpectedOn;
        if (deviceId == null || deviceId.isEmpty || expectedOn == null) return;

        final device = _tapoDevices.getDevice(deviceId);
        if (device == null || !device.isOnline) return;

        final isInWrongState = device.isOn != expectedOn;
        shouldFire  = isInWrongState && _triggered[flow.id] != true;
        shouldReset = !isInWrongState;
    }

    if (shouldReset) await _setTriggered(flow.id, false);
    if (!shouldFire) return;

    await _setTriggered(flow.id, true);
    _running[flow.id] = true;
    Log.i('FlowEngine', 'Firing "${flow.name}" (trigger: ${flow.trigger.type.name})');

    try {
      final triggerLevel = _ble.status.batteryLevel;
      for (final action in flow.actions) {
        await _execute(action, settings, triggerLevel, flow.name);
      }
      Log.i('FlowEngine', '"${flow.name}" completed');
    } catch (e) {
      Log.e('FlowEngine', 'Error in flow "${flow.name}"', e);
    } finally {
      _running[flow.id] = false;
    }
  }

  // ── Action execution ───────────────────────────────────────────────────────

  Future<void> _execute(
    FlowAction action,
    AutomationSettings settings,
    int triggerLevel,
    String flowName,
  ) async {
    switch (action.type) {
      case FlowActionType.wait:
        Log.d('FlowEngine', 'wait ${action.waitSeconds}s');
        await Future<void>.delayed(Duration(seconds: action.waitSeconds));

      case FlowActionType.setBleOutlet:
        switch (action.outlet) {
          case BleOutlet.usb: await _ble.setUsb(action.outletOn);
          case BleOutlet.ac:  await _ble.setAc(action.outletOn);
          case BleOutlet.dc:  await _ble.setDc(action.outletOn);
        }
        Log.d('FlowEngine', '${action.outlet.name} → ${action.outletOn ? "ON" : "OFF"}');
        await _history.addEntry(AutomationHistoryEntry(
          timestamp:    DateTime.now(),
          action:       HistoryAction.outletToggled,
          batteryLevel: triggerLevel,
          success:      true,
          method:       ActivationMethod.bleOutlet,
          flowName:     flowName,
          deviceName:   action.outlet.name.toUpperCase(),
        ));

      case FlowActionType.fireWebhook:
        if (action.webhookUrl.isEmpty) {
          Log.w('FlowEngine', 'fireWebhook: empty URL — skipping');
          return;
        }
        final ok = await _webhooks.fire(action.webhookUrl);
        Log.d('FlowEngine', 'webhook ${ok ? "OK" : "FAILED"}');
        await _history.addEntry(AutomationHistoryEntry(
          timestamp:    DateTime.now(),
          action:       HistoryAction.webhookFired,
          batteryLevel: triggerLevel,
          success:      ok,
          method:       ActivationMethod.webhook,
          flowName:     flowName,
        ));

      case FlowActionType.controlTapo:
        await _executeTapoAction(action, triggerLevel, flowName);
    }
  }

  Future<void> _executeTapoAction(
    FlowAction action,
    int triggerLevel,
    String flowName,
  ) async {
    if (action.tapoDeviceId.isEmpty) {
      Log.w('FlowEngine',
          'controlTapo: no device ID set on action in "$flowName" — skipping. '
          'Open the flow editor and select a Tapo device.');
      return;
    }

    final device = _tapoDevices.getDevice(action.tapoDeviceId);
    if (device == null) {
      Log.w('FlowEngine', 'controlTapo: device ${action.tapoDeviceId} not found');
      return;
    }

    _tapo.resetSession(ip: device.ip, email: device.email);
    final ok = await _tapo.setOn(
      ip:       device.ip,
      email:    device.email,
      password: device.password,
      on:       action.tapoOn,
    );
    Log.i('FlowEngine',
        'Tapo "${device.name}" ${action.tapoOn ? "ON" : "OFF"}: ${ok ? "OK" : "FAILED"}');
    await _history.addEntry(AutomationHistoryEntry(
      timestamp:    DateTime.now(),
      action:       action.tapoOn ? HistoryAction.tapoOn : HistoryAction.tapoOff,
      batteryLevel: triggerLevel,
      success:      ok,
      method:       ActivationMethod.localTapo,
      flowName:     flowName,
      deviceName:   device.name,
    ));
  }

  // ── Persistence helpers ────────────────────────────────────────────────────

  Future<void> _setTriggered(String flowId, bool value) async {
    if (_triggered[flowId] == value) return;
    _triggered[flowId] = value;
    await _flowRepository.setFlowTriggered(flowId, value);
  }

  Future<void> onFlowDeleted(String flowId) async {
    _triggered.remove(flowId);
    _running.remove(flowId);
    await _flowRepository.clearFlowTriggered(flowId);
  }

  void resetAll() {
    for (final id in _triggered.keys) {
      _triggered[id] = false;
      unawaited(_flowRepository.setFlowTriggered(id, false));
    }
  }
}