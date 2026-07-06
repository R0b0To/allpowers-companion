/// Immutable snapshot of station metrics at a single sampled point in time.
///
/// Powers the Energy tab's consumption graphs. Recorded at a throttled
/// interval by [EnergyLogService] — never on every raw BLE packet — to keep
/// long-term storage bounded.
///
/// ## Compact format
/// [toCompact]/[tryFromCompact] serialize to a pipe-delimited string
/// (`epochMs|battery|inputW|outputW|socketMask`). The primary store is now
/// SQLite (see [EnergyLogRepository]), but this compact format is still
/// used to read entries out of the legacy SharedPreferences store during
/// the one-time migration a pre-SQLite install goes through on first load
/// — see `SqliteEnergyLogRepository._migrateFromSharedPreferencesIfPresent`.
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
  /// one corrupt line can't take down the whole migration (same defensive
  /// pattern as [AutomationHistoryEntry.tryFromJson]).
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