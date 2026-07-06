import 'package:flutter_test/flutter_test.dart';

import 'package:ap_companion/constants/ble_constants.dart';
import 'package:ap_companion/models/power_station_status.dart';
import 'package:ap_companion/services/status_packet_parser.dart';

/// Builds a syntactically valid 16-byte Allpowers status packet, with every
/// field overridable so individual tests can isolate one field at a time.
List<int> _buildStatusPacket({
  int header1 = BleConstants.header1,
  int header2 = BleConstants.header2,
  int packetType = BleConstants.statusPacketType,
  int socketMask = 0,
  int batteryLevel = 50,
  int inputWatts = 0,
  int outputWatts = 0,
  int minutesRemaining = 0,
}) {
  final bytes = List<int>.filled(16, 0);
  bytes[0] = header1;
  bytes[1] = header2;
  bytes[5] = packetType;
  bytes[BleConstants.socketMaskOffset] = socketMask;
  bytes[BleConstants.batteryLevelOffset] = batteryLevel;
  bytes[BleConstants.inputWattsHighByteOffset] = (inputWatts >> 8) & 0xFF;
  bytes[BleConstants.inputWattsHighByteOffset + 1] = inputWatts & 0xFF;
  bytes[BleConstants.outputWattsHighByteOffset] = (outputWatts >> 8) & 0xFF;
  bytes[BleConstants.outputWattsHighByteOffset + 1] = outputWatts & 0xFF;
  bytes[BleConstants.minutesRemainingHighByteOffset] =
      (minutesRemaining >> 8) & 0xFF;
  bytes[BleConstants.minutesRemainingHighByteOffset + 1] =
      minutesRemaining & 0xFF;
  return bytes;
}

void main() {
  group('StatusPacketParser.decode — length and header validation', () {
    test('rejects a packet shorter than the minimum length', () {
      expect(StatusPacketParser.decode([0xa5, 0x65, 0x08]), isA<PacketTooShort>());
    });

    test('rejects an empty payload', () {
      expect(StatusPacketParser.decode(const []), isA<PacketTooShort>());
    });

    test('accepts a packet exactly at the minimum length', () {
      final bytes = _buildStatusPacket();
      expect(bytes.length, BleConstants.minStatusPacketLength);
      expect(StatusPacketParser.decode(bytes), isA<StatusPacket>());
    });

    test('rejects a full-length packet with the wrong first header byte', () {
      final bytes = _buildStatusPacket(header1: 0x00);
      final result = StatusPacketParser.decode(bytes);
      expect(result, isA<UnknownHeader>());
      expect((result as UnknownHeader).byte0, 0x00);
      expect(result.byte1, BleConstants.header2);
    });

    test('rejects a full-length packet with the wrong second header byte', () {
      final bytes = _buildStatusPacket(header2: 0xff);
      expect(StatusPacketParser.decode(bytes), isA<UnknownHeader>());
    });

    test(
        'a stray 16+ byte notification from an unrelated characteristic is '
        'rejected by header, not accidentally parsed as status', () {
      // This is the exact regression the header check exists to prevent —
      // see the FIX comment previously on BleService._parseStatusPacket:
      // only byte[5] (packet type) was checked at first, so any 16+ byte
      // payload that happened to have 0x08 at offset 5 would be misread as
      // a status report.
      final bytes = List<int>.filled(16, 0)..[5] = BleConstants.statusPacketType;
      expect(StatusPacketParser.decode(bytes), isA<UnknownHeader>());
    });
  });

  group('StatusPacketParser.decode — packet type dispatch', () {
    test('a valid header with a non-status packet type is recognized as such',
        () {
      final bytes = _buildStatusPacket(packetType: 0x01);
      expect(StatusPacketParser.decode(bytes), isA<UnrecognizedPacketType>());
    });
  });

  group('StatusPacketParser.decode — field extraction', () {
    test('decodes battery level directly from its offset', () {
      final bytes = _buildStatusPacket(batteryLevel: 77);
      final result = StatusPacketParser.decode(bytes) as StatusPacket;
      expect(result.batteryLevel, 77);
    });

    test('decodes 16-bit big-endian input watts', () {
      final bytes = _buildStatusPacket(inputWatts: 0x01F4); // 500
      final result = StatusPacketParser.decode(bytes) as StatusPacket;
      expect(result.inputWatts, 500);
    });

    test('decodes 16-bit big-endian output watts', () {
      final bytes = _buildStatusPacket(outputWatts: 0x00C8); // 200
      final result = StatusPacketParser.decode(bytes) as StatusPacket;
      expect(result.outputWatts, 200);
    });

    test('decodes 16-bit big-endian minutes remaining, including the max value',
        () {
      final bytes = _buildStatusPacket(minutesRemaining: 0xFFFF);
      final result = StatusPacketParser.decode(bytes) as StatusPacket;
      expect(result.minutesRemaining, 65535);
    });

    test('decodes the raw socket mask byte unmodified', () {
      final bytes = _buildStatusPacket(
        socketMask: BleConstants.usbMask | BleConstants.dcMask,
      );
      final result = StatusPacketParser.decode(bytes) as StatusPacket;
      expect(result.socketMask & BleConstants.usbMask, isNot(0));
      expect(result.socketMask & BleConstants.acMask, 0);
      expect(result.socketMask & BleConstants.dcMask, isNot(0));
    });

    test('extra trailing bytes beyond the minimum length are ignored', () {
      final bytes = [..._buildStatusPacket(batteryLevel: 33), 0xAA, 0xBB, 0xCC];
      final result = StatusPacketParser.decode(bytes) as StatusPacket;
      expect(result.batteryLevel, 33);
    });
  });

  group('StatusPacketParser.applyToStatus', () {
    const baseStatus = PowerStationStatus(
      batteryLevel: 10,
      inputWatts: 5,
      outputWatts: 0,
      minutesRemaining: 100,
      isUsbOn: true,
      isAcOn: false,
      isDcOn: false,
    );

    test(
        'updates battery/power/time fields and socket state when not '
        'suppressed', () {
      const packet = StatusPacket(
        batteryLevel: 60,
        inputWatts: 120,
        outputWatts: 0,
        minutesRemaining: 200,
        socketMask: BleConstants.acMask,
      );

      final result = StatusPacketParser.applyToStatus(
        current: baseStatus,
        packet: packet,
        suppressSocketState: false,
      );

      expect(result.batteryLevel, 60);
      expect(result.inputWatts, 120);
      expect(result.minutesRemaining, 200);
      expect(result.isUsbOn, isFalse); // mask doesn't include USB → cleared
      expect(result.isAcOn, isTrue);
      expect(result.isDcOn, isFalse);
    });

    test(
        'preserves existing socket state and ignores the packet mask during '
        'the manual-override window', () {
      // This is the exact scenario BleService's manual-override window
      // exists for: the user just toggled an outlet locally, and a status
      // packet arrives before the station's own state has caught up. If
      // this packet's (stale) socket mask were applied, it would visibly
      // flip the toggle back for a moment.
      const staleMaskPacket = StatusPacket(
        batteryLevel: 15,
        inputWatts: 5,
        outputWatts: 0,
        minutesRemaining: 95,
        socketMask: 0, // stale — would otherwise clear isUsbOn
      );

      final result = StatusPacketParser.applyToStatus(
        current: baseStatus,
        packet: staleMaskPacket,
        suppressSocketState: true,
      );

      expect(result.isUsbOn, isTrue); // preserved from `current`, not packet
      expect(result.isAcOn, isFalse);
      expect(result.isDcOn, isFalse);
      // Non-socket fields still update even while suppressed.
      expect(result.batteryLevel, 15);
      expect(result.minutesRemaining, 95);
    });

    test('all three outlet bits can be simultaneously on', () {
      const packet = StatusPacket(
        batteryLevel: 50,
        inputWatts: 0,
        outputWatts: 0,
        minutesRemaining: 0,
        socketMask:
            BleConstants.usbMask | BleConstants.acMask | BleConstants.dcMask,
      );

      final result = StatusPacketParser.applyToStatus(
        current: baseStatus,
        packet: packet,
        suppressSocketState: false,
      );

      expect(result.isUsbOn, isTrue);
      expect(result.isAcOn, isTrue);
      expect(result.isDcOn, isTrue);
    });
  });
}