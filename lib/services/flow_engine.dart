import 'dart:async';

import 'package:flutter/material.dart';

import '../models/automation_flow.dart';
import '../models/automation_history_entry.dart';
import '../models/automation_settings.dart';
import '../utils/logger.dart';
import 'ble_service.dart';
import 'history_service.dart';
import 'storage_service.dart';
import 'tapo_service.dart';
import 'webhook_service.dart';

/// Evaluates user-defined [AutomationFlow]s against live BLE status and
/// executes their action sequences.
///
/// ## Trigger guards
/// Each flow uses an edge-triggered guard ([_triggered]) — it fires once when
/// the condition first becomes true and is suppressed until the battery moves
/// back past the threshold. The guard is persisted to [StorageService] so
/// a restart mid-cycle does not re-fire an already-handled event.
///
/// ## Concurrency
/// Flows run independently via [unawaited]; a per-flow [_running] lock
/// prevents the same flow from overlapping itself when BLE packets arrive
/// faster than a sequence with [wait] steps can complete.
final class FlowEngine {
  FlowEngine(
    this._ble,
    this._webhooks,
    this._tapo,
    this._history,
    this._storage,
  );

  final BleService _ble;
  final WebhookService _webhooks;
  final TapoService _tapo;
  final HistoryService _history;
  final StorageService _storage;

  final Map<String, bool> _triggered = {};
  final Map<String, bool> _running = {};
  bool _initialized = false;

  // ── Bootstrap ──────────────────────────────────────────────────────────────

  /// Restore persisted trigger states. Must be called once after flows are loaded.
  Future<void> init(List<AutomationFlow> flows) async {
    for (final flow in flows) {
      _triggered[flow.id] = await _storage.getFlowTriggered(flow.id);
    }
    _initialized = true;
    Log.i('FlowEngine', 'init — ${flows.length} flow(s) loaded');
  }

  // ── Evaluation ─────────────────────────────────────────────────────────────

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

  Future<void> _evaluateFlow(
    AutomationFlow flow,
    AutomationSettings settings,
  ) async {
    if (_running[flow.id] == true) return;

    final level = _ble.status.batteryLevel;
    if (level <= 0) return;

    if (!flow.trigger.isTimeInWindow(TimeOfDay.now())) {
      await _setTriggered(flow.id, false);
      return;
    }

    final bool shouldFire;
    final bool shouldReset;

    switch (flow.trigger.type) {
      case FlowTriggerType.batteryFallsBelow:
        shouldFire =
            level <= flow.trigger.threshold && _triggered[flow.id] != true;
        shouldReset = level > flow.trigger.threshold;
      case FlowTriggerType.batteryRisesAbove:
        shouldFire =
            level >= flow.trigger.threshold && _triggered[flow.id] != true;
        shouldReset = level < flow.trigger.threshold;
    }

    if (shouldReset) await _setTriggered(flow.id, false);
    if (!shouldFire) return;

    await _setTriggered(flow.id, true);
    _running[flow.id] = true;
    Log.i('FlowEngine', 'Firing "${flow.name}" at battery $level%');

    try {
      final triggerLevel = level;
      for (final action in flow.actions) {
        await _execute(action, settings, triggerLevel);
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
  ) async {
    switch (action.type) {
      case FlowActionType.wait:
        Log.d('FlowEngine', 'wait ${action.waitSeconds}s');
        await Future<void>.delayed(Duration(seconds: action.waitSeconds));

      case FlowActionType.setBleOutlet:
        switch (action.outlet) {
          case BleOutlet.usb:
            await _ble.setUsb(action.outletOn);
          case BleOutlet.ac:
            await _ble.setAc(action.outletOn);
          case BleOutlet.dc:
            await _ble.setDc(action.outletOn);
        }
        Log.d('FlowEngine',
            '${action.outlet.name} → ${action.outletOn ? "ON" : "OFF"}');

      case FlowActionType.fireWebhook:
        if (action.webhookUrl.isEmpty) {
          Log.w('FlowEngine', 'fireWebhook: empty URL — skipping');
          return;
        }
        final ok = await _webhooks.fire(action.webhookUrl);
        Log.d('FlowEngine', 'webhook ${ok ? "OK" : "FAILED"}');
        await _history.addEntry(AutomationHistoryEntry(
          timestamp: DateTime.now(),
          action: HistoryAction.turnOn,
          batteryLevel: triggerLevel,
          success: ok,
          method: ActivationMethod.webhook,
        ));

      case FlowActionType.controlTapo:
        if (!settings.hasLocalTapoCredentials) {
          Log.w('FlowEngine', 'controlTapo: no credentials — skipping');
          return;
        }
        _tapo.resetSession(ip: settings.tapoIp, email: settings.tapoEmail);
        final ok = await _tapo.setOn(
          ip: settings.tapoIp,
          email: settings.tapoEmail,
          password: settings.tapoPassword,
          on: action.tapoOn,
        );
        Log.i('FlowEngine',
            'Tapo ${action.tapoOn ? "ON" : "OFF"}: ${ok ? "OK" : "FAILED"}');
        await _history.addEntry(AutomationHistoryEntry(
          timestamp: DateTime.now(),
          action: action.tapoOn ? HistoryAction.turnOn : HistoryAction.turnOff,
          batteryLevel: triggerLevel,
          success: ok,
          method: ActivationMethod.localTapo,
        ));
    }
  }

  // ── Persistence helpers ────────────────────────────────────────────────────

  Future<void> _setTriggered(String flowId, bool value) async {
    if (_triggered[flowId] == value) return;
    _triggered[flowId] = value;
    await _storage.setFlowTriggered(flowId, value);
  }

  /// Call when a flow is deleted to avoid leaving orphaned storage keys.
  Future<void> onFlowDeleted(String flowId) async {
    _triggered.remove(flowId);
    _running.remove(flowId);
    await _storage.clearFlowTriggered(flowId);
  }

  void resetAll() {
    for (final id in _triggered.keys) {
      _triggered[id] = false;
      unawaited(_storage.setFlowTriggered(id, false));
    }
  }
}