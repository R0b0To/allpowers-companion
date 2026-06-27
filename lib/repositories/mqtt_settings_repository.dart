import '../models/mqtt_settings.dart';
import '../utils/logger.dart';
import 'shared_preferences_source.dart';

/// Persists MQTT broker configuration: mode, host, port, credentials,
/// topic prefix, TLS, and client ID.
///
/// ## Testing
/// ```dart
/// SharedPreferences.setMockInitialValues({'mqtt_mode': 'gateway'});
/// final repo = SharedPrefsMqttSettingsRepository(SharedPreferencesSource());
/// final s = await repo.load();
/// expect(s.mode, AppMode.gateway);
/// ```
abstract class MqttSettingsRepository {
  Future<MqttSettings> load();
  Future<void> save(MqttSettings settings);
}

final class SharedPrefsMqttSettingsRepository implements MqttSettingsRepository {
  SharedPrefsMqttSettingsRepository(this._source);

  final SharedPreferencesSource _source;

  // ── Keys ──────────────────────────────────────────────────────────────────
  static const _keyMode        = 'mqtt_mode';
  static const _keyBrokerHost  = 'mqtt_broker_host';
  static const _keyPort        = 'mqtt_port';
  static const _keyUsername    = 'mqtt_username';
  static const _keyPassword    = 'mqtt_password';
  static const _keyTopicPrefix = 'mqtt_topic_prefix';
  static const _keyUseTls      = 'mqtt_use_tls';
  static const _keyClientId    = 'mqtt_client_id';

  @override
  Future<MqttSettings> load() async {
    try {
      final prefs = await _source.prefs;
      final modeStr = prefs.getString(_keyMode) ?? AppMode.standalone.name;
      final mode = AppMode.values.firstWhere(
        (m) => m.name == modeStr,
        orElse: () => AppMode.standalone,
      );
      return MqttSettings(
        mode:        mode,
        brokerHost:  prefs.getString(_keyBrokerHost)  ?? '',
        port:        prefs.getInt(_keyPort)            ?? 1883,
        username:    prefs.getString(_keyUsername)     ?? '',
        password:    prefs.getString(_keyPassword)     ?? '',
        topicPrefix: prefs.getString(_keyTopicPrefix)  ?? 'ap/station',
        useTls:      prefs.getBool(_keyUseTls)         ?? false,
        clientId:    prefs.getString(_keyClientId)     ?? '',
      );
    } catch (e) {
      Log.e('MqttSettingsRepository', 'load failed — returning defaults', e);
      return const MqttSettings();
    }
  }

  @override
  Future<void> save(MqttSettings s) async {
    try {
      final prefs = await _source.prefs;
      await Future.wait([
        prefs.setString(_keyMode,        s.mode.name),
        prefs.setString(_keyBrokerHost,  s.brokerHost),
        prefs.setInt(_keyPort,           s.port),
        prefs.setString(_keyUsername,    s.username),
        prefs.setString(_keyPassword,    s.password),
        prefs.setString(_keyTopicPrefix, s.topicPrefix),
        prefs.setBool(_keyUseTls,        s.useTls),
        prefs.setString(_keyClientId,    s.clientId),
      ]);
    } catch (e) {
      Log.e('MqttSettingsRepository', 'save failed', e);
    }
  }
}
