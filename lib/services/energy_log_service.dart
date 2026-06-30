import 'package:flutter/foundation.dart';

import '../models/energy_log_entry.dart';
import '../models/power_station_status.dart';
import '../repositories/energy_log_repository.dart';

/// Records periodic snapshots of station metrics for the Energy tab.
///
/// ## Throttling
/// [BleService] can emit a status update multiple times per second; storing
/// every one would bloat SharedPreferences within hours. Instead, a sample
/// is only appended once at least [interval] has elapsed since the
/// *previously stored* sample's timestamp. Because this is based on stored
/// data rather than a wall-clock [Timer], it survives app restarts
/// correctly: relaunching after being closed for a day doesn't backfill —
/// it just waits for the next [interval] to elapse from the last real
/// sample before resuming.
///
/// ## Storage model
/// Entries are kept oldest-first in memory (convenient for charting) and
/// persisted via [EnergyLogRepository], which caps the stored count at
/// [EnergyLogRepository.maxEntries].
final class EnergyLogService extends ChangeNotifier {
  EnergyLogService(
    this._repository, {
    this.interval = const Duration(minutes: 5),
  });

  final EnergyLogRepository _repository;

  /// Minimum spacing between recorded samples.
  final Duration interval;

  List<EnergyLogEntry> _entries = const [];
  bool _isLoaded = false;

  /// Oldest first.
  List<EnergyLogEntry> get entries => _entries;
  bool get isLoaded => _isLoaded;

  /// Must be called once during app bootstrap to restore persisted samples.
  Future<void> init() async {
    _entries = await _repository.loadLog();
    _isLoaded = true;
    notifyListeners();
  }

  /// Call on every BLE status update — internally throttles to [interval].
  Future<void> recordSample(PowerStationStatus status) async {
    if (!_isLoaded) return;
    if (status.batteryLevel <= 0) return; // Bogus pre-first-packet reading.

    final now = DateTime.now().toUtc();
    if (_entries.isNotEmpty &&
        now.difference(_entries.last.timestamp) < interval) {
      return;
    }

    final entry = EnergyLogEntry(
      timestamp: now,
      batteryLevel: status.batteryLevel,
      inputWatts: status.inputWatts,
      outputWatts: status.outputWatts,
      isUsbOn: status.isUsbOn,
      isAcOn: status.isAcOn,
      isDcOn: status.isDcOn,
    );

    _entries = [..._entries, entry];
    notifyListeners();
    await _repository.saveLog(_entries);
  }

  Future<void> clear() async {
    _entries = const [];
    notifyListeners();
    await _repository.saveLog(_entries);
  }

  /// Returns entries no older than [duration] from now.
  ///
  /// FIX: previously returned `_entries.sublist(idx)`, which in Dart is a
  /// fresh growable List but is filled by copying the *current* element
  /// references in the *current* range. The bug this fixes isn't aliasing
  /// of the backing array (sublist always copies), but call-site lifetime:
  /// callers (e.g. EnergyTab._entriesAndStats) compare list *identity*
  /// across rebuilds to decide whether to recompute cached stats. Returning
  /// `List.unmodifiable(...)` here makes the immutability contract explicit
  /// and prevents any future caller from mutating what looks like a fresh
  /// list but is logically meant to be a read-only view, while keeping the
  /// identity-based caching in EnergyTab correct (a new sample always
  /// produces a new List instance here).
  List<EnergyLogEntry> since(Duration duration) {
    if (_entries.isEmpty) return const [];
    final cutoff = DateTime.now().toUtc().subtract(duration);
    final idx = _lowerBound(cutoff);
    if (idx >= _entries.length) return const [];
    return List.unmodifiable(_entries.sublist(idx));
  }

  /// Returns the index of the first entry whose timestamp is not before
  /// [cutoff], using binary search on the sorted [_entries] list.
  ///
  /// Returns [_entries.length] if all entries are before [cutoff].
  int _lowerBound(DateTime cutoff) {
    int lo = 0;
    int hi = _entries.length;
    final cutoffMs = cutoff.millisecondsSinceEpoch;
    while (lo < hi) {
      final mid = lo + ((hi - lo) >> 1);
      if (_entries[mid].timestamp.millisecondsSinceEpoch < cutoffMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}