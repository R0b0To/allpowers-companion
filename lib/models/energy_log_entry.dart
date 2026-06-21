/// Immutable snapshot of station metrics at a single sampled point in time.
///
/// Powers the Energy tab's consumption graphs. Recorded at a throttled
/// interval by [EnergyLogService] — never on every raw BLE packet — to keep
/// long-term storage bounded.
///
/// Uses a compact pipe-delimited serialization rather than JSON
/// ([AutomationHistoryEntry]'s approach) because the energy log accumulates
/// far more entries over time (potentially tens of thousands across weeks),
/// and the per-entry overhead of JSON keys adds up quickly in
/// SharedPreferences.
final class EnergyLogEntry {
  const EnergyLogEntry({
    required this.timestamp,
    required this.batteryLevel,
    required this.inputWatts,
    required this.outputWatts,
    required this.isUsbOn,
    required this.isAcOn,
    required this.isDcOn,
  });

  /// Always UTC — converted to local time only at display time.
  final DateTime timestamp;
  final int batteryLevel;
  final int inputWatts;
  final int outputWatts;
  final bool isUsbOn;
  final bool isAcOn;
  final bool isDcOn;

  bool get isCharging => inputWatts > 0;
  int get netWatts => inputWatts - outputWatts;

  /// Format: `epochMillisUtc|battery|inputWatts|outputWatts|socketMask`
  String toCompact() {
    var mask = 0;
    if (isUsbOn) mask |= 0x01;
    if (isAcOn) mask |= 0x02;
    if (isDcOn) mask |= 0x04;
    return '${timestamp.millisecondsSinceEpoch}|$batteryLevel|$inputWatts|$outputWatts|$mask';
  }

  /// Parses a single compact line, returning null on any malformed data so
  /// one corrupt line can't take down the whole log (same defensive pattern
  /// as [AutomationHistoryEntry.tryFromJson]).
  static EnergyLogEntry? tryFromCompact(String line) {
    try {
      final parts = line.split('|');
      if (parts.length != 5) return null;
      final mask = int.parse(parts[4]);
      return EnergyLogEntry(
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          int.parse(parts[0]),
          isUtc: true,
        ),
        batteryLevel: int.parse(parts[1]).clamp(0, 100),
        inputWatts: int.parse(parts[2]).clamp(0, 9999),
        outputWatts: int.parse(parts[3]).clamp(0, 9999),
        isUsbOn: (mask & 0x01) != 0,
        isAcOn: (mask & 0x02) != 0,
        isDcOn: (mask & 0x04) != 0,
      );
    } catch (_) {
      return null;
    }
  }
}