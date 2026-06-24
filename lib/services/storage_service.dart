import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/automation_history_entry.dart';
import '../models/automation_settings.dart';
import '../models/energy_log_entry.dart';
import '../models/mqtt_settings.dart';
import '../utils/logger.dart';

/// Typed, error-safe wrapper around [SharedPreferences].
///
/// - All keys are private constants — no raw strings leak into business logic.
/// - Every read/write is wrapped in try/catch; failures are logged and
///   surfaced as null / default values rather than crashing the app.
/// - The Tapo password is stored in plain text inside SharedPreferences
///   (the same sandbox storage as the rest of the settings). For production
///   this should be replaced with flutter_secure_storage.
/// - The energy log uses a compact line format (not JSON) since it can grow
///   to thousands of entries — see [EnergyLogEntry.toCompact]. If retention
///   needs to grow well beyond [_maxEnergyLogEntries], consider moving it to
///   sqflite instead of SharedPreferences.
final class StorageService {
  // ── Keys — automation / BLE ──────────────────────────────────────────────
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
  static const _keyAutomationHistory = 'automation_history';
  static const _keyEnergyLog = 'energy_log';

  // ── Keys — MQTT ──────────────────────────────────────────────────────────
  static const _keyMqttMode = 'mqtt_mode';
  static const _keyMqttBrokerHost = 'mqtt_broker_host';
  static const _keyMqttPort = 'mqtt_port';
  static const _keyMqttUsername = 'mqtt_username';
  static const _keyMqttPassword = 'mqtt_password';
  static const _keyMqttTopicPrefix = 'mqtt_topic_prefix';
  static const _keyMqttUseTls = 'mqtt_use_tls';
  static const _keyMqttClientId = 'mqtt_client_id';

  /// Hard cap on stored history entries — keeps SharedPreferences (which is
  /// not meant for large blobs) bounded regardless of how long the app runs.
  static const _maxHistoryEntries = 100;

  /// Hard cap on stored energy samples. At the default 5-minute sampling
  /// interval (288 samples/day) this holds roughly 30 days of history.
  static const _maxEnergyLogEntries = 8640;

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

  // ── MQTT settings ─────────────────────────────────────────────────────────

  Future<MqttSettings> loadMqttSettings() async {
    try {
      final prefs = await _getPrefs();
      final modeStr = prefs.getString(_keyMqttMode) ?? AppMode.standalone.name;
      final mode = AppMode.values.firstWhere(
        (m) => m.name == modeStr,
        orElse: () => AppMode.standalone,
      );
      return MqttSettings(
        mode: mode,
        brokerHost: prefs.getString(_keyMqttBrokerHost) ?? '',
        port: prefs.getInt(_keyMqttPort) ?? 1883,
        username: prefs.getString(_keyMqttUsername) ?? '',
        password: prefs.getString(_keyMqttPassword) ?? '',
        topicPrefix: prefs.getString(_keyMqttTopicPrefix) ?? 'ap/station',
        useTls: prefs.getBool(_keyMqttUseTls) ?? false,
        clientId: prefs.getString(_keyMqttClientId) ?? '',
      );
    } catch (e) {
      Log.e('StorageService', 'loadMqttSettings failed, returning defaults', e);
      return const MqttSettings();
    }
  }

  Future<void> saveMqttSettings(MqttSettings settings) async {
    try {
      final prefs = await _getPrefs();
      await Future.wait([
        prefs.setString(_keyMqttMode, settings.mode.name),
        prefs.setString(_keyMqttBrokerHost, settings.brokerHost),
        prefs.setInt(_keyMqttPort, settings.port),
        prefs.setString(_keyMqttUsername, settings.username),
        prefs.setString(_keyMqttPassword, settings.password),
        prefs.setString(_keyMqttTopicPrefix, settings.topicPrefix),
        prefs.setBool(_keyMqttUseTls, settings.useTls),
        prefs.setString(_keyMqttClientId, settings.clientId),
      ]);
    } catch (e) {
      Log.e('StorageService', 'saveMqttSettings failed', e);
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

  // ── Automation history ────────────────────────────────────────────────────

  /// Loads stored history entries, newest first. Individually malformed
  /// entries are skipped rather than failing the whole load.
  Future<List<AutomationHistoryEntry>> loadAutomationHistory() async {
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getStringList(_keyAutomationHistory) ?? [];
      final entries = <AutomationHistoryEntry>[];
      for (final s in raw) {
        try {
          final entry = AutomationHistoryEntry.tryFromJson(
            jsonDecode(s) as Map<String, dynamic>,
          );
          if (entry != null) entries.add(entry);
        } catch (_) {
          // Skip this single entry; one bad row shouldn't drop the rest.
        }
      }
      return entries;
    } catch (e) {
      Log.e('StorageService', 'loadAutomationHistory failed', e);
      return [];
    }
  }

  /// Persists [entries] (expected newest-first), capping at
  /// [_maxHistoryEntries].
  Future<void> saveAutomationHistory(
    List<AutomationHistoryEntry> entries,
  ) async {
    try {
      final prefs = await _getPrefs();
      final capped = entries.length > _maxHistoryEntries
          ? entries.sublist(0, _maxHistoryEntries)
          : entries;
      await prefs.setStringList(
        _keyAutomationHistory,
        capped.map((e) => jsonEncode(e.toJson())).toList(),
      );
    } catch (e) {
      Log.e('StorageService', 'saveAutomationHistory failed', e);
    }
  }

  // ── Energy log ─────────────────────────────────────────────────────────────

  /// Loads stored energy samples, oldest first. Individually malformed lines
  /// are skipped rather than failing the whole load.
  Future<List<EnergyLogEntry>> loadEnergyLog() async {
    try {
      final prefs = await _getPrefs();
      final raw = prefs.getStringList(_keyEnergyLog) ?? [];
      final entries = <EnergyLogEntry>[];
      for (final line in raw) {
        final entry = EnergyLogEntry.tryFromCompact(line);
        if (entry != null) entries.add(entry);
      }
      return entries;
    } catch (e) {
      Log.e('StorageService', 'loadEnergyLog failed', e);
      return [];
    }
  }

  /// Persists [entries] (expected oldest-first), capping at
  /// [_maxEnergyLogEntries] by dropping the oldest samples first.
  Future<void> saveEnergyLog(List<EnergyLogEntry> entries) async {
    try {
      final prefs = await _getPrefs();
      final capped = entries.length > _maxEnergyLogEntries
          ? entries.sublist(entries.length - _maxEnergyLogEntries)
          : entries;
      await prefs.setStringList(
        _keyEnergyLog,
        capped.map((e) => e.toCompact()).toList(),
      );
    } catch (e) {
      Log.e('StorageService', 'saveEnergyLog failed', e);
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