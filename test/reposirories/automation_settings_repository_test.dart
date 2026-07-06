import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ap_companion/models/automation_settings.dart';
import 'package:ap_companion/repositories/automation_settings_repository.dart';
import 'package:ap_companion/repositories/shared_preferences_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPrefsAutomationSettingsRepository', () {
    test('returns defaults on a fresh install with nothing stored', () async {
      SharedPreferences.setMockInitialValues({});
      final repo =
          SharedPrefsAutomationSettingsRepository(SharedPreferencesSource());

      final settings = await repo.load();

      expect(settings.enabled, isFalse);
      expect(settings.lowThreshold, 10);
      expect(settings.highThreshold, 95);
    });

    test('save then load round-trips via the single JSON key', () async {
      SharedPreferences.setMockInitialValues({});
      final repo =
          SharedPrefsAutomationSettingsRepository(SharedPreferencesSource());

      await repo.save(AutomationSettings.validated(
        enabled: true,
        lowThreshold: 20,
        highThreshold: 80,
        startTime: const TimeOfDay(hour: 22, minute: 0),
        endTime: const TimeOfDay(hour: 6, minute: 0),
      ));

      final loaded = await repo.load();

      expect(loaded.enabled, isTrue);
      expect(loaded.lowThreshold, 20);
      expect(loaded.highThreshold, 80);
      expect(loaded.startTime, const TimeOfDay(hour: 22, minute: 0));
      expect(loaded.endTime, const TimeOfDay(hour: 6, minute: 0));
    });

    test('migrates legacy per-field keys to the single JSON key on first load',
        () async {
      SharedPreferences.setMockInitialValues({
        'auto_enabled': true,
        'low_threshold': 5,
        'high_threshold': 90,
        'start_time': '20:00',
        'end_time': '07:30',
        // Legacy webhook fields from the retired global on/off automation —
        // must be discarded, not migrated onto anything.
        'tapo_on_url': 'https://example.com/on',
        'tapo_off_url': 'https://example.com/off',
      });
      final source = SharedPreferencesSource();
      final repo = SharedPrefsAutomationSettingsRepository(source);

      final migrated = await repo.load();

      expect(migrated.enabled, isTrue);
      expect(migrated.lowThreshold, 5);
      expect(migrated.highThreshold, 90);
      expect(migrated.startTime, const TimeOfDay(hour: 20, minute: 0));
      expect(migrated.endTime, const TimeOfDay(hour: 7, minute: 30));

      // Legacy keys should be gone, so a second load doesn't re-migrate and
      // instead reads straight from the new JSON key.
      final prefs = await source.prefs;
      expect(prefs.containsKey('auto_enabled'), isFalse);
      expect(prefs.containsKey('tapo_on_url'), isFalse);
      expect(prefs.containsKey('tapo_off_url'), isFalse);

      final reloaded = await repo.load();
      expect(reloaded.lowThreshold, 5);
    });

    test('a corrupt legacy time string falls back to 00:00 rather than throwing',
        () async {
      SharedPreferences.setMockInitialValues({
        'auto_enabled': false,
        'low_threshold': 10,
        'high_threshold': 95,
        'start_time': 'not-a-time',
        'end_time': '08:00',
      });
      final repo =
          SharedPrefsAutomationSettingsRepository(SharedPreferencesSource());

      final settings = await repo.load();

      expect(settings.startTime, const TimeOfDay(hour: 0, minute: 0));
    });
  });
}