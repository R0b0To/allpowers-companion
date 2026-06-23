import 'package:flutter/material.dart';

import '../models/automation_history_entry.dart';
import '../models/automation_settings.dart';
import '../utils/logger.dart';
import 'ble_service.dart';
import 'history_service.dart';
import 'storage_service.dart';
import 'tapo_service.dart';
import 'webhook_service.dart';

/// Implements the "smart charging" automation loop.
final class AutomationEngine {
  AutomationEngine(
    this._ble,
    this._webhooks,
    this._tapo,
    this._storage,
    this._history,
  );

  final BleService _ble;
  final WebhookService _webhooks;
  final TapoService _tapo;
  final StorageService _storage;
  final HistoryService _history;

  bool _chargingTriggered = false;
  bool _fullyChargedHandled = false;
  bool _sequenceRunning = false;
  bool _initialized = false;

  /// Must be called once before [evaluate] to restore the persisted state.
  Future<void> init() async {
    _chargingTriggered = await _storage.getChargingTriggered();
    _initialized = true;
    Log.i('AutomationEngine', 'init — chargingTriggered=$_chargingTriggered');
  }

  /// Evaluates the current battery level against the automation rules.
  Future<void> evaluate(AutomationSettings settings) async {
    if (!_initialized || !settings.enabled) return;

    final level = _ble.status.batteryLevel;
    if (level <= 0) return;

    final inWindow = settings.isTimeInWindow(TimeOfDay.now());

    // Re-arm high-threshold guard when level drops back below limit.
    if (level < settings.highThreshold) {
      _fullyChargedHandled = false;
    }

    if (inWindow) {
      // ── Normal window logic ──────────────────────────────────────────────
      if (level <= settings.lowThreshold &&
          !_chargingTriggered &&
          !_sequenceRunning) {
        await _runLowBatterySequence(settings);
        return;
      }

      if (level >= settings.highThreshold && !_fullyChargedHandled && !_sequenceRunning) {
        await _runFullyChargedSequence(settings);
      }
    } else {
      // ── Outside window: ensure plug is on ───────────────────────────────
      if (!_chargingTriggered && !_sequenceRunning) {
        _sequenceRunning = true; // Guard against overlapping evaluations
        try {
          // Clear any stale session before checking the state
          if (settings.hasLocalTapoCredentials) {
            _tapo.resetSession(ip: settings.tapoIp, email: settings.tapoEmail);
          }

          final alreadyOn = settings.hasLocalTapoCredentials
              ? await _tapo.isOn(
                  ip: settings.tapoIp,
                  email: settings.tapoEmail,
                  password: settings.tapoPassword,
                )
              : null; // webhooks can't query state, assume needs triggering

          if (alreadyOn == true) {
            Log.i('AutomationEngine', 'Outside window — plug already ON, syncing flag');
            _chargingTriggered = true;
            await _storage.setChargingTriggered(true);
          } else {
            Log.i('AutomationEngine', 'Outside window — plug is OFF, starting charge');
            _sequenceRunning = false; // Reset so sequence can manage lifecycle
            await _runLowBatterySequence(settings);
          }
        } catch (e) {
          Log.e('AutomationEngine', 'Error checking plug state outside window', e);
        } finally {
          _sequenceRunning = false;
        }
      }
    }
  }

  // ── Low battery sequence ───────────────────────────────────────────────────

  Future<void> _runLowBatterySequence(AutomationSettings settings) async {
    _sequenceRunning = true;
    final triggerLevel = _ble.status.batteryLevel;

    _chargingTriggered = true;
    await _storage.setChargingTriggered(true);
    Log.i('AutomationEngine', 'Low threshold reached — starting charge sequence');

    try {
      // Step 1: Cut AC to isolate the load before the charger powers up.
      if (_ble.status.isAcOn) {
        await _ble.setAc(false);
        Log.d('AutomationEngine', 'AC outlets cut');
      }

      // Step 2: Let the relay fully open before the charger energises.
      await Future<void>.delayed(const Duration(seconds: 5));

      // Step 3: Activate the charger.
      final (success, method) = await _activatePlug(settings, on: true);
      await _history.addEntry(AutomationHistoryEntry(
        timestamp: DateTime.now(),
        action: HistoryAction.turnOn,
        batteryLevel: triggerLevel,
        success: success,
        method: method,
      ));

      if (!success) {
        // Recover: Reset flags so the engine will retry on the next evaluation.
        _chargingTriggered = false;
        await _storage.setChargingTriggered(false);
        Log.w('AutomationEngine', 'Low-battery sequence failed to activate plug. Retrying on next update.');
        return;
      }

      // Step 4: Give the charger time to complete its power-delivery handshake.
      await Future<void>.delayed(const Duration(seconds: 10));

      // Step 5: Restore AC (station is now being charged).
      if (!_ble.status.isAcOn) {
        await _ble.setAc(true);
        Log.d('AutomationEngine', 'AC outlets restored');
      }
    } catch (e) {
      Log.e('AutomationEngine', 'Critical error in low-battery sequence', e);
      _chargingTriggered = false;
      await _storage.setChargingTriggered(false);
    } finally {
      _sequenceRunning = false;
    }
  }

  // ── Fully charged sequence ─────────────────────────────────────────────────

  Future<void> _runFullyChargedSequence(AutomationSettings settings) async {
    _sequenceRunning = true;
    Log.i('AutomationEngine', 'High threshold reached — stopping charge');

    final triggerLevel = _ble.status.batteryLevel;

    _chargingTriggered = false;
    await _storage.setChargingTriggered(false);

    try {
      // Ensure AC is on (it should be, but guard against edge cases).
      if (!_ble.status.isAcOn) {
        await _ble.setAc(true);
      }

      final (success, method) = await _activatePlug(settings, on: false);
      await _history.addEntry(AutomationHistoryEntry(
        timestamp: DateTime.now(),
        action: HistoryAction.turnOff,
        batteryLevel: triggerLevel,
        success: success,
        method: method,
      ));

      if (success) {
        _fullyChargedHandled = true;
      } else {
        // Recover: Revert flags on failure so it can re-attempt on the next update.
        _chargingTriggered = true;
        await _storage.setChargingTriggered(true);
        _fullyChargedHandled = false;
        Log.w('AutomationEngine', 'Failed to deactivate plug. Retrying on next update.');
      }
    } catch (e) {
      Log.e('AutomationEngine', 'Critical error in fully charged sequence', e);
      _chargingTriggered = true;
      await _storage.setChargingTriggered(true);
      _fullyChargedHandled = false;
    } finally {
      _sequenceRunning = false;
    }
  }

  // ── Shared plug control with fallback ─────────────────────────────────────

  Future<(bool success, ActivationMethod method)> _activatePlug(
    AutomationSettings settings, {
    required bool on,
  }) async {
    final action = on ? 'ON' : 'OFF';

    if (settings.hasLocalTapoCredentials) {
      // Corrected: Clear cached session before state changes as intended.
      _tapo.resetSession(ip: settings.tapoIp, email: settings.tapoEmail);
      Log.d('AutomationEngine', 'Attempting local Tapo $action');
      final success = await _tapo.setOn(
        ip: settings.tapoIp,
        email: settings.tapoEmail,
        password: settings.tapoPassword,
        on: on,
      );
      if (success) {
        Log.i('AutomationEngine', 'Local Tapo $action succeeded');
        return (true, ActivationMethod.localTapo);
      }
      Log.w('AutomationEngine', 'Local Tapo $action failed — falling back to webhook');
    }

    final webhookUrl = on ? settings.tapoOnUrl : settings.tapoOffUrl;
    if (webhookUrl.isNotEmpty) {
      Log.d('AutomationEngine', 'Firing $action webhook');
      try {
        final success = await _webhooks.fire(webhookUrl);
        if (success) {
          Log.i('AutomationEngine', '$action webhook succeeded');
        } else {
          Log.w('AutomationEngine', '$action webhook failed');
        }
        return (success, ActivationMethod.webhook);
      } catch (e) {
        Log.e('AutomationEngine', '$action webhook thrown exception', e);
        return (false, ActivationMethod.webhook);
      }
    }

    Log.w('AutomationEngine', 'No $action action configured');
    return (false, ActivationMethod.none);
  }

  // ── Debug accessors (AutomationTestScreen only) ───────────────────────────

  bool get debugInitialized => _initialized;
  bool get debugChargingTriggered => _chargingTriggered;
  bool get debugSequenceRunning => _sequenceRunning;
  bool get debugFullyChargedHandled => _fullyChargedHandled;

  Future<void> debugResetState() async {
    _chargingTriggered = false;
    _fullyChargedHandled = false;
    await _storage.setChargingTriggered(false);
    Log.i('AutomationEngine', 'debug: state reset by test screen');
  }
}