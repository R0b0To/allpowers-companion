import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/automation_settings.dart';

/// Thin, typed wrapper around [SharedPreferences] so the rest of the app
/// never touches raw preference keys directly.
class StorageService {
  static const _keySavedDeviceId = 'saved_device_id';
  static const _keyAutoEnabled = 'auto_enabled';
  static const _keyTapoOnUrl = 'tapo_on_url';
  static const _keyTapoOffUrl = 'tapo_off_url';
  static const _keyLowThreshold = 'low_threshold';
  static const _keyHighThreshold = 'high_threshold';
  static const _keyStartTime = 'start_time';
  static const _keyEndTime = 'end_time';

  // New local Tapo preference keys
  static const _keyUseLocalTapo = 'use_local_tapo';
  static const _keyTapoIp = 'tapo_ip';
  static const _keyTapoEmail = 'tapo_email';
  static const _keyTapoPassword = 'tapo_password';

  /// Persisted so that a disconnect/reconnect mid-charge cycle does not
  /// re-trigger the low-battery sequence.
  static const _keyChargingTriggered = 'charging_triggered';

  // ── Device pairing ────────────────────────────────────────────────────────

  Future<String?> getSavedDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySavedDeviceId);
  }

  Future<void> setSavedDeviceId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySavedDeviceId, id);
  }

  Future<void> clearSavedDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySavedDeviceId);
  }

  // ── Automation settings ───────────────────────────────────────────────────

  Future<AutomationSettings> loadAutomationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return AutomationSettings(
      enabled: prefs.getBool(_keyAutoEnabled) ?? false,
      tapoOnUrl: prefs.getString(_keyTapoOnUrl) ?? '',
      tapoOffUrl: prefs.getString(_keyTapoOffUrl) ?? '',
      lowThreshold:
          int.tryParse(prefs.getString(_keyLowThreshold) ?? '') ?? 10,
      highThreshold:
          int.tryParse(prefs.getString(_keyHighThreshold) ?? '') ?? 95,
      startTime: _parseTime(prefs.getString(_keyStartTime) ?? '21:00'),
      endTime: _parseTime(prefs.getString(_keyEndTime) ?? '08:00'),
      
      // Load direct Tapo settings
      useLocalTapo: prefs.getBool(_keyUseLocalTapo) ?? false,
      tapoIp: prefs.getString(_keyTapoIp) ?? '',
      tapoEmail: prefs.getString(_keyTapoEmail) ?? '',
      tapoPassword: prefs.getString(_keyTapoPassword) ?? '',
    );
  }

  Future<void> saveAutomationSettings(AutomationSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoEnabled, settings.enabled);
    await prefs.setString(_keyTapoOnUrl, settings.tapoOnUrl);
    await prefs.setString(_keyTapoOffUrl, settings.tapoOffUrl);
    await prefs.setString(_keyLowThreshold, settings.lowThreshold.toString());
    await prefs.setString(
        _keyHighThreshold, settings.highThreshold.toString());
    await prefs.setString(_keyStartTime, _formatTime(settings.startTime));
    await prefs.setString(_keyEndTime, _formatTime(settings.endTime));

    // Save direct Tapo settings
    await prefs.setBool(_keyUseLocalTapo, settings.useLocalTapo);
    await prefs.setString(_keyTapoIp, settings.tapoIp);
    await prefs.setString(_keyTapoEmail, settings.tapoEmail);
    await prefs.setString(_keyTapoPassword, settings.tapoPassword);
  }

  // ── Charging-triggered flag ───────────────────────────────────────────────

  Future<bool> getChargingTriggered() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyChargingTriggered) ?? false;
  }

  Future<void> setChargingTriggered(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyChargingTriggered, value);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  TimeOfDay _parseTime(String value) {
    try {
      final parts = value.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return const TimeOfDay(hour: 0, minute: 0);
    }
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
  }
}