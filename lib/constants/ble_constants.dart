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
  //
  // FIX: wrapped in List.unmodifiable. A plain `const List<String>` literal
  // is itself immutable in Dart (the literal can't be replaced), but the
  // List instance it produces is NOT deeply protected against mutation —
  // calling `BleConstants.readCharacteristicHints.add('x')` would silently
  // succeed and corrupt this "constant" for the remainder of the process.
  // Wrapping in List.unmodifiable makes any such call throw immediately
  // instead of corrupting shared state used by every BLE connection.
  static final List<String> readCharacteristicHints =
      List.unmodifiable(['fff1', 'ffe1']);
  static final List<String> writeCharacteristicHints =
      List.unmodifiable(['fff2', 'ffe2']);

  // ── Packet framing ─────────────────────────────────────────────────────────
  static const int header1 = 0xa5;
  static const int header2 = 0x65;

  // ── Commands ───────────────────────────────────────────────────────────────

  /// Sent once after connecting. Subscribes to periodic status broadcasts.
  ///
  /// FIX: wrapped in List.unmodifiable for the same reason as the
  /// characteristic hint lists above — this exact byte sequence is written
  /// to the BLE characteristic on every connect, and an accidental mutation
  /// (e.g. a caller doing `..add(0)` while building a derived packet) would
  /// corrupt the handshake for every station this app ever talks to.
  static final List<int> requestStatusCommand = List.unmodifiable([
    header1, header2, 0xb1, 0x00, 0x01, 0x06, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
  ]);

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
  
  /// Maximum time to wait for a device to respond during auto-connect.
  static const Duration autoConnectTimeout = Duration(seconds: 20);

  /// BLE scan duration before automatically stopping.
  static const Duration scanDuration = Duration(seconds: 60);

   /// Maximum time without a status packet before the watchdog considers the
  /// connection stale and forces a reconnect, even though the OS hasn't yet
  /// fired a `disconnected` event. Several OEMs (Samsung, Xiaomi) are known
  /// to leave a GATT connection in a "zombie" state — connected per the OS,
  /// but no longer notifying — especially with `autoConnect: true` and the
  /// screen off. This is the exact failure mode gateway mode can't tolerate.
  static const Duration staleConnectionThreshold = Duration(seconds: 45);

  /// How often the watchdog timer checks for staleness.
  static const Duration watchdogCheckInterval = Duration(seconds: 15);

  /// How often to proactively re-send `requestStatusCommand` while
  /// connected, independent of whether packets are arriving on their own.
  /// Cheaper and faster than waiting for `staleConnectionThreshold` to force
  /// a full disconnect/reconnect — many "stale" cases are just a missed
  /// broadcast tick, not a dead GATT link, and a re-request alone unsticks
  /// them in under a second.
  static const Duration keepaliveInterval = Duration(seconds: 20);

  /// Base delay for the Nth auto-reconnect attempt is
  /// `min(reconnectBaseDelay * attempt, reconnectMaxDelay)`. Prevents
  /// hammering a station that's actually off or out of range with a fixed
  /// 2s retry forever, while still recovering quickly for transient drops.
  static const Duration reconnectBaseDelay = Duration(seconds: 2);
  static const Duration reconnectMaxDelay = Duration(seconds: 30);
}