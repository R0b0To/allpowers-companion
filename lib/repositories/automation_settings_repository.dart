import 'package:flutter/material.dart';

import '../models/automation_settings.dart';
import '../utils/logger.dart';
import 'shared_preferences_source.dart';

/// Persists smart-charging rules: battery thresholds, active time window,
/// and optional webhook URLs for ON/OFF events.
///
/// [TimeOfDay] values are stored as `HH:MM` strings; parsing is handled
/// privately so callers work entirely with typed [AutomationSettings].
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

  // ── Keys ──────────────────────────────────────────────────────────────────
  static const _keyEnabled       = 'auto_enabled';
  static const _keyTapoOnUrl     = 'tapo_on_url';
  static const _keyTapoOffUrl    = 'tapo_off_url';
  static const _keyLowThreshold  = 'low_threshold';
  static const _keyHighThreshold = 'high_threshold';
  static const _keyStartTime     = 'start_time';
  static const _keyEndTime       = 'end_time';

  @override
  Future<AutomationSettings> load() async {
    try {
      final prefs = await _source.prefs;
      return AutomationSettings.validated(
        enabled:        prefs.getBool(_keyEnabled)            ?? false,
        tapoOnUrl:      prefs.getString(_keyTapoOnUrl)        ?? '',
        tapoOffUrl:     prefs.getString(_keyTapoOffUrl)       ?? '',
        lowThreshold:   prefs.getInt(_keyLowThreshold)        ?? 10,
        highThreshold:  prefs.getInt(_keyHighThreshold)       ?? 95,
        startTime:      _parseTime(prefs.getString(_keyStartTime)  ?? '21:00'),
        endTime:        _parseTime(prefs.getString(_keyEndTime)    ?? '08:00'),
      );
    } catch (e) {
      Log.e('AutomationSettingsRepository', 'load failed — returning defaults', e);
      return const AutomationSettings();
    }
  }

  @override
  Future<void> save(AutomationSettings s) async {
    try {
      final prefs = await _source.prefs;
      await Future.wait([
        prefs.setBool(_keyEnabled,        s.enabled),
        prefs.setString(_keyTapoOnUrl,    s.tapoOnUrl),
        prefs.setString(_keyTapoOffUrl,   s.tapoOffUrl),
        prefs.setInt(_keyLowThreshold,    s.lowThreshold),
        prefs.setInt(_keyHighThreshold,   s.highThreshold),
        prefs.setString(_keyStartTime,    _formatTime(s.startTime)),
        prefs.setString(_keyEndTime,      _formatTime(s.endTime)),
      ]);
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
        hour:   int.parse(parts[0]).clamp(0, 23),
        minute: int.parse(parts[1]).clamp(0, 59),
      );
    } catch (e) {
      Log.w('AutomationSettingsRepository', 'Failed to parse time "$value" — using 00:00');
      return const TimeOfDay(hour: 0, minute: 0);
    }
  }

  static String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
