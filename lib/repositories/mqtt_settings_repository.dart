import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/mqtt_settings.dart';
import '../utils/logger.dart';
import 'secure_storage_source.dart';
import 'shared_preferences_source.dart';

/// Persists MQTT broker configuration: mode, host, port, credentials,
/// topic prefix, TLS, and client ID.
///
/// ## Credential storage
/// The broker password is stored in [SecureStorageSource] (platform
/// keystore) under the key `mqtt_password`, kept deliberately separate from
/// the JSON blob below — secure storage and SharedPreferences have
/// different security guarantees and shouldn't be mixed.
///
/// ## Non-sensitive field storage
/// Every other field is stored as a single JSON blob under
/// [_keySettingsJson]. Previously each field was written as its own
/// SharedPreferences key via `Future.wait`; a process kill between two of
/// those writes could leave the stored settings an inconsistent mix of old
/// and new values (e.g. a new [MqttSettings.mode] paired with a stale
/// [MqttSettings.brokerHost]). A single key removes that window.
///
/// ## Migration from plaintext password
/// Versions prior to this change stored the MQTT password in SharedPreferences
/// under the key `mqtt_password`. On first load after upgrade, if the secure-
/// storage entry is absent but the SharedPreferences key has a value, the
/// password is migrated automatically and the plaintext key is removed. Users
/// do not need to re-enter their credentials.
///
/// ## Migration from per-field keys
/// If [_keySettingsJson] is absent (pre-upgrade install), [load] falls back
/// to the legacy per-field keys, builds an [MqttSettings] from them,
/// persists it under the new key, and removes the legacy keys.
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

  // ── Current storage key (non-sensitive fields only) ───────────────────────
  static const _keySettingsJson = 'mqtt_settings_json';

  // ── Legacy per-field SharedPreferences keys (pre-migration) ───────────────
  static const _legacyKeyMode = 'mqtt_mode';
  static const _legacyKeyBrokerHost = 'mqtt_broker_host';
  static const _legacyKeyPort = 'mqtt_port';
  static const _legacyKeyUsername = 'mqtt_username';
  static const _legacyKeyTopicPrefix = 'mqtt_topic_prefix';
  static const _legacyKeyUseTls = 'mqtt_use_tls';
  static const _legacyKeyClientId = 'mqtt_client_id';

  // ── Secure-storage key ────────────────────────────────────────────────────
  static const _secureKeyPassword = 'mqtt_password';

  // ── Legacy SharedPreferences key for the plaintext password ───────────────
  static const _legacyKeyPassword = 'mqtt_password';

  @override
  Future<MqttSettings> load() async {
    try {
      final prefs = await _source.prefs;

      // --- Password migration (independent of the field-bundling migration
      // below — its own guard, unchanged from before) ------------------------
      String? password = await _secure.storage.read(key: _secureKeyPassword);

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

      final raw = prefs.getString(_keySettingsJson);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        return _fromNonSensitiveJson(j, password: password ?? '');
      }

      return _migrateFromLegacyKeys(prefs, password: password ?? '');
    } catch (e) {
      Log.e('MqttSettingsRepository', 'load failed — returning defaults', e);
      return const MqttSettings();
    }
  }

  Future<MqttSettings> _migrateFromLegacyKeys(
    SharedPreferences prefs, {
    required String password,
  }) async {
    final hasLegacyData = prefs.containsKey(_legacyKeyMode) ||
        prefs.containsKey(_legacyKeyBrokerHost) ||
        prefs.containsKey(_legacyKeyPort) ||
        prefs.containsKey(_legacyKeyUsername) ||
        prefs.containsKey(_legacyKeyTopicPrefix) ||
        prefs.containsKey(_legacyKeyUseTls) ||
        prefs.containsKey(_legacyKeyClientId);

    final modeStr = prefs.getString(_legacyKeyMode) ?? AppMode.standalone.name;
    final mode = AppMode.values.firstWhere(
      (m) => m.name == modeStr,
      orElse: () => AppMode.standalone,
    );

    final settings = MqttSettings(
      mode: mode,
      brokerHost: prefs.getString(_legacyKeyBrokerHost) ?? '',
      port: prefs.getInt(_legacyKeyPort) ?? 1883,
      username: prefs.getString(_legacyKeyUsername) ?? '',
      password: password,
      topicPrefix: prefs.getString(_legacyKeyTopicPrefix) ?? 'ap/station',
      useTls: prefs.getBool(_legacyKeyUseTls) ?? false,
      clientId: prefs.getString(_legacyKeyClientId) ?? '',
    );

    if (hasLegacyData) {
      Log.i('MqttSettingsRepository',
          'Migrating legacy per-field MQTT settings to single JSON key');
      await _saveNonSensitive(settings);
      await Future.wait([
        prefs.remove(_legacyKeyMode),
        prefs.remove(_legacyKeyBrokerHost),
        prefs.remove(_legacyKeyPort),
        prefs.remove(_legacyKeyUsername),
        prefs.remove(_legacyKeyTopicPrefix),
        prefs.remove(_legacyKeyUseTls),
        prefs.remove(_legacyKeyClientId),
      ]);
    }

    return settings;
  }

  MqttSettings _fromNonSensitiveJson(
    Map<String, dynamic> j, {
    required String password,
  }) {
    final modeStr = j['mode'] as String? ?? AppMode.standalone.name;
    final mode = AppMode.values.firstWhere(
      (m) => m.name == modeStr,
      orElse: () => AppMode.standalone,
    );
    return MqttSettings(
      mode: mode,
      brokerHost: j['brokerHost'] as String? ?? '',
      port: (j['port'] as num?)?.toInt() ?? 1883,
      username: j['username'] as String? ?? '',
      password: password,
      topicPrefix: j['topicPrefix'] as String? ?? 'ap/station',
      useTls: j['useTls'] as bool? ?? false,
      clientId: j['clientId'] as String? ?? '',
    );
  }

  Map<String, dynamic> _toNonSensitiveJson(MqttSettings s) => {
        'mode': s.mode.name,
        'brokerHost': s.brokerHost,
        'port': s.port,
        'username': s.username,
        'topicPrefix': s.topicPrefix,
        'useTls': s.useTls,
        'clientId': s.clientId,
      };

  Future<void> _saveNonSensitive(MqttSettings s) async {
    final prefs = await _source.prefs;
    await prefs.setString(
        _keySettingsJson, jsonEncode(_toNonSensitiveJson(s)));
  }

  @override
  Future<void> save(MqttSettings s) async {
    try {
      // Password goes to secure storage; everything else to the JSON blob.
      await _secure.storage.write(
        key: _secureKeyPassword,
        value: s.password,
      );
      await _saveNonSensitive(s);
    } catch (e) {
      Log.e('MqttSettingsRepository', 'save failed', e);
    }
  }
}