import 'package:flutter_test/flutter_test.dart';

import 'package:ap_companion/models/energy_log_entry.dart';

void main() {
  group('EnergyLogEntry', () {
    test('round-trips through the compact format', () {
      final entry = EnergyLogEntry(
        timestamp: DateTime.utc(2026, 3, 1, 12, 0, 0),
        batteryLevel: 55,
        inputWatts: 120,
        outputWatts: 30,
        isUsbOn: true,
        isAcOn: false,
        isDcOn: true,
      );

      final decoded = EnergyLogEntry.tryFromCompact(entry.toCompact());

      expect(decoded, isNotNull);
      expect(decoded!.timestamp, entry.timestamp);
      expect(decoded.batteryLevel, 55);
      expect(decoded.inputWatts, 120);
      expect(decoded.outputWatts, 30);
      expect(decoded.isUsbOn, isTrue);
      expect(decoded.isAcOn, isFalse);
      expect(decoded.isDcOn, isTrue);
    });

    test('every combination of outlet bits round-trips through the mask', () {
      for (var mask = 0; mask < 8; mask++) {
        final entry = EnergyLogEntry(
          timestamp: DateTime.utc(2026, 1, 1),
          batteryLevel: 10,
          inputWatts: 0,
          outputWatts: 0,
          isUsbOn: (mask & 0x01) != 0,
          isAcOn: (mask & 0x02) != 0,
          isDcOn: (mask & 0x04) != 0,
        );

        final decoded = EnergyLogEntry.tryFromCompact(entry.toCompact());

        expect(decoded!.isUsbOn, entry.isUsbOn, reason: 'mask=$mask');
        expect(decoded.isAcOn, entry.isAcOn, reason: 'mask=$mask');
        expect(decoded.isDcOn, entry.isDcOn, reason: 'mask=$mask');
      }
    });

    test('returns null for a line with the wrong number of fields', () {
      expect(EnergyLogEntry.tryFromCompact('1|2|3'), isNull);
    });

    test('returns null for non-numeric fields instead of throwing', () {
      expect(EnergyLogEntry.tryFromCompact('abc|2|3|4|0'), isNull);
    });

    test('clamps battery level and watt values to their legal ranges', () {
      final decoded = EnergyLogEntry.tryFromCompact('0|500|-10|99999|0');

      expect(decoded, isNotNull);
      expect(decoded!.batteryLevel, 100); // clamped from 500
      expect(decoded.inputWatts, 0); // clamped from -10
      expect(decoded.outputWatts, 9999); // clamped from 99999
    });

    test('isCharging is true only when inputWatts is positive', () {
      final charging = EnergyLogEntry(
        timestamp: DateTime.utc(2026, 1, 1),
        batteryLevel: 50,
        inputWatts: 10,
        outputWatts: 0,
        isUsbOn: false,
        isAcOn: false,
        isDcOn: false,
      );
      final notCharging = EnergyLogEntry(
        timestamp: DateTime.utc(2026, 1, 1),
        batteryLevel: 50,
        inputWatts: 0,
        outputWatts: 10,
        isUsbOn: false,
        isAcOn: false,
        isDcOn: false,
      );

      expect(charging.isCharging, isTrue);
      expect(notCharging.isCharging, isFalse);
    });

    test('netWatts is input minus output', () {
      final entry = EnergyLogEntry(
        timestamp: DateTime.utc(2026, 1, 1),
        batteryLevel: 50,
        inputWatts: 120,
        outputWatts: 45,
        isUsbOn: false,
        isAcOn: false,
        isDcOn: false,
      );

      expect(entry.netWatts, 75);
    });
  });
}