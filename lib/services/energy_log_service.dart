import 'package:flutter/foundation.dart';

import '../models/energy_log_entry.dart';
import '../models/power_station_status.dart';
import 'storage_service.dart';

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
/// persisted via [StorageService], which caps the stored count — see
/// [StorageService] for the current limit and the rationale.
final class EnergyLogService extends ChangeNotifier {
  EnergyLogService(
    this._storage, {
    this.interval = const Duration(minutes: 5),
  });

  final StorageService _storage;

  /// Minimum spacing between recorded samples.
  final Duration interval;

  List<EnergyLogEntry> _entries = const [];
  bool _isLoaded = false;

  /// Oldest first.
  List<EnergyLogEntry> get entries => _entries;
  bool get isLoaded => _isLoaded;

  /// Must be called once during app bootstrap to restore persisted samples.
  Future<void> init() async {
    _entries = await _storage.loadEnergyLog();
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
    await _storage.saveEnergyLog(_entries);
  }

  Future<void> clear() async {
    _entries = const [];
    notifyListeners();
    await _storage.saveEnergyLog(_entries);
  }

  /// Entries no older than [duration] from now.
  List<EnergyLogEntry> since(Duration duration) {
    final cutoff = DateTime.now().toUtc().subtract(duration);
    final idx = _entries.indexWhere((e) => !e.timestamp.isBefore(cutoff));
    if (idx == -1) return const [];
    return _entries.sublist(idx);
  }
}