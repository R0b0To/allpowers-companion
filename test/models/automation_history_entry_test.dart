import 'package:flutter_test/flutter_test.dart';

import 'package:ap_companion/models/automation_history_entry.dart';

void main() {
  group('AutomationHistoryEntry', () {
    test('round-trips through JSON', () {
      final entry = AutomationHistoryEntry(
        timestamp: DateTime.utc(2026, 1, 15, 10, 30),
        action: HistoryAction.tapoOn,
        batteryLevel: 42,
        success: true,
        method: ActivationMethod.localTapo,
        flowName: 'Start Charging',
        deviceName: 'Garage Plug',
      );

      final decoded = AutomationHistoryEntry.tryFromJson(entry.toJson());

      expect(decoded, isNotNull);
      expect(decoded!.timestamp, entry.timestamp);
      expect(decoded.action, HistoryAction.tapoOn);
      expect(decoded.batteryLevel, 42);
      expect(decoded.success, isTrue);
      expect(decoded.method, ActivationMethod.localTapo);
      expect(decoded.flowName, 'Start Charging');
      expect(decoded.deviceName, 'Garage Plug');
    });

    test('clamps an out-of-range battery level rather than throwing', () {
      final json = {
        'timestamp': DateTime.utc(2026, 1, 1).toIso8601String(),
        'action': 'turnOn',
        'batteryLevel': 250,
        'success': true,
        'method': 'localTapo',
      };

      final decoded = AutomationHistoryEntry.tryFromJson(json);

      expect(decoded, isNotNull);
      expect(decoded!.batteryLevel, 100);
    });

    test('returns null for malformed JSON instead of throwing', () {
      expect(AutomationHistoryEntry.tryFromJson({'garbage': true}), isNull);
    });

    test('defaults an unrecognised action name to turnOn for forward compatibility', () {
      final json = {
        'timestamp': DateTime.utc(2026, 1, 1).toIso8601String(),
        'action': 'someFutureAction',
        'batteryLevel': 50,
        'success': true,
        'method': 'none',
      };

      final decoded = AutomationHistoryEntry.tryFromJson(json);

      expect(decoded, isNotNull);
      expect(decoded!.action, HistoryAction.turnOn);
    });

    test('defaults an unrecognised method name to none', () {
      final json = {
        'timestamp': DateTime.utc(2026, 1, 1).toIso8601String(),
        'action': 'turnOn',
        'batteryLevel': 50,
        'success': true,
        'method': 'someFutureMethod',
      };

      final decoded = AutomationHistoryEntry.tryFromJson(json);

      expect(decoded, isNotNull);
      expect(decoded!.method, ActivationMethod.none);
    });

    test('flowName and deviceName default to empty string when absent', () {
      final json = {
        'timestamp': DateTime.utc(2026, 1, 1).toIso8601String(),
        'action': 'turnOn',
        'batteryLevel': 50,
        'success': true,
        'method': 'none',
      };

      final decoded = AutomationHistoryEntry.tryFromJson(json);

      expect(decoded!.flowName, '');
      expect(decoded.deviceName, '');
    });
  });
}