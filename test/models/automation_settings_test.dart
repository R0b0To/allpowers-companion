import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ap_companion/models/automation_settings.dart';

void main() {
  group('AutomationSettings', () {
    // ── Defaults ─────────────────────────────────────────────────────────────

    group('defaults', () {
      test('starts disabled with sensible thresholds', () {
        const s = AutomationSettings();
        expect(s.enabled, false);
        expect(s.lowThreshold, 10);
        expect(s.highThreshold, 95);
        expect(s.tapoOnUrl, '');
        expect(s.tapoOffUrl, '');
        expect(s.startTime, const TimeOfDay(hour: 21, minute: 0));
        expect(s.endTime, const TimeOfDay(hour: 8, minute: 0));
      });
    });

    // ── validated constructor ─────────────────────────────────────────────────

    group('validated constructor', () {
      test('clamps lowThreshold to 0–99', () {
        expect(
          AutomationSettings.validated(lowThreshold: -1, highThreshold: 95)
              .lowThreshold,
          0,
        );
        expect(
          AutomationSettings.validated(lowThreshold: 100, highThreshold: 95)
              .lowThreshold,
          99,
        );
      });

      test('clamps highThreshold to at least low+1', () {
        final s = AutomationSettings.validated(
          lowThreshold: 50,
          highThreshold: 40, // below low
        );
        expect(s.highThreshold, 51);
      });

      test('clamps highThreshold to 100 at most', () {
        final s = AutomationSettings.validated(
          lowThreshold: 10,
          highThreshold: 200,
        );
        expect(s.highThreshold, 100);
      });

      test('trims whitespace from webhook URLs', () {
        final s = AutomationSettings.validated(
          lowThreshold: 10,
          highThreshold: 95,
          tapoOnUrl: '  https://on.example.com  ',
          tapoOffUrl: '  https://off.example.com  ',
        );
        expect(s.tapoOnUrl, 'https://on.example.com');
        expect(s.tapoOffUrl, 'https://off.example.com');
      });

      test('allows low and high thresholds at valid boundary (low=0, high=1)',
          () {
        final s =
            AutomationSettings.validated(lowThreshold: 0, highThreshold: 1);
        expect(s.lowThreshold, 0);
        expect(s.highThreshold, 1);
      });

      test('allows low=99, high clamped to 100', () {
        final s =
            AutomationSettings.validated(lowThreshold: 99, highThreshold: 99);
        expect(s.lowThreshold, 99);
        expect(s.highThreshold, 100);
      });
    });

    // ── hasOnAction / hasOffAction ────────────────────────────────────────────

    group('hasOnAction / hasOffAction', () {
      test('both false when URLs are empty', () {
        const s = AutomationSettings();
        expect(s.hasOnAction, false);
        expect(s.hasOffAction, false);
      });

      test('hasOnAction true when tapoOnUrl is set', () {
        final s = AutomationSettings.validated(
          lowThreshold: 10,
          highThreshold: 95,
          tapoOnUrl: 'https://example.com/on',
        );
        expect(s.hasOnAction, true);
        expect(s.hasOffAction, false);
      });

      test('hasOffAction true when tapoOffUrl is set', () {
        final s = AutomationSettings.validated(
          lowThreshold: 10,
          highThreshold: 95,
          tapoOffUrl: 'https://example.com/off',
        );
        expect(s.hasOnAction, false);
        expect(s.hasOffAction, true);
      });
    });

    // ── isTimeInWindow ────────────────────────────────────────────────────────

    group('isTimeInWindow — same-day window (09:00–17:00)', () {
      late AutomationSettings s;

      setUp(() {
        s = AutomationSettings.validated(
          lowThreshold: 10,
          highThreshold: 95,
          startTime: const TimeOfDay(hour: 9, minute: 0),
          endTime: const TimeOfDay(hour: 17, minute: 0),
        );
      });

      test('returns true at start boundary', () {
        expect(s.isTimeInWindow(const TimeOfDay(hour: 9, minute: 0)), true);
      });

      test('returns true at end boundary', () {
        expect(s.isTimeInWindow(const TimeOfDay(hour: 17, minute: 0)), true);
      });

      test('returns true strictly inside window', () {
        expect(s.isTimeInWindow(const TimeOfDay(hour: 12, minute: 30)), true);
      });

      test('returns false one minute before start', () {
        expect(s.isTimeInWindow(const TimeOfDay(hour: 8, minute: 59)), false);
      });

      test('returns false one minute after end', () {
        expect(s.isTimeInWindow(const TimeOfDay(hour: 17, minute: 1)), false);
      });

      test('returns false at midnight (well outside window)', () {
        expect(s.isTimeInWindow(const TimeOfDay(hour: 0, minute: 0)), false);
      });
    });

    group('isTimeInWindow — overnight window (21:00–08:00)', () {
      late AutomationSettings s;

      setUp(() {
        s = AutomationSettings.validated(
          lowThreshold: 10,
          highThreshold: 95,
          startTime: const TimeOfDay(hour: 21, minute: 0),
          endTime: const TimeOfDay(hour: 8, minute: 0),
        );
      });

      test('returns true at start boundary (21:00)', () {
        expect(s.isTimeInWindow(const TimeOfDay(hour: 21, minute: 0)), true);
      });

      test('returns true late evening (23:59)', () {
        expect(s.isTimeInWindow(const TimeOfDay(hour: 23, minute: 59)), true);
      });

      test('returns true at midnight (00:00)', () {
        expect(s.isTimeInWindow(const TimeOfDay(hour: 0, minute: 0)), true);
      });

      test('returns true early morning inside window (06:00)', () {
        expect(s.isTimeInWindow(const TimeOfDay(hour: 6, minute: 0)), true);
      });

      test('returns true at end boundary (08:00)', () {
        expect(s.isTimeInWindow(const TimeOfDay(hour: 8, minute: 0)), true);
      });

      test('returns false one minute after end (08:01)', () {
        expect(s.isTimeInWindow(const TimeOfDay(hour: 8, minute: 1)), false);
      });

      test('returns false midday (12:00)', () {
        expect(s.isTimeInWindow(const TimeOfDay(hour: 12, minute: 0)), false);
      });

      test('returns false one minute before start (20:59)', () {
        expect(s.isTimeInWindow(const TimeOfDay(hour: 20, minute: 59)), false);
      });
    });

    // ── copyWith ──────────────────────────────────────────────────────────────

    group('copyWith', () {
      const base = AutomationSettings(
        enabled: true,
        lowThreshold: 15,
        highThreshold: 80,
      );

      test('changes only enabled', () {
        final copy = base.copyWith(enabled: false);
        expect(copy.enabled, false);
        expect(copy.lowThreshold, 15);
        expect(copy.highThreshold, 80);
      });

      test('changes only lowThreshold', () {
        final copy = base.copyWith(lowThreshold: 20);
        expect(copy.lowThreshold, 20);
        expect(copy.enabled, true);
      });

      test('re-validates threshold relationship on copyWith', () {
        // Setting lowThreshold above highThreshold must clamp highThreshold.
        final copy = base.copyWith(lowThreshold: 85); // above current high=80
        expect(copy.lowThreshold, 85);
        expect(copy.highThreshold, greaterThan(85));
      });

      test('returns an equal value when no fields change', () {
        final copy = base.copyWith();
        expect(copy, equals(base));
      });
    });

    // ── Equality & hashCode ───────────────────────────────────────────────────

    group('equality', () {
      test('equal instances compare equal', () {
        const a = AutomationSettings(lowThreshold: 10, highThreshold: 95);
        const b = AutomationSettings(lowThreshold: 10, highThreshold: 95);
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('different enabled flag breaks equality', () {
        const a = AutomationSettings(enabled: true);
        const b = AutomationSettings(enabled: false);
        expect(a, isNot(equals(b)));
      });

      test('different lowThreshold breaks equality', () {
        const a = AutomationSettings(lowThreshold: 10, highThreshold: 95);
        const b = AutomationSettings(lowThreshold: 20, highThreshold: 95);
        expect(a, isNot(equals(b)));
      });

      test('different URLs break equality', () {
        final a = AutomationSettings.validated(
            lowThreshold: 10,
            highThreshold: 95,
            tapoOnUrl: 'https://a.example.com');
        final b = AutomationSettings.validated(
            lowThreshold: 10,
            highThreshold: 95,
            tapoOnUrl: 'https://b.example.com');
        expect(a, isNot(equals(b)));
      });

      test('identical instance equals itself', () {
        const s = AutomationSettings();
        expect(s, equals(s));
      });
    });

    // ── JSON round-trip ───────────────────────────────────────────────────────

    group('JSON round-trip', () {
      test('survives a full serialise → deserialise cycle', () {
        final original = AutomationSettings.validated(
          enabled: true,
          lowThreshold: 15,
          highThreshold: 85,
          tapoOnUrl: 'https://on.example.com',
          tapoOffUrl: 'https://off.example.com',
          startTime: const TimeOfDay(hour: 22, minute: 30),
          endTime: const TimeOfDay(hour: 7, minute: 15),
        );
        final json = original.toJson();
        final restored = AutomationSettingsJson.fromJson(json);
        expect(restored, equals(original));
      });

      test('fromJson uses defaults for missing keys (forward-compat)', () {
        // Simulate a stored payload that predates the enabled flag.
        final json = <String, dynamic>{
          'lowThreshold': 20,
          'highThreshold': 90,
          // 'enabled' absent — should default to false
        };
        final s = AutomationSettingsJson.fromJson(json);
        expect(s.enabled, false);
        expect(s.lowThreshold, 20);
        expect(s.highThreshold, 90);
      });

      test('fromJson clamps out-of-range values from corrupt storage', () {
        final json = <String, dynamic>{
          'lowThreshold': -99,
          'highThreshold': 9999,
          'startTime': '21:00',
          'endTime': '08:00',
        };
        final s = AutomationSettingsJson.fromJson(json);
        expect(s.lowThreshold, 0);
        expect(s.highThreshold, 100);
      });
    });
  });
}