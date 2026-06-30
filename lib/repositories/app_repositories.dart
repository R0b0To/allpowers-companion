import 'automation_settings_repository.dart';
import 'ble_repository.dart';
import 'dashboard_repository.dart';
import 'energy_log_repository.dart';
import 'flow_repository.dart';
import 'history_repository.dart';
import 'mqtt_settings_repository.dart';
import 'secure_storage_source.dart';
import 'shared_preferences_source.dart';
import 'tapo_repository.dart';

export 'automation_settings_repository.dart';
export 'ble_repository.dart';
export 'dashboard_repository.dart';
export 'energy_log_repository.dart';
export 'flow_repository.dart';
export 'history_repository.dart';
export 'mqtt_settings_repository.dart';
export 'secure_storage_source.dart';
export 'shared_preferences_source.dart';
export 'tapo_repository.dart';

/// Composition root for all persistence repositories.
///
/// ## Sources
/// Two storage sources are created here and shared across all repositories:
///
/// - [SharedPreferencesSource] — non-sensitive config (device IDs, thresholds,
///   topic prefixes, flow lists, energy logs, history).
/// - [SecureStorageSource] — sensitive credentials (Tapo device passwords,
///   MQTT broker password). Backed by platform keystore on Android and by
///   Keychain Services on iOS.
///
/// Both sources are cheap to construct and safe to share — they hold no mutable
/// state themselves; they merely provide access to the underlying platform APIs.
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
///
/// For repositories that require [SecureStorageSource], provide a mock
/// `FlutterSecureStorage` instance via the `SecureStorageSource` constructor
/// once a mock is available (or inject a fake repository directly).
final class AppRepositories {
  AppRepositories() {
    final source = SharedPreferencesSource();
    final secure = const SecureStorageSource();

    ble = SharedPrefsBleRepository(source);
    automationSettings = SharedPrefsAutomationSettingsRepository(source);
    mqttSettings = SharedPrefsMqttSettingsRepository(source, secure);
    flows = SharedPrefsFlowRepository(source);
    history = SharedPrefsHistoryRepository(source);
    energyLog = SharedPrefsEnergyLogRepository(source);
    tapo = SharedPrefsTapoRepository(source, secure);
    dashboard = SharedPrefsDashboardRepository(source);
  }

  /// BLE device pairing — used by [BleService].
  late final BleRepository ble;

  /// Smart-charging rules and thresholds — used by [MainShell].
  late final AutomationSettingsRepository automationSettings;

  /// MQTT broker configuration — used by [MainShell].
  late final MqttSettingsRepository mqttSettings;

  /// Automation flow list and per-flow edge-trigger state.
  late final FlowRepository flows;

  /// Automation execution log — used by [HistoryService].
  late final HistoryRepository history;

  /// Periodic energy samples — used by [EnergyLogService].
  late final EnergyLogRepository energyLog;

  /// Tapo device configurations — used by [TapoDeviceService].
  late final TapoRepository tapo;

  /// Dashboard widget order.
  late final DashboardRepository dashboard;
}