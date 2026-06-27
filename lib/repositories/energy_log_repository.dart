import '../models/energy_log_entry.dart';
import '../utils/logger.dart';
import 'shared_preferences_source.dart';

/// Persists periodic energy samples using [EnergyLogEntry]'s compact
/// pipe-delimited format (`epochMs|battery|inputW|outputW|socketMask`).
///
/// Storage is capped at [maxEntries].  At the default 5-minute sampling
/// interval this covers exactly one week of continuous data (7d × 24h × 12
/// samples/h = 2 016) well within the cap.  The cap of 8 640 allows for
/// shorter sampling intervals in future without a storage migration.
///
/// Entries are kept oldest-first in memory and on disk so the binary search
/// in [EnergyLogService.since] works correctly.
///
/// ## Testing
/// ```dart
/// SharedPreferences.setMockInitialValues({});
/// final repo = SharedPrefsEnergyLogRepository(SharedPreferencesSource());
/// await repo.saveLog([EnergyLogEntry(timestamp: DateTime.now().toUtc(), ...)]);
/// expect(await repo.loadLog(), hasLength(1));
/// ```
abstract class EnergyLogRepository {
  /// Maximum number of entries kept on disk.
  /// Oldest entries are dropped when the cap is exceeded.
  static const int maxEntries = 8640;

  Future<List<EnergyLogEntry>> loadLog();
  Future<void> saveLog(List<EnergyLogEntry> entries);
}

final class SharedPrefsEnergyLogRepository implements EnergyLogRepository {
  SharedPrefsEnergyLogRepository(this._source);

  final SharedPreferencesSource _source;

  static const _keyEnergyLog = 'energy_log';

  @override
  Future<List<EnergyLogEntry>> loadLog() async {
    try {
      final prefs   = await _source.prefs;
      final raw     = prefs.getStringList(_keyEnergyLog) ?? [];
      final entries = <EnergyLogEntry>[];
      for (final line in raw) {
        final entry = EnergyLogEntry.tryFromCompact(line);
        if (entry != null) entries.add(entry);
        // Silently skip corrupt lines — defensive pattern from EnergyLogEntry.
      }
      return entries;
    } catch (e) {
      Log.e('EnergyLogRepository', 'loadLog failed', e);
      return [];
    }
  }

  @override
  Future<void> saveLog(List<EnergyLogEntry> entries) async {
    try {
      final prefs = await _source.prefs;
      // Keep only the NEWEST [maxEntries] samples (list is oldest-first,
      // so we take the tail when over the cap).
      final capped = entries.length > EnergyLogRepository.maxEntries
          ? entries.sublist(entries.length - EnergyLogRepository.maxEntries)
          : entries;
      await prefs.setStringList(
        _keyEnergyLog,
        capped.map((e) => e.toCompact()).toList(),
      );
    } catch (e) {
      Log.e('EnergyLogRepository', 'saveLog failed', e);
    }
  }
}
