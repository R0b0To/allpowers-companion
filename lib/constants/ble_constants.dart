/// Byte-level constants for the Allpowers BLE protocol.
///
/// NOTE: the "request status" handshake packet sends `0xb1` at offset 2,
/// while the "set socket state" command sends it at offset 3 (with a 0x00
/// swapped into offset 2). This mirrors the original implementation as-is
/// since there's no protocol spec to verify against here -- if outlet
/// toggles ever stop working, this header ordering is the first thing to
/// check against your station's actual documentation.
class BleConstants {
  BleConstants._();

  /// Substrings used to identify the read/write characteristics among a
  /// device's services, since exact UUIDs can vary slightly by firmware.
  static const List<String> readCharacteristicHints = ['fff1', 'ffe1'];
  static const List<String> writeCharacteristicHints = ['fff2', 'ffe2'];

  static const int header1 = 0xa5;
  static const int header2 = 0x65;

  /// Sent once right after connecting, to subscribe to periodic status
  /// packets from the station.
  static const List<int> requestStatusCommand = [
    header1, header2, 0xb1, 0x00, 0x01, 0x06, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
  ];

  /// Packet type byte (offset 5) identifying a full status report.
  static const int statusPacketType = 0x08;
  static const int minStatusPacketLength = 16;

  // Offsets within a status packet.
  static const int socketMaskOffset = 7;
  static const int batteryLevelOffset = 8;
  static const int inputWattsHighByteOffset = 9;
  static const int outputWattsHighByteOffset = 11;

  static const int usbMask = 0x01;
  static const int acMask = 0x02;
  static const int dcMask = 0x04;
}