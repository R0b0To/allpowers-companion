import '../models/mqtt_settings.dart';
import '../utils/logger.dart';
import 'secure_storage_source.dart';
import 'shared_preferences_source.dart';

/// Persists MQTT broker configuration: mode, host, port, credentials,
/// topic prefix, TLS, and client ID.
///
/// ## Credential storage
/// All non-sensitive fields are stored in SharedPreferences. The broker
/// password is stored in [SecureStorageSource] (platform keystore) under the
/// key `mqtt_password`.
///
/// ## Migration from plaintext
/// Versions prior to this change stored the MQTT password in SharedPreferences
/// under the key `mqtt_password`. On first load after upgrade, if the secure-
/// storage entry is absent but the SharedPreferences key has a value, the
/// password is migrated automatically and the plaintext key is removed. Users
/// do not need to re-enter their credentials.
///
/// ## Testing
/// ```dart
/// SharedPreferences.setMockInitialValues({'mqtt_mode': 'gateway'});
/// final repo = SharedPrefsMqttSettingsRepository(
///   SharedPreferencesSource(), SecureStorageSource(),
/// );
/// final s = await repo.load();
/// expect(s.mode, AppMode.gateway);
/// ```
abstract class MqttSettingsRepository {
  Future<MqttSettings> load();
  Future<void> save(MqttSettings settings);
}

final class SharedPrefsMqttSettingsRepository
    implements MqttSettingsRepository {
  SharedPrefsMqttSettingsRepository(this._source, this._secure);

  final SharedPreferencesSource _source;
  final SecureStorageSource _secure;

  // ── SharedPreferences keys (non-sensitive fields only) ────────────────────
  static const _keyMode = 'mqtt_mode';
  static const _keyBrokerHost = 'mqtt_broker_host';
  static const _keyPort = 'mqtt_port';
  static const _keyUsername = 'mqtt_username';
  static const _keyTopicPrefix = 'mqtt_topic_prefix';
  static const _keyUseTls = 'mqtt_use_tls';
  static const _keyClientId = 'mqtt_client_id';

  // ── Secure-storage key ────────────────────────────────────────────────────
  static const _secureKeyPassword = 'mqtt_password';

  // ── Legacy SharedPreferences key (present before this migration) ──────────
  static const _legacyKeyPassword = 'mqtt_password';

  @override
  Future<MqttSettings> load() async {
    try {
      final prefs = await _source.prefs;

      // --- Migration path ---------------------------------------------------
      // Read from secure storage first. If absent, check whether a plaintext
      // value exists in SharedPreferences (pre-migration install) and migrate.
      String? password =
          await _secure.storage.read(key: _secureKeyPassword);

      if (password == null) {
        final legacyPw = prefs.getString(_legacyKeyPassword);
        if (legacyPw != null && legacyPw.isNotEmpty) {
          password = legacyPw;
          await _secure.storage.write(
            key: _secureKeyPassword,
            value: password,
          );
          await prefs.remove(_legacyKeyPassword);
          Log.i('MqttSettingsRepository',
              'Migrated MQTT password to secure storage');
        }
      }
      // ---------------------------------------------------------------------

      final modeStr = prefs.getString(_keyMode) ?? AppMode.standalone.name;
      final mode = AppMode.values.firstWhere(
        (m) => m.name == modeStr,
        orElse: () => AppMode.standalone,
      );

      return MqttSettings(
        mode: mode,
        brokerHost: prefs.getString(_keyBrokerHost) ?? '',
        port: prefs.getInt(_keyPort) ?? 1883,
        username: prefs.getString(_keyUsername) ?? '',
        password: password ?? '',
        topicPrefix: prefs.getString(_keyTopicPrefix) ?? 'ap/station',
        useTls: prefs.getBool(_keyUseTls) ?? false,
        clientId: prefs.getString(_keyClientId) ?? '',
      );
    } catch (e) {
      Log.e('MqttSettingsRepository',
          'load failed — returning defaults', e);
      return const MqttSettings();
    }
  }

  @override
  Future<void> save(MqttSettings s) async {
    try {
      final prefs = await _source.prefs;

      // Password goes to secure storage; everything else to SharedPreferences.
      await _secure.storage.write(
        key: _secureKeyPassword,
        value: s.password,
      );

      await Future.wait([
        prefs.setString(_keyMode, s.mode.name),
        prefs.setString(_keyBrokerHost, s.brokerHost),
        prefs.setInt(_keyPort, s.port),
        prefs.setString(_keyUsername, s.username),
        // _legacyKeyPassword intentionally NOT written — it was cleared on migration.
        prefs.setString(_keyTopicPrefix, s.topicPrefix),
        prefs.setBool(_keyUseTls, s.useTls),
        prefs.setString(_keyClientId, s.clientId),
      ]);
    } catch (e) {
      Log.e('MqttSettingsRepository', 'save failed', e);
    }
  }
}