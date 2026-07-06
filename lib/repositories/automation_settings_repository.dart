import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/automation_settings.dart';
import '../utils/logger.dart';
import 'shared_preferences_source.dart';

/// Persists smart-charging rules: battery thresholds and active time window.
///
/// ## Storage format
/// All fields are stored as a single JSON blob under [_keySettingsJson].
/// Previously each field was written as its own SharedPreferences key via
/// `Future.wait`, which meant a process kill between two of those writes
/// could leave the stored settings an inconsistent mix of old and new
/// values (e.g. a new [AutomationSettings.lowThreshold] paired with the old
/// [AutomationSettings.highThreshold]). A single key is written as one
/// atomic call, so partial writes are no longer possible.
///
/// ## Migration
/// If [_keySettingsJson] is absent (pre-upgrade install), [load] falls back
/// to the legacy per-field keys, builds an [AutomationSettings] from them,
/// persists it under the new key, and removes the legacy keys. The legacy
/// `tapo_on_url` / `tapo_off_url` keys — from the retired global on/off
/// webhook fields, superseded by per-device Tapo control and per-flow
/// webhook actions — are removed during migration but otherwise ignored;
/// they no longer map to anything on [AutomationSettings].
///
/// ## Testing
/// ```dart
/// SharedPreferences.setMockInitialValues({});
/// final repo = SharedPrefsAutomationSettingsRepository(SharedPreferencesSource());
/// final loaded = await repo.load();
/// expect(loaded.lowThreshold, 10); // default
/// ```
abstract class AutomationSettingsRepository {
  Future<AutomationSettings> load();
  Future<void> save(AutomationSettings settings);
}

final class SharedPrefsAutomationSettingsRepository
    implements AutomationSettingsRepository {
  SharedPrefsAutomationSettingsRepository(this._source);

  final SharedPreferencesSource _source;

  // ── Current storage key ───────────────────────────────────────────────────
  static const _keySettingsJson = 'automation_settings_json';

  // ── Legacy per-field keys (pre-migration) ─────────────────────────────────
  static const _legacyKeyEnabled = 'auto_enabled';
  static const _legacyKeyTapoOnUrl = 'tapo_on_url'; // retired — discarded
  static const _legacyKeyTapoOffUrl = 'tapo_off_url'; // retired — discarded
  static const _legacyKeyLowThreshold = 'low_threshold';
  static const _legacyKeyHighThreshold = 'high_threshold';
  static const _legacyKeyStartTime = 'start_time';
  static const _legacyKeyEndTime = 'end_time';

  @override
  Future<AutomationSettings> load() async {
    try {
      final prefs = await _source.prefs;
      final raw = prefs.getString(_keySettingsJson);
      if (raw != null) {
        return AutomationSettingsJson.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
      return _migrateFromLegacyKeys(prefs);
    } catch (e) {
      Log.e('AutomationSettingsRepository', 'load failed — returning defaults', e);
      return const AutomationSettings();
    }
  }

  Future<AutomationSettings> _migrateFromLegacyKeys(
      SharedPreferences prefs) async {
    final hasLegacyData = prefs.containsKey(_legacyKeyEnabled) ||
        prefs.containsKey(_legacyKeyLowThreshold) ||
        prefs.containsKey(_legacyKeyHighThreshold) ||
        prefs.containsKey(_legacyKeyStartTime) ||
        prefs.containsKey(_legacyKeyEndTime);

    final settings = AutomationSettings.validated(
      enabled: prefs.getBool(_legacyKeyEnabled) ?? false,
      lowThreshold: prefs.getInt(_legacyKeyLowThreshold) ?? 10,
      highThreshold: prefs.getInt(_legacyKeyHighThreshold) ?? 95,
      startTime: _parseTime(prefs.getString(_legacyKeyStartTime) ?? '21:00'),
      endTime: _parseTime(prefs.getString(_legacyKeyEndTime) ?? '08:00'),
    );

    if (hasLegacyData) {
      Log.i('AutomationSettingsRepository',
          'Migrating legacy per-field settings to single JSON key');
      await save(settings);
      await Future.wait([
        prefs.remove(_legacyKeyEnabled),
        prefs.remove(_legacyKeyTapoOnUrl),
        prefs.remove(_legacyKeyTapoOffUrl),
        prefs.remove(_legacyKeyLowThreshold),
        prefs.remove(_legacyKeyHighThreshold),
        prefs.remove(_legacyKeyStartTime),
        prefs.remove(_legacyKeyEndTime),
      ]);
    }

    return settings;
  }

  @override
  Future<void> save(AutomationSettings s) async {
    try {
      final prefs = await _source.prefs;
      await prefs.setString(_keySettingsJson, jsonEncode(s.toJson()));
    } catch (e) {
      Log.e('AutomationSettingsRepository', 'save failed', e);
    }
  }

  // ── TimeOfDay helpers ─────────────────────────────────────────────────────

  static TimeOfDay _parseTime(String value) {
    try {
      final parts = value.split(':');
      if (parts.length != 2) throw const FormatException('Expected HH:MM');
      return TimeOfDay(
        hour: int.parse(parts[0]).clamp(0, 23),
        minute: int.parse(parts[1]).clamp(0, 59),
      );
    } catch (e) {
      Log.w('AutomationSettingsRepository',
          'Failed to parse time "$value" — using 00:00');
      return const TimeOfDay(hour: 0, minute: 0);
    }
  }
}