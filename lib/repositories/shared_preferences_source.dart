import 'package:shared_preferences/shared_preferences.dart';

/// Single access point for [SharedPreferences] shared across all repositories.
///
/// ## Why inject a source rather than call `getInstance` in each repo?
///
/// `SharedPreferences.getInstance()` is async and returns the same singleton,
/// but calling it from eight repositories during parallel bootstrap creates
/// eight independent `Future` chains.  Caching the `Future` itself (not the
/// resolved value) in one place means:
///
/// 1. Only one native platform call is ever made.
/// 2. All concurrent callers share the same `Future`; the `??=` assignment
///    executes synchronously inside Dart's single-threaded event loop before
///    any `await` yields, so the race that existed in the old
///    `StorageService._getPrefs()` is structurally impossible here.
/// 3. Every repository becomes independently unit-testable:
///    ```dart
///    SharedPreferences.setMockInitialValues({});
///    final source = SharedPreferencesSource();
///    final repo   = SharedPrefsBleRepository(source);
///    ```
///
/// Pass a single [SharedPreferencesSource] instance (created once in
/// [AppRepositories]) to every repository constructor.
final class SharedPreferencesSource {
  Future<SharedPreferences>? _prefsFuture;

  /// Returns the shared [SharedPreferences] instance.
  ///
  /// Safe to call concurrently from multiple repositories during app bootstrap.
  Future<SharedPreferences> get prefs {
    _prefsFuture ??= SharedPreferences.getInstance();
    return _prefsFuture!;
  }
}
