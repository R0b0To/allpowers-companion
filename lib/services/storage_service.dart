import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/automation_settings.dart';
import '../utils/logger.dart';

/// Typed, error-safe wrapper around [SharedPreferences].
///
/// - All keys are private constants — no raw strings leak into business logic.
/// - Every read/write is wrapped in try/catch; failures are logged and
///   surfaced as null / default values rather than crashing the app.
/// - The Tapo password is stored in plain text inside SharedPreferences
///   (the same sandbox storage as the rest of the settings). For production
///   this should be replaced with flutter_secure_storage.
final class StorageService {
  // ── Keys ──────────────────────────────────────────────────────────────────
  static const _keyDeviceId = 'saved_device_id';
  static const _keyAutoEnabled = 'auto_enabled';
  static const _keyTapoOnUrl = 'tapo_on_url';
  static const _keyTapoOffUrl = 'tapo_off_url';
  static const _keyLowThreshold = 'low_threshold';
  static const _keyHighThreshold = 'high_threshold';
  static const _keyStartTime = 'start_time';
  static const _keyEndTime = 'end_time';
  static const _keyUseLocalTapo = 'use_local_tapo';
  static const _keyTapoIp = 'tapo_ip';
  static const _keyTapoEmail = 'tapo_email';
  static const _keyTapoPassword = 'tapo_password';
  static const _keyChargingTriggered = 'charging_triggered';

  // ── Cached instance ───────────────────────────────────────────────────────
  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── Device pairing ────────────────────────────────────────────────────────

  Future<String?> getSavedDeviceId() async {
    try {
      final prefs = await _getPrefs();
      return prefs.getString(_keyDeviceId);
    } catch (e) {
      Log.e('StorageService', 'getSavedDeviceId failed', e);
      return null;
    }
  }

  Future<void> setSavedDeviceId(String id) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setString(_keyDeviceId, id);
    } catch (e) {
      Log.e('StorageService', 'setSavedDeviceId failed', e);
    }
  }

  Future<void> clearSavedDeviceId() async {
    try {
      final prefs = await _getPrefs();
      await prefs.remove(_keyDeviceId);
    } catch (e) {
      Log.e('StorageService', 'clearSavedDeviceId failed', e);
    }
  }

  // ── Automation settings ───────────────────────────────────────────────────

  Future<AutomationSettings> loadAutomationSettings() async {
    try {
      final prefs = await _getPrefs();
      return AutomationSettings.validated(
        enabled: prefs.getBool(_keyAutoEnabled) ?? false,
        tapoOnUrl: prefs.getString(_keyTapoOnUrl) ?? '',
        tapoOffUrl: prefs.getString(_keyTapoOffUrl) ?? '',
        lowThreshold: prefs.getInt(_keyLowThreshold) ?? 10,
        highThreshold: prefs.getInt(_keyHighThreshold) ?? 95,
        startTime: _parseTime(prefs.getString(_keyStartTime) ?? '21:00'),
        endTime: _parseTime(prefs.getString(_keyEndTime) ?? '08:00'),
        useLocalTapo: prefs.getBool(_keyUseLocalTapo) ?? false,
        tapoIp: prefs.getString(_keyTapoIp) ?? '',
        tapoEmail: prefs.getString(_keyTapoEmail) ?? '',
        tapoPassword: prefs.getString(_keyTapoPassword) ?? '',
      );
    } catch (e) {
      Log.e('StorageService', 'loadAutomationSettings failed, returning defaults', e);
      return const AutomationSettings();
    }
  }

  Future<void> saveAutomationSettings(AutomationSettings settings) async {
    try {
      final prefs = await _getPrefs();
      await Future.wait([
        prefs.setBool(_keyAutoEnabled, settings.enabled),
        prefs.setString(_keyTapoOnUrl, settings.tapoOnUrl),
        prefs.setString(_keyTapoOffUrl, settings.tapoOffUrl),
        prefs.setInt(_keyLowThreshold, settings.lowThreshold),
        prefs.setInt(_keyHighThreshold, settings.highThreshold),
        prefs.setString(_keyStartTime, _formatTime(settings.startTime)),
        prefs.setString(_keyEndTime, _formatTime(settings.endTime)),
        prefs.setBool(_keyUseLocalTapo, settings.useLocalTapo),
        prefs.setString(_keyTapoIp, settings.tapoIp),
        prefs.setString(_keyTapoEmail, settings.tapoEmail),
        prefs.setString(_keyTapoPassword, settings.tapoPassword),
      ]);
    } catch (e) {
      Log.e('StorageService', 'saveAutomationSettings failed', e);
    }
  }

  // ── Charging-triggered flag ───────────────────────────────────────────────

  /// Persisted across app restarts so a disconnect during a charge cycle
  /// does not re-trigger the low-battery sequence on reconnect.
  Future<bool> getChargingTriggered() async {
    try {
      final prefs = await _getPrefs();
      return prefs.getBool(_keyChargingTriggered) ?? false;
    } catch (e) {
      Log.e('StorageService', 'getChargingTriggered failed', e);
      return false;
    }
  }

  Future<void> setChargingTriggered(bool value) async {
    try {
      final prefs = await _getPrefs();
      await prefs.setBool(_keyChargingTriggered, value);
    } catch (e) {
      Log.e('StorageService', 'setChargingTriggered failed', e);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  TimeOfDay _parseTime(String value) {
    try {
      final parts = value.split(':');
      if (parts.length != 2) throw const FormatException('Expected HH:MM');
      return TimeOfDay(
        hour: int.parse(parts[0]).clamp(0, 23),
        minute: int.parse(parts[1]).clamp(0, 59),
      );
    } catch (e) {
      Log.w('StorageService', 'Failed to parse time "$value", using 00:00');
      return const TimeOfDay(hour: 0, minute: 0);
    }
  }

  String _formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}