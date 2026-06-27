import 'dart:convert';

import '../models/automation_history_entry.dart';
import '../utils/logger.dart';
import 'shared_preferences_source.dart';

/// Persists automation execution history (newest-first order).
///
/// Storage is capped at [maxEntries] to bound SharedPreferences growth.
/// The cap constant is public so UI copy ("last 200 actions") can stay
/// in sync with the implementation without duplicating the magic number.
///
/// ## Testing
/// ```dart
/// SharedPreferences.setMockInitialValues({});
/// final repo = SharedPrefsHistoryRepository(SharedPreferencesSource());
///
/// final entry = AutomationHistoryEntry(
///   timestamp: DateTime.now(), action: HistoryAction.tapoOn,
///   batteryLevel: 50, success: true, method: ActivationMethod.localTapo,
/// );
/// await repo.saveHistory([entry]);
///
/// final loaded = await repo.loadHistory();
/// expect(loaded.first.batteryLevel, 50);
/// ```
abstract class HistoryRepository {
  /// Maximum number of entries persisted. Oldest entries are dropped first.
  static const int maxEntries = 200;

  Future<List<AutomationHistoryEntry>> loadHistory();
  Future<void> saveHistory(List<AutomationHistoryEntry> entries);
}

final class SharedPrefsHistoryRepository implements HistoryRepository {
  SharedPrefsHistoryRepository(this._source);

  final SharedPreferencesSource _source;

  static const _keyHistory = 'automation_history';

  @override
  Future<List<AutomationHistoryEntry>> loadHistory() async {
    try {
      final prefs   = await _source.prefs;
      final raw     = prefs.getStringList(_keyHistory) ?? [];
      final entries = <AutomationHistoryEntry>[];
      for (final s in raw) {
        try {
          final e = AutomationHistoryEntry.tryFromJson(
            jsonDecode(s) as Map<String, dynamic>,
          );
          if (e != null) entries.add(e);
        } catch (_) {
          // Skip corrupt entries; one bad record does not invalidate the rest.
        }
      }
      return entries;
    } catch (e) {
      Log.e('HistoryRepository', 'loadHistory failed', e);
      return [];
    }
  }

  @override
  Future<void> saveHistory(List<AutomationHistoryEntry> entries) async {
    try {
      final prefs  = await _source.prefs;
      // Keep only the newest [maxEntries] entries (list is newest-first).
      final capped = entries.length > HistoryRepository.maxEntries
          ? entries.sublist(0, HistoryRepository.maxEntries)
          : entries;
      await prefs.setStringList(
        _keyHistory,
        capped.map((e) => jsonEncode(e.toJson())).toList(),
      );
    } catch (e) {
      Log.e('HistoryRepository', 'saveHistory failed', e);
    }
  }
}
