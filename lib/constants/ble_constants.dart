/// Byte-level constants for the Allpowers BLE protocol.
///
/// ## Header ordering note
/// The "request status" handshake packet sends `0xb1` at offset 2 and
/// `0x00` at offset 3. The "set socket state" command swaps these — `0x00`
/// at offset 2, `0xb1` at offset 3. This mirrors the original implementation
/// exactly; if outlet toggles stop working, this header ordering is the
/// first thing to verify against live packet captures.
///
/// ## Characteristic discovery
/// UUIDs vary slightly across firmware versions, so we match by substring
/// rather than exact equality. A device may expose multiple services; we
/// take the last matching characteristic found (later services tend to be
/// the application-level ones on Allpowers hardware).
abstract final class BleConstants {
  // ── Characteristic UUID substrings ─────────────────────────────────────────
  static const List<String> readCharacteristicHints = ['fff1', 'ffe1'];
  static const List<String> writeCharacteristicHints = ['fff2', 'ffe2'];

  // ── Packet framing ─────────────────────────────────────────────────────────
  static const int header1 = 0xa5;
  static const int header2 = 0x65;

  // ── Commands ───────────────────────────────────────────────────────────────

  /// Sent once after connecting. Subscribes to periodic status broadcasts.
  static const List<int> requestStatusCommand = [
    header1, header2, 0xb1, 0x00, 0x01, 0x06, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
  ];

  // ── Status packet structure ─────────────────────────────────────────────────
  /// Value at byte [5] that identifies a full status report packet.
  static const int statusPacketType = 0x08;

  /// Minimum valid length for a status packet.
  static const int minStatusPacketLength = 16;

  // Byte offsets within a status packet.
  static const int socketMaskOffset = 7;
  static const int batteryLevelOffset = 8;
  static const int inputWattsHighByteOffset = 9;   // High byte; low byte at offset 10.
  static const int outputWattsHighByteOffset = 11; // High byte; low byte at offset 12.
  static const int minutesRemainingHighByteOffset = 13; // High byte; low byte at offset 14.

  // ── Socket bitmask values ──────────────────────────────────────────────────
  static const int usbMask = 0x01;
  static const int acMask = 0x02;
  static const int dcMask = 0x04;

  // ── Timing ────────────────────────────────────────────────────────────────
  /// After a manual outlet command, status packets received within this
  /// window must not overwrite the optimistic local state — the station
  /// can take several packets to reflect the relay change.
  static const Duration manualOverrideWindow = Duration(milliseconds: 1500);

  /// Grace delay before retrying an auto-connect after an unexpected
  /// disconnect, to let the OS fully tear down the prior connection.
  static const Duration reconnectDelay = Duration(seconds: 2);

  /// Maximum time to wait for a device to respond during auto-connect.
  static const Duration autoConnectTimeout = Duration(seconds: 20);

  /// BLE scan duration before automatically stopping.
  static const Duration scanDuration = Duration(seconds: 60);
}