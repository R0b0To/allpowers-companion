import 'package:flutter/material.dart';

import '../models/automation_settings.dart';
import '../utils/logger.dart';
import 'ble_service.dart';
import 'storage_service.dart';
import 'tapo_service.dart';
import 'webhook_service.dart';

/// Implements the "smart charging" automation loop.
///
/// ## What it does
/// - **Low threshold → start charging**: Cut AC outlets briefly, activate the
///   smart plug (local Tapo preferred, webhook fallback), wait for the charger
///   to power up, then restore AC.
/// - **High threshold → stop charging**: Turn off the smart plug (same
///   priority order) and reset the charging-triggered flag.
///
/// ## Reconnect-safe design
/// [_chargingTriggered] is persisted to [StorageService]. If the station
/// disconnects mid-charge and reconnects at a slightly higher level, the
/// engine will not re-fire the low-battery sequence because the flag
/// survives restarts. It is only cleared when the high threshold is reached.
///
/// ## Deduplication
/// - [_chargingTriggered] deduplicates the low-threshold action.
/// - [_fullyChargedHandled] deduplicates the high-threshold action within
///   a single app session. It re-arms when the level drops back below the
///   threshold so the next full cycle can fire again. Intentionally NOT
///   persisted — the stop-charging action should always fire after the app
///   is restarted mid-cycle if the level is already at the high threshold.
/// - [_sequenceRunning] prevents overlapping low-battery sequences if BLE
///   packets arrive faster than the sequence completes (which includes
///   deliberate 5 s + 10 s delays).
final class AutomationEngine {
  AutomationEngine(
    this._ble,
    this._webhooks,
    this._tapo,
    this._storage,
  );

  final BleService _ble;
  final WebhookService _webhooks;
  final TapoService _tapo;
  final StorageService _storage;

  bool _chargingTriggered = false;
  bool _fullyChargedHandled = false;
  bool _sequenceRunning = false;
  bool _initialized = false;

  /// Must be called once before [evaluate] to restore the persisted
  /// [_chargingTriggered] flag from disk.
  Future<void> init() async {
    _chargingTriggered = await _storage.getChargingTriggered();
    _initialized = true;
    Log.i('AutomationEngine', 'init — chargingTriggered=$_chargingTriggered');
  }

  /// Evaluates the current battery level against the automation rules.
  ///
  /// Called on every BLE status update. Returns early if automation is
  /// disabled, outside the time window, or a sequence is already running.
  Future<void> evaluate(AutomationSettings settings) async {
    if (!_initialized || !settings.enabled) return;
    if (!settings.isTimeInWindow(TimeOfDay.now())) return;

    final level = _ble.status.batteryLevel;
    if (level <= 0) return; // Bogus reading — ignore.

    // Re-arm the high-threshold stop guard once level drops back below limit.
    if (level < settings.highThreshold) {
      _fullyChargedHandled = false;
    }

    // ── Low threshold: start charging ────────────────────────────────────────
    if (level <= settings.lowThreshold &&
        !_chargingTriggered &&
        !_sequenceRunning) {
      await _runLowBatterySequence(settings);
      return; // Don't also evaluate high-threshold in the same tick.
    }

    // ── High threshold: stop charging ────────────────────────────────────────
    // Intentionally NOT gated on _chargingTriggered so the charger is always
    // stopped at the limit, even if this session never saw it cross the low
    // threshold (manual plug-in, app restart mid-cycle, etc).
    if (level >= settings.highThreshold && !_fullyChargedHandled) {
      _fullyChargedHandled = true;
      await _runFullyChargedSequence(settings);
    }
  }

  // ── Low battery sequence ───────────────────────────────────────────────────

  Future<void> _runLowBatterySequence(AutomationSettings settings) async {
    _sequenceRunning = true;

    // Persist flag before any async work so a crash or disconnect mid-sequence
    // does not retrigger on reconnect.
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
      await _activatePlug(settings, on: true);

      // Step 4: Give the charger time to complete its power-delivery handshake.
      await Future<void>.delayed(const Duration(seconds: 10));

      // Step 5: Restore AC (station is now being charged).
      if (!_ble.status.isAcOn) {
        await _ble.setAc(true);
        Log.d('AutomationEngine', 'AC outlets restored');
      }
    } catch (e) {
      Log.e('AutomationEngine', 'Error in low-battery sequence', e);
    } finally {
      _sequenceRunning = false;
    }
  }

  // ── Fully charged sequence ─────────────────────────────────────────────────

  Future<void> _runFullyChargedSequence(AutomationSettings settings) async {
    Log.i('AutomationEngine', 'High threshold reached — stopping charge');

    // Reset persisted flag first so even if deactivation fails the engine
    // won't be stuck in "charging" state forever.
    _chargingTriggered = false;
    await _storage.setChargingTriggered(false);

    // Ensure AC is on (it should be, but guard against edge cases).
    if (!_ble.status.isAcOn) {
      await _ble.setAc(true);
    }

    await _activatePlug(settings, on: false);
  }

  // ── Shared plug control with fallback ─────────────────────────────────────

  Future<void> _activatePlug(AutomationSettings settings, {required bool on}) async {
    final action = on ? 'ON' : 'OFF';

    if (settings.hasLocalTapoCredentials) {
      Log.d('AutomationEngine', 'Attempting local Tapo $action');
      final success = await _tapo.setOn(
        ip: settings.tapoIp,
        email: settings.tapoEmail,
        password: settings.tapoPassword,
        on: on,
      );
      if (success) {
        Log.i('AutomationEngine', 'Local Tapo $action succeeded');
        return;
      }
      Log.w('AutomationEngine', 'Local Tapo $action failed — falling back to webhook');
    }

    final webhookUrl = on ? settings.tapoOnUrl : settings.tapoOffUrl;
    if (webhookUrl.isNotEmpty) {
      Log.d('AutomationEngine', 'Firing $action webhook');
      final success = await _webhooks.fire(webhookUrl);
      if (success) {
        Log.i('AutomationEngine', '$action webhook succeeded');
      } else {
        Log.w('AutomationEngine', '$action webhook failed');
      }
    } else {
      Log.w('AutomationEngine', 'No $action action configured');
    }
  }
}