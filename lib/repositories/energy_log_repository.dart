import '../models/energy_log_entry.dart';
import '../utils/logger.dart';
import 'energy_log_database.dart';
import 'shared_preferences_source.dart';

import 'package:sqflite/sqflite.dart';

/// Persists periodic energy samples for the Energy tab's consumption graphs.
///
/// ## Storage model
/// Backed by SQLite ([SqliteEnergyLogRepository]) rather than
/// SharedPreferences — see [EnergyLogDatabase]'s doc comment for why. The
/// interface reflects that: instead of [loadLog]/`saveLog(wholeList)`, a new
/// sample is appended one row at a time via [appendEntry], and the
/// implementation prunes old rows internally rather than requiring the
/// caller to pass (and rewrite) the entire capped list on every call.
///
/// Storage is capped at [maxEntries]. At the default 5-minute sampling
/// interval this covers exactly one week of continuous data (7d × 24h × 12
/// samples/h = 2,016) well within the cap. The cap of 8,640 allows for
/// shorter sampling intervals in future without a storage migration.
///
/// ## Testing
/// ```dart
/// SharedPreferences.setMockInitialValues({});
/// final db = EnergyLogDatabase(path: '/tmp/test_energy_log.db');
/// final repo = SqliteEnergyLogRepository(db, SharedPreferencesSource());
/// await repo.appendEntry(EnergyLogEntry(timestamp: DateTime.now().toUtc(), ...));
/// expect(await repo.loadLog(), hasLength(1));
/// ```
abstract class EnergyLogRepository {
  /// Maximum number of entries kept on disk. Oldest entries are pruned
  /// first once the count exceeds this.
  static const int maxEntries = 8640;

  Future<List<EnergyLogEntry>> loadLog();

  /// Appends a single new sample. Implementations are responsible for
  /// pruning entries beyond [maxEntries] as part of normal operation — not
  /// necessarily on every single call (see [SqliteEnergyLogRepository]'s
  /// batched pruning) — rather than requiring the caller to pass the whole
  /// list on every append.
  Future<void> appendEntry(EnergyLogEntry entry);

  /// Deletes every stored sample.
  Future<void> clearLog();
}

final class SqliteEnergyLogRepository implements EnergyLogRepository {
  SqliteEnergyLogRepository(
    this._db,
    this._legacySource, {
    int? maxEntriesOverride,
    int pruneEveryNAppends = 50,
  })  : _maxEntries = maxEntriesOverride ?? EnergyLogRepository.maxEntries,
        _pruneEveryNAppends = pruneEveryNAppends;

  final EnergyLogDatabase _db;

  /// Used only to read (and then delete) the legacy SharedPreferences key
  /// on first load after upgrading from a pre-SQLite install.
  final SharedPreferencesSource _legacySource;

  final int _maxEntries;

  /// Pruning is a `DELETE` that has to compute how many rows are over the
  /// cap — batching it every N appends (rather than every single one)
  /// avoids doing that work every 5 minutes when the log is nowhere near
  /// the cap. Configurable so tests can force pruning to happen
  /// deterministically without needing thousands of inserts.
  final int _pruneEveryNAppends;

  int _appendsSinceLastPrune = 0;

  static const _legacyKeyEnergyLog = 'energy_log';

  @override
  Future<List<EnergyLogEntry>> loadLog() async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        EnergyLogDatabase.tableName,
        orderBy: 'timestampMs ASC',
      );
      if (rows.isEmpty) {
        return _migrateFromSharedPreferencesIfPresent();
      }
      return rows.map(_entryFromRow).toList();
    } catch (e) {
      Log.e('EnergyLogRepository', 'loadLog failed', e);
      return [];
    }
  }

  /// One-time migration path: versions prior to this change stored the
  /// energy log as a pipe-delimited SharedPreferences string list under
  /// [_legacyKeyEnergyLog]. If the SQLite table is empty (fresh DB — either
  /// a brand-new install, or an upgrade that hasn't migrated yet), check
  /// for that legacy data, import it, and remove the legacy key so this
  /// path is only ever taken once.
  Future<List<EnergyLogEntry>> _migrateFromSharedPreferencesIfPresent() async {
    try {
      final prefs = await _legacySource.prefs;
      final raw = prefs.getStringList(_legacyKeyEnergyLog);
      if (raw == null || raw.isEmpty) return [];

      final entries = <EnergyLogEntry>[];
      for (final line in raw) {
        final entry = EnergyLogEntry.tryFromCompact(line);
        if (entry != null) entries.add(entry);
        // Corrupt lines are skipped, same defensive pattern as the
        // pre-migration loader used.
      }

      if (entries.isEmpty) {
        await prefs.remove(_legacyKeyEnergyLog);
        return [];
      }

      Log.i('EnergyLogRepository',
          'Migrating ${entries.length} legacy energy sample(s) to SQLite');
      final db = await _db.database;
      final batch = db.batch();
      for (final e in entries) {
        batch.insert(
          EnergyLogDatabase.tableName,
          _rowFromEntry(e),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
      await prefs.remove(_legacyKeyEnergyLog);

      return entries;
    } catch (e) {
      Log.e('EnergyLogRepository', 'Legacy migration failed', e);
      return [];
    }
  }

  @override
  Future<void> appendEntry(EnergyLogEntry entry) async {
    try {
      final db = await _db.database;
      await db.insert(
        EnergyLogDatabase.tableName,
        _rowFromEntry(entry),
        // Same timestamp arriving twice (should be practically impossible
        // given EnergyLogService's interval spacing, but not worth an
        // exception over) replaces rather than duplicates.
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      _appendsSinceLastPrune++;
      if (_appendsSinceLastPrune >= _pruneEveryNAppends) {
        _appendsSinceLastPrune = 0;
        await _pruneOldEntries(db);
      }
    } catch (e) {
      Log.e('EnergyLogRepository', 'appendEntry failed', e);
    }
  }

  Future<void> _pruneOldEntries(Database db) async {
    final count = Sqflite.firstIntValue(
          await db.rawQuery(
              'SELECT COUNT(*) FROM ${EnergyLogDatabase.tableName}'),
        ) ??
        0;
    final overflow = count - _maxEntries;
    if (overflow <= 0) return;

    await db.delete(
      EnergyLogDatabase.tableName,
      where: 'timestampMs IN '
          '(SELECT timestampMs FROM ${EnergyLogDatabase.tableName} '
          'ORDER BY timestampMs ASC LIMIT ?)',
      whereArgs: [overflow],
    );
    Log.d('EnergyLogRepository', 'Pruned $overflow old sample(s)');
  }

  @override
  Future<void> clearLog() async {
    try {
      final db = await _db.database;
      await db.delete(EnergyLogDatabase.tableName);
    } catch (e) {
      Log.e('EnergyLogRepository', 'clearLog failed', e);
    }
  }

  Map<String, dynamic> _rowFromEntry(EnergyLogEntry e) {
    var mask = 0;
    if (e.isUsbOn) mask |= 0x01;
    if (e.isAcOn) mask |= 0x02;
    if (e.isDcOn) mask |= 0x04;
    return {
      'timestampMs': e.timestamp.millisecondsSinceEpoch,
      'batteryLevel': e.batteryLevel,
      'inputWatts': e.inputWatts,
      'outputWatts': e.outputWatts,
      'socketMask': mask,
    };
  }

  EnergyLogEntry _entryFromRow(Map<String, dynamic> row) {
    final mask = row['socketMask'] as int;
    return EnergyLogEntry(
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        row['timestampMs'] as int,
        isUtc: true,
      ),
      batteryLevel: (row['batteryLevel'] as int).clamp(0, 100),
      inputWatts: (row['inputWatts'] as int).clamp(0, 9999),
      outputWatts: (row['outputWatts'] as int).clamp(0, 9999),
      isUsbOn: (mask & 0x01) != 0,
      isAcOn: (mask & 0x02) != 0,
      isDcOn: (mask & 0x04) != 0,
    );
  }
}