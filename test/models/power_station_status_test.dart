import 'package:flutter_test/flutter_test.dart';

import 'package:ap_companion/models/power_station_status.dart';

void main() {
  group('PowerStationStatus', () {
    test('default values are sensible', () {
      const s = PowerStationStatus();
      expect(s.batteryLevel, 0);
      expect(s.inputWatts, 0);
      expect(s.outputWatts, 0);
      expect(s.isUsbOn, false);
      expect(s.isAcOn, false);
      expect(s.isDcOn, false);
    });

    test('validated clamps batteryLevel to 0–100', () {
      final s = PowerStationStatus.validated(
        batteryLevel: 150,
        inputWatts: 0,
        outputWatts: 0,
        minutesRemaining:0,
        isUsbOn: false,
        isAcOn: false,
        isDcOn: false,
      );
      expect(s.batteryLevel, 100);
    });

    test('validated clamps negative wattage to 0', () {
      final s = PowerStationStatus.validated(
        batteryLevel: 50,
        inputWatts: -5,
        outputWatts: -10,
        minutesRemaining:0,
        isUsbOn: false,
        isAcOn: false,
        isDcOn: false,
      );
      expect(s.inputWatts, 0);
      expect(s.outputWatts, 0);
    });

    test('isCharging returns true when inputWatts > 0', () {
      const s = PowerStationStatus(batteryLevel: 50, inputWatts: 120);
      expect(s.isCharging, true);
    });

    test('isCharging returns false when inputWatts == 0', () {
      const s = PowerStationStatus(batteryLevel: 50, inputWatts: 0);
      expect(s.isCharging, false);
    });

    test('netWatts is positive when charging exceeds draw', () {
      const s = PowerStationStatus(inputWatts: 200, outputWatts: 80);
      expect(s.netWatts, 120);
    });

    test('hasActiveOutlet reflects any outlet being on', () {
      expect(const PowerStationStatus(isUsbOn: true).hasActiveOutlet, true);
      expect(const PowerStationStatus(isAcOn: true).hasActiveOutlet, true);
      expect(const PowerStationStatus(isDcOn: true).hasActiveOutlet, true);
      expect(const PowerStationStatus().hasActiveOutlet, false);
    });

    test('copyWith only updates specified fields', () {
      const original = PowerStationStatus(
        batteryLevel: 50,
        inputWatts: 100,
        isAcOn: true,
      );
      final copy = original.copyWith(batteryLevel: 75);
      expect(copy.batteryLevel, 75);
      expect(copy.inputWatts, 100);  // unchanged
      expect(copy.isAcOn, true);     // unchanged
    });

    test('equality compares all fields', () {
      const a = PowerStationStatus(batteryLevel: 50, inputWatts: 100);
      const b = PowerStationStatus(batteryLevel: 50, inputWatts: 100);
      const c = PowerStationStatus(batteryLevel: 51, inputWatts: 100);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}