import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Single access point for the on-device SQLite database backing the
/// energy log.
///
/// ## Why SQLite instead of SharedPreferences?
/// The energy log accumulates up to [EnergyLogRepository.maxEntries] samples
/// (one week at the default 5-minute interval) and appends a new sample
/// roughly every 5 minutes for as long as the app runs. Previously each
/// append rewrote the *entire* capped list as a SharedPreferences string
/// list — an O(n) serialize-and-write on every single sample, purely to add
/// one row. SQLite lets a new sample be a single `INSERT`, with pruning of
/// old rows handled by an occasional batched `DELETE` (see
/// [SqliteEnergyLogRepository]) rather than every write touching the whole
/// dataset.
///
/// Mirrors [SharedPreferencesSource]'s rationale: a single cached instance
/// avoids reopening the database file on every repository call, and an
/// injectable path makes the repository independently unit-testable
/// without touching the real on-device database file.
///
/// ## Testing
/// ```dart
/// final db = EnergyLogDatabase(path: inMemoryDatabasePath);
/// // ...or a unique temp file path per test; see
/// // test/repositories/energy_log_repository_test.dart.
/// ```
final class EnergyLogDatabase {
  EnergyLogDatabase({String? path}) : _overridePath = path;

  /// Overrides the real on-device database path — used only by tests.
  /// `null` in production, which resolves the standard per-platform
  /// databases directory via [getDatabasesPath].
  final String? _overridePath;

  Future<Database>? _dbFuture;

  static const tableName = 'energy_log';

  /// Returns the shared [Database] instance, opening (and creating the
  /// schema for) it on first access.
  ///
  /// Safe to call concurrently — mirrors [SharedPreferencesSource.prefs]:
  /// the `??=` assignment executes synchronously before any `await` yields,
  /// so concurrent callers during app bootstrap share the same `Future`
  /// rather than racing to open the file twice.
  Future<Database> get database {
    _dbFuture ??= _open();
    return _dbFuture!;
  }

  Future<Database> _open() async {
    final path =
        _overridePath ?? p.join(await getDatabasesPath(), 'energy_log.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $tableName (
            timestampMs INTEGER PRIMARY KEY,
            batteryLevel INTEGER NOT NULL,
            inputWatts INTEGER NOT NULL,
            outputWatts INTEGER NOT NULL,
            socketMask INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_energy_log_timestamp ON $tableName (timestampMs)',
        );
      },
    );
  }
}