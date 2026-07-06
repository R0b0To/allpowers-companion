import '../constants/ble_constants.dart';
import '../models/power_station_status.dart';

/// Outcome of decoding a single BLE notification payload against the
/// Allpowers protocol framing.
sealed class PacketDecodeResult {
  const PacketDecodeResult();
}

/// Fewer bytes than the shortest valid packet — too short even to attempt
/// header validation.
final class PacketTooShort extends PacketDecodeResult {
  const PacketTooShort();
}

/// Long enough, but the first two bytes don't match the protocol's magic
/// header (`0xa5 0x65`) — most likely a stray notification from an
/// unrelated characteristic rather than a corrupted station packet.
final class UnknownHeader extends PacketDecodeResult {
  const UnknownHeader(this.byte0, this.byte1);
  final int byte0;
  final int byte1;
}

/// Valid header and length, but the packet-type byte (offset 5) is not
/// [BleConstants.statusPacketType] — e.g. a handshake acknowledgement.
/// The link is confirmed alive; there's simply no new station data here.
final class UnrecognizedPacketType extends PacketDecodeResult {
  const UnrecognizedPacketType();
}

/// A full, decodable status report.
final class StatusPacket extends PacketDecodeResult {
  const StatusPacket({
    required this.batteryLevel,
    required this.inputWatts,
    required this.outputWatts,
    required this.minutesRemaining,
    required this.socketMask,
  });

  final int batteryLevel;
  final int inputWatts;
  final int outputWatts;
  final int minutesRemaining;
  final int socketMask;
}

/// Pure, stateless decoder for Allpowers BLE status packets.
///
/// Extracted from `BleService._parseStatusPacket` so the packet format —
/// header validation, packet-type dispatch, byte offsets, big-endian 16-bit
/// field assembly, and the manual-override merge rule — can be unit tested
/// with plain byte arrays, without a real BLE connection, a
/// `BluetoothCharacteristic`, or any platform channel. `BleService` still
/// owns everything genuinely stateful: recording `lastPacketTime`, holding
/// the current [PowerStationStatus], the manual-override window's timing,
/// and deciding when to call `notifyListeners`. This class only answers
/// "what does this byte array mean" and "how does it combine with the
/// current status" — nothing about *when* those questions get asked.
abstract final class StatusPacketParser {
  static PacketDecodeResult decode(List<int> bytes) {
    if (bytes.length < BleConstants.minStatusPacketLength) {
      return const PacketTooShort();
    }

    if (bytes[0] != BleConstants.header1 || bytes[1] != BleConstants.header2) {
      return UnknownHeader(bytes[0], bytes[1]);
    }

    if (bytes[5] != BleConstants.statusPacketType) {
      return const UnrecognizedPacketType();
    }

    return StatusPacket(
      batteryLevel: bytes[BleConstants.batteryLevelOffset],
      inputWatts: (bytes[BleConstants.inputWattsHighByteOffset] << 8) |
          bytes[BleConstants.inputWattsHighByteOffset + 1],
      outputWatts: (bytes[BleConstants.outputWattsHighByteOffset] << 8) |
          bytes[BleConstants.outputWattsHighByteOffset + 1],
      minutesRemaining:
          (bytes[BleConstants.minutesRemainingHighByteOffset] << 8) |
              bytes[BleConstants.minutesRemainingHighByteOffset + 1],
      socketMask: bytes[BleConstants.socketMaskOffset],
    );
  }

  /// Merges a decoded [packet] into [current], returning the resulting
  /// [PowerStationStatus].
  ///
  /// When [suppressSocketState] is true (`BleService`'s manual-override
  /// window, active briefly after a local outlet command), the packet's
  /// socket-mask bits are ignored and the outlet states already present in
  /// [current] are kept — this is what stops a status packet that hasn't
  /// caught up yet from clobbering an optimistic local toggle. Battery,
  /// power, and remaining-time fields are always taken from the packet
  /// regardless of [suppressSocketState].
  static PowerStationStatus applyToStatus({
    required PowerStationStatus current,
    required StatusPacket packet,
    required bool suppressSocketState,
  }) {
    if (suppressSocketState) {
      return current.copyWith(
        batteryLevel: packet.batteryLevel,
        inputWatts: packet.inputWatts,
        outputWatts: packet.outputWatts,
        minutesRemaining: packet.minutesRemaining,
      );
    }
    return current.copyWith(
      batteryLevel: packet.batteryLevel,
      inputWatts: packet.inputWatts,
      outputWatts: packet.outputWatts,
      minutesRemaining: packet.minutesRemaining,
      isUsbOn: (packet.socketMask & BleConstants.usbMask) != 0,
      isAcOn: (packet.socketMask & BleConstants.acMask) != 0,
      isDcOn: (packet.socketMask & BleConstants.dcMask) != 0,
    );
  }
}