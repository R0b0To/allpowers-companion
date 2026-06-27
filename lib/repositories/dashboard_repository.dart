import '../utils/logger.dart';
import 'shared_preferences_source.dart';

/// Persists the ordered list of dashboard widget IDs so the user's
/// custom layout survives app restarts.
///
/// This is intentionally the smallest repository — its existence is
/// justified not by complexity but by the single-responsibility principle:
/// dashboard layout config has nothing to do with BLE device pairing,
/// MQTT credentials, or energy samples.
///
/// ## Testing
/// ```dart
/// SharedPreferences.setMockInitialValues({});
/// final repo = SharedPrefsDashboardRepository(SharedPreferencesSource());
/// await repo.saveConfig(['battery_ring', 'metrics_row', 'outlet_controls']);
/// expect(await repo.loadConfig(), hasLength(3));
/// ```
abstract class DashboardRepository {
  Future<List<String>> loadConfig();
  Future<void> saveConfig(List<String> widgetIds);
}

final class SharedPrefsDashboardRepository implements DashboardRepository {
  SharedPrefsDashboardRepository(this._source);

  final SharedPreferencesSource _source;

  static const _keyDashboardConfig = 'dashboard_config';

  @override
  Future<List<String>> loadConfig() async {
    try {
      return (await _source.prefs).getStringList(_keyDashboardConfig) ?? [];
    } catch (e) {
      Log.e('DashboardRepository', 'loadConfig failed', e);
      return [];
    }
  }

  @override
  Future<void> saveConfig(List<String> widgetIds) async {
    try {
      await (await _source.prefs).setStringList(_keyDashboardConfig, widgetIds);
    } catch (e) {
      Log.e('DashboardRepository', 'saveConfig failed', e);
    }
  }
}
