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
/// A lock ([_sequenceRunning]) prevents two sequences from overlapping if
/// status packets arrive faster than a sequence completes.
class AutomationEngine {
  AutomationEngine(this._ble, this._webhooks, this._tapo, this._storage);

  final BleService _ble;
  final WebhookService _webhooks;
  final TapoService _tapo; // Added TapoService field
  final StorageService _storage;

  bool _chargingTriggered = false;
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

    // ── Low threshold: start charging ──────────────────────────────────────
    // Guard: only trigger if we haven't already done so since the last full
    // charge. This survives disconnects/reconnects because the flag is
    // persisted to disk in _runLowBatterySequence.
    if (batteryLevel <= settings.lowThreshold &&
        !_chargingTriggered &&
        !_sequenceRunning) {
      await _runLowBatterySequence(settings);
    }

    // ── High threshold: stop charging ──────────────────────────────────────
    if (batteryLevel >= settings.highThreshold && _chargingTriggered) {
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