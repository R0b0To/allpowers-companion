import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/automation_settings.dart';
import 'ble_service.dart';
import 'webhook_service.dart';

/// Runs the "smart charging" handshake:
///  - When the battery drops to the configured low limit, briefly cut the
///    AC outlets, fire the "charger on" webhook, wait for the plug to
///    physically power up, then restore AC.
///  - When the battery reaches the high limit, fire the "charger off"
///    webhook and leave AC on.
///
/// A lock ([_sequenceRunning]) prevents two sequences from overlapping if
/// status packets arrive faster than a sequence completes.
class AutomationEngine {
  AutomationEngine(this._ble, this._webhooks);

  final BleService _ble;
  final WebhookService _webhooks;

  bool _chargingTriggered = false;
  bool _sequenceRunning = false;

  Future<void> evaluate(AutomationSettings settings) async {
    if (!settings.enabled) return;
    if (!settings.isTimeInWindow(TimeOfDay.now())) return;

    final batteryLevel = _ble.status.batteryLevel;

    if (batteryLevel <= settings.lowThreshold &&
        batteryLevel > 0 &&
        !_chargingTriggered &&
        !_sequenceRunning) {
      await _runLowBatterySequence(settings);
    }

    if (batteryLevel >= settings.highThreshold && _chargingTriggered) {
      await _runFullyChargedSequence(settings);
    }
  }

  Future<void> _runLowBatterySequence(AutomationSettings settings) async {
    _sequenceRunning = true;
    _chargingTriggered = true;
    debugPrint('Automation: low battery threshold hit, starting sequence.');

    try {
      if (_ble.status.isAcOn) {
        await _ble.setAc(false);
        debugPrint('Automation: AC outlets off.');
      }

      // Let the relay fully isolate the load before the charger powers up.
      await Future.delayed(const Duration(seconds: 5));

      await _webhooks.fire(settings.tapoOnUrl);
      debugPrint('Automation: charger ON webhook fired.');

      // Give the charger time to complete its power-delivery handshake.
      await Future.delayed(const Duration(seconds: 10));

      if (!_ble.status.isAcOn) {
        await _ble.setAc(true);
        debugPrint('Automation: AC outlets back on.');
      }
    } finally {
      _sequenceRunning = false;
    }
  }

  Future<void> _runFullyChargedSequence(AutomationSettings settings) async {
    _chargingTriggered = false;

    if (!_ble.status.isAcOn) {
      await _ble.setAc(true);
    }
    await _webhooks.fire(settings.tapoOffUrl);
    debugPrint('Automation: fully charged, charger OFF webhook fired.');
  }
}