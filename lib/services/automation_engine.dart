import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/automation_settings.dart';
import 'ble_service.dart';
import 'storage_service.dart';
import 'webhook_service.dart';
import 'tapo_service.dart'; 

/// Runs the "smart charging" handshake:
///  - When the battery drops to the configured low limit, briefly cut the
///    AC outlets, fire the local Tapo plug command (or the "charger on"
///    webhook as a fallback), wait for the plug to physically power up,
///    then restore AC.
///  - When the battery reaches the high limit, turn off the local Tapo plug
///    (or fire the "charger off" webhook as a fallback) and leave AC on.
///
/// Reconnect-safe design
/// ─────────────────────
/// [_chargingTriggered] is persisted to [StorageService] so that if the
/// station disconnects and reconnects at a slightly higher level (e.g.
/// triggered at 8 %, reconnected at 9 %) the engine does **not** fire the
/// low-battery sequence a second time. It is only cleared (both in memory
/// and on disk) once the battery actually reaches the high threshold.
///
/// [_fullyChargedHandled] is a separate, in-memory-only dedup flag for the
/// high-threshold "stop charging" sequence. It is intentionally NOT tied to
/// [_chargingTriggered]: the charger should be turned off whenever the
/// battery is at/above the high limit while in-window, regardless of
/// whether this app instance was the one that started the charge (e.g. the
/// plug was switched on manually, or the app was restarted mid-cycle). It
/// just prevents the OFF command from being re-sent on every single BLE
/// status packet while sitting at/above the threshold, and re-arms itself
/// automatically once the level dips back below the threshold so the stop
/// sequence can fire again on the next full-charge cycle.
///
/// A lock ([_sequenceRunning]) prevents two low-battery sequences from
/// overlapping if status packets arrive faster than a sequence completes.
class AutomationEngine {
  AutomationEngine(this._ble, this._webhooks, this._tapo, this._storage);

  final BleService _ble;
  final WebhookService _webhooks;
  final TapoService _tapo; // Added TapoService field
  final StorageService _storage;

  bool _chargingTriggered = false;
  bool _fullyChargedHandled = false;
  bool _sequenceRunning = false;
  bool _initialized = false;

  /// Must be called once before [evaluate] so that the persisted
  /// [_chargingTriggered] flag is loaded from disk.
  Future<void> init() async {
    _chargingTriggered = await _storage.getChargingTriggered();
    _initialized = true;
    debugPrint('AutomationEngine: init – chargingTriggered=$_chargingTriggered');
  }

  Future<void> evaluate(AutomationSettings settings) async {
    if (!_initialized) return;
    if (!settings.enabled) return;
    if (!settings.isTimeInWindow(TimeOfDay.now())) return;

    final batteryLevel = _ble.status.batteryLevel;
    if (batteryLevel <= 0) return; // ignore bogus readings

    // Re-arm the high-threshold stop sequence once the level drops back
    // below the limit, so it can fire again next time it reaches it.
    if (batteryLevel < settings.highThreshold) {
      _fullyChargedHandled = false;
    }

    // ── Low threshold: start charging ──────────────────────────────────────
    // Guard: only trigger if we haven't already done so since the last full
    // charge. This survives disconnects/reconnects because the flag is
    // persisted to disk in _runLowBatterySequence — e.g. triggered at 5%,
    // reconnected at 8% (still below the low threshold) must NOT re-fire
    // the AC-cut + charger-on sequence on top of a charge already underway.
    if (batteryLevel <= settings.lowThreshold &&
        !_chargingTriggered &&
        !_sequenceRunning) {
      await _runLowBatterySequence(settings);
    }

    // ── High threshold: stop charging ──────────────────────────────────────
    // Deliberately NOT gated on _chargingTriggered: the charger must be
    // turned off whenever the battery is at/above the limit while in-window,
    // even if this app instance never saw it cross the low threshold (manual
    // plug-in, app restart mid-cycle, etc). _fullyChargedHandled only stops
    // it firing repeatedly on every status packet while at/above the limit.
    if (batteryLevel >= settings.highThreshold && !_fullyChargedHandled) {
      _fullyChargedHandled = true;
      await _runFullyChargedSequence(settings);
    }
  }

  Future<void> _runLowBatterySequence(AutomationSettings settings) async {
    _sequenceRunning = true;

    // Persist before doing anything async so that even if we crash mid-
    // sequence or the device disconnects, we won't re-trigger on reconnect.
    _chargingTriggered = true;
    await _storage.setChargingTriggered(true);

    debugPrint('Automation: low battery threshold hit, starting sequence.');

    try {
      if (_ble.status.isAcOn) {
        await _ble.setAc(false);
        debugPrint('Automation: AC outlets off.');
      }

      // Let the relay fully isolate the load before the charger powers up.
      await Future.delayed(const Duration(seconds: 5));

      bool localSuccess = false;
      if (settings.useLocalTapo) {
        debugPrint('Automation: Attempting direct local Tapo ON command.');
        localSuccess = await _tapo.setOn(
          ip: settings.tapoIp,
          email: settings.tapoEmail,
          password: settings.tapoPassword,
          on: true,
        );
      }

      // Fallback if local Tapo is disabled or failed
      if (!localSuccess) {
        debugPrint('Automation: Direct local control failed or bypassed. Executing fallback ON webhook.');
        await _webhooks.fire(settings.tapoOnUrl);
        debugPrint('Automation: charger ON webhook fired.');
      } else {
        debugPrint('Automation: Direct local Tapo ON command succeeded.');
      }

      // Give the charger time to complete its power-delivery handshake.
      await Future.delayed(const Duration(seconds: 10));

      if (!_ble.status.isAcOn) {
        await _ble.setAc(true);
        debugPrint('Automation: AC outlets back on.');
      }
    } catch (e) {
      debugPrint('Automation: error in low battery sequence: $e');
    } finally {
      _sequenceRunning = false;
    }
  }

  Future<void> _runFullyChargedSequence(AutomationSettings settings) async {
    _chargingTriggered = false;
    await _storage.setChargingTriggered(false);

    if (!_ble.status.isAcOn) {
      await _ble.setAc(true);
    }

    bool localSuccess = false;
    if (settings.useLocalTapo) {
      debugPrint('Automation: Attempting direct local Tapo OFF command.');
      localSuccess = await _tapo.setOn(
        ip: settings.tapoIp,
        email: settings.tapoEmail,
        password: settings.tapoPassword,
        on: false,
      );
    }

    // Fallback if local Tapo is disabled or failed
    if (!localSuccess) {
      debugPrint('Automation: Direct local control failed or bypassed. Executing fallback OFF webhook.');
      await _webhooks.fire(settings.tapoOffUrl);
      debugPrint('Automation: fully charged, charger OFF webhook fired.');
    } else {
      debugPrint('Automation: Direct local Tapo OFF command succeeded.');
    }
  }
}