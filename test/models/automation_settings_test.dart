import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ap_companion/models/automation_settings.dart';

void main() {
  group('AutomationSettings.validated', () {
    test('clamps low threshold below the configured high threshold', () {
      final settings =
          AutomationSettings.validated(lowThreshold: 90, highThreshold: 95);

      expect(settings.lowThreshold, lessThan(settings.highThreshold));
    });

    test('clamps thresholds to the legal 0-100 range', () {
      final settings =
          AutomationSettings.validated(lowThreshold: -10, highThreshold: 500);

      expect(settings.lowThreshold, 0);
      expect(settings.highThreshold, 100);
    });

    test('forces highThreshold to be strictly greater than the (clamped) lowThreshold',
        () {
      final settings =
          AutomationSettings.validated(lowThreshold: 50, highThreshold: 50);

      expect(settings.highThreshold, greaterThan(settings.lowThreshold));
    });
  });

  group('AutomationSettings.isTimeInWindow', () {
    test('normal window', () {
      final settings = AutomationSettings.validated(
        lowThreshold: 10,
        highThreshold: 95,
        startTime: const TimeOfDay(hour: 8, minute: 0),
        endTime: const TimeOfDay(hour: 20, minute: 0),
      );

      expect(settings.isTimeInWindow(const TimeOfDay(hour: 12, minute: 0)), isTrue);
      expect(settings.isTimeInWindow(const TimeOfDay(hour: 21, minute: 0)), isFalse);
    });

    test('overnight window', () {
      final settings = AutomationSettings.validated(
        lowThreshold: 10,
        highThreshold: 95,
        startTime: const TimeOfDay(hour: 21, minute: 0),
        endTime: const TimeOfDay(hour: 8, minute: 0),
      );

      expect(settings.isTimeInWindow(const TimeOfDay(hour: 23, minute: 0)), isTrue);
      expect(settings.isTimeInWindow(const TimeOfDay(hour: 3, minute: 0)), isTrue);
      expect(settings.isTimeInWindow(const TimeOfDay(hour: 15, minute: 0)), isFalse);
    });
  });

  group('AutomationSettings JSON', () {
    test('round-trips through JSON', () {
      final settings = AutomationSettings.validated(
        enabled: true,
        lowThreshold: 15,
        highThreshold: 90,
        startTime: const TimeOfDay(hour: 22, minute: 30),
        endTime: const TimeOfDay(hour: 6, minute: 45),
      );

      final decoded = AutomationSettingsJson.fromJson(settings.toJson());

      expect(decoded, settings);
    });

    test('fromJson falls back to defaults for missing keys', () {
      final decoded = AutomationSettingsJson.fromJson(<String, dynamic>{});

      expect(decoded.enabled, isFalse);
      expect(decoded.lowThreshold, 10);
      expect(decoded.highThreshold, 95);
      expect(decoded.startTime, const TimeOfDay(hour: 21, minute: 0));
      expect(decoded.endTime, const TimeOfDay(hour: 8, minute: 0));
    });
  });

  group('AutomationSettings equality', () {
    test('two instances with the same field values are equal', () {
      const a =
          AutomationSettings(enabled: true, lowThreshold: 10, highThreshold: 90);
      const b =
          AutomationSettings(enabled: true, lowThreshold: 10, highThreshold: 90);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}