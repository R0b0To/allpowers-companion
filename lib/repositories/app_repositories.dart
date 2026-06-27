import 'automation_settings_repository.dart';
import 'ble_repository.dart';
import 'dashboard_repository.dart';
import 'energy_log_repository.dart';
import 'flow_repository.dart';
import 'history_repository.dart';
import 'mqtt_settings_repository.dart';
import 'shared_preferences_source.dart';
import 'tapo_repository.dart';

export 'automation_settings_repository.dart';
export 'ble_repository.dart';
export 'dashboard_repository.dart';
export 'energy_log_repository.dart';
export 'flow_repository.dart';
export 'history_repository.dart';
export 'mqtt_settings_repository.dart';
export 'shared_preferences_source.dart';
export 'tapo_repository.dart';

/// Composition root for all persistence repositories.
///
/// ## Why a container class?
/// Services should depend on the *narrowest* interface that satisfies their
/// needs (e.g. [BleService] needs only [BleRepository], not everything).
/// [AppRepositories] creates every concrete implementation once, wiring all
/// of them to a single [SharedPreferencesSource], and exposes each through
/// its abstract interface type.
///
/// [MainShell] holds the single [AppRepositories] instance and passes the
/// relevant field to each service constructor:
///
/// ```dart
/// final _repos = AppRepositories();
///
/// // In _MainShellState.initState:
/// _ble          = BleService(_repos.ble);
/// _history      = HistoryService(_repos.history);
/// _energyLog    = EnergyLogService(_repos.energyLog);
/// _tapoDevices  = TapoDeviceService(_tapo, _repos.tapo);
/// _flowEngine   = FlowEngine(_ble, _webhooks, _tapo,
///                            _tapoDevices, _history, _repos.flows);
///
/// // In _bootstrap:
/// final settings = await _repos.automationSettings.load();
/// final mqtt     = await _repos.mqttSettings.load();
/// final flows    = await _repos.flows.loadFlows();
/// ```
///
/// ## Testing
/// For unit tests, construct individual repositories directly and pass them
/// without going through [AppRepositories]:
///
/// ```dart
/// SharedPreferences.setMockInitialValues({});
/// final source  = SharedPreferencesSource();
/// final history = SharedPrefsHistoryRepository(source);
/// final service = HistoryService(history);
/// ```
final class AppRepositories {
  AppRepositories() {
    final source = SharedPreferencesSource();

    ble                = SharedPrefsBleRepository(source);
    automationSettings = SharedPrefsAutomationSettingsRepository(source);
    mqttSettings       = SharedPrefsMqttSettingsRepository(source);
    flows              = SharedPrefsFlowRepository(source);
    history            = SharedPrefsHistoryRepository(source);
    energyLog          = SharedPrefsEnergyLogRepository(source);
    tapo               = SharedPrefsTapoRepository(source);
    dashboard          = SharedPrefsDashboardRepository(source);
  }

  /// BLE device pairing — used by [BleService].
  late final BleRepository ble;

  /// Smart-charging rules and thresholds — used by [MainShell].
  late final AutomationSettingsRepository automationSettings;

  /// MQTT broker configuration — used by [MainShell].
  late final MqttSettingsRepository mqttSettings;

  /// Automation flow list and per-flow edge-trigger state —
  /// used by [MainShell] (flow list) and [FlowEngine] (trigger state).
  late final FlowRepository flows;

  /// Automation execution log — used by [HistoryService].
  late final HistoryRepository history;

  /// Periodic energy samples — used by [EnergyLogService].
  late final EnergyLogRepository energyLog;

  /// Tapo device configurations — used by [TapoDeviceService].
  late final TapoRepository tapo;

  /// Dashboard widget order — used by any future dashboard service.
  late final DashboardRepository dashboard;
}
