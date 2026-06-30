import 'dart:convert';

import '../models/tapo_device.dart';
import '../utils/logger.dart';
import 'secure_storage_source.dart';
import 'shared_preferences_source.dart';

/// Persists the list of saved TP-Link Tapo smart plug configurations.
///
/// ## Credential storage
/// Device configs (id, name, ip, email) are stored in SharedPreferences as
/// JSON. Passwords are stored separately in [SecureStorageSource] (encrypted
/// at rest via the platform keystore) under the key `tapo_pw_<device_id>`.
///
/// Runtime-only state (`isOnline`, `isOn`, `model`) is intentionally not
/// persisted — [TapoDevice.toJson] already excludes these fields and they
/// are refreshed on each poll cycle by [TapoDeviceService].
///
/// ## Migration from plaintext
/// Versions prior to this change stored the full JSON including the password
/// in SharedPreferences. On first load after upgrade, if a device's password
/// is found inside the SharedPreferences JSON but is absent from secure
/// storage, it is migrated automatically and cleared from the JSON. Users do
/// not need to re-enter credentials.
///
/// ## Testing
/// ```dart
/// SharedPreferences.setMockInitialValues({});
/// final source = SharedPreferencesSource();
/// final secure = SecureStorageSource();
/// final repo = SharedPrefsTapoRepository(source, secure);
///
/// final device = TapoDevice(
///   id: 'dev_1', name: 'Garage', ip: '192.168.1.100',
///   email: 'user@example.com', password: 'secret',
/// );
/// await repo.saveDevices([device]);
/// final loaded = await repo.loadDevices();
/// expect(loaded.first.name, 'Garage');
/// expect(loaded.first.password, 'secret');
/// ```
abstract class TapoRepository {
  Future<List<TapoDevice>> loadDevices();
  Future<void> saveDevices(List<TapoDevice> devices);
}

final class SharedPrefsTapoRepository implements TapoRepository {
  SharedPrefsTapoRepository(this._source, this._secure);

  final SharedPreferencesSource _source;
  final SecureStorageSource _secure;

  static const _keyTapoDevices = 'tapo_devices';

  /// Secure-storage key for a device's password.
  static String _pwKey(String deviceId) => 'tapo_pw_$deviceId';

  @override
  Future<List<TapoDevice>> loadDevices() async {
    try {
      final prefs = await _source.prefs;
      final raw = prefs.getStringList(_keyTapoDevices) ?? [];
      final devices = <TapoDevice>[];

      for (final s in raw) {
        try {
          final json = jsonDecode(s) as Map<String, dynamic>;
          final id = json['id'] as String? ?? '';
          if (id.isEmpty) continue;

          // --- Migration path -------------------------------------------
          // Prior versions wrote 'password' inside the SharedPrefs JSON.
          // If secure storage has no entry for this device but the JSON
          // does, migrate the plaintext value to secure storage and strip
          // it from the on-disk JSON on the next save().
          final storedPw =
              await _secure.storage.read(key: _pwKey(id));

          if (storedPw == null) {
            final legacyPw = json['password'] as String? ?? '';
            if (legacyPw.isNotEmpty) {
              await _secure.storage.write(
                key: _pwKey(id),
                value: legacyPw,
              );
              Log.i('TapoRepository',
                  'Migrated password for device $id to secure storage');
            }
          }
          // ------------------------------------------------------------

          final password = storedPw ??
              (await _secure.storage.read(key: _pwKey(id))) ??
              '';

          final d = TapoDevice(
            id: id,
            name: json['name'] as String? ?? '',
            ip: json['ip'] as String? ?? '',
            email: json['email'] as String? ?? '',
            password: password,
          );
          devices.add(d);
        } catch (_) {
          // Skip corrupt entries; one bad record does not break the list.
        }
      }

      return devices;
    } catch (e) {
      Log.e('TapoRepository', 'loadDevices failed', e);
      return [];
    }
  }

  @override
  Future<void> saveDevices(List<TapoDevice> devices) async {
    try {
      final prefs = await _source.prefs;

      // Determine which device IDs are being removed so we can purge their
      // secure-storage entries and avoid orphaned secrets.
      final existing = prefs.getStringList(_keyTapoDevices) ?? [];
      final existingIds = <String>{};
      for (final s in existing) {
        try {
          final id = (jsonDecode(s) as Map<String, dynamic>)['id'] as String?;
          if (id != null) existingIds.add(id);
        } catch (_) {}
      }
      final incomingIds = devices.map((d) => d.id).toSet();
      final removedIds = existingIds.difference(incomingIds);
      for (final id in removedIds) {
        await _secure.storage.delete(key: _pwKey(id));
        Log.d('TapoRepository', 'Deleted secure-storage entry for removed device $id');
      }

      // Persist each device's password to secure storage; store config
      // (without password) in SharedPreferences.
      for (final d in devices) {
        await _secure.storage.write(key: _pwKey(d.id), value: d.password);
      }

      await prefs.setStringList(
        _keyTapoDevices,
        devices.map((d) => jsonEncode(_toJsonWithoutPassword(d))).toList(),
      );
    } catch (e) {
      Log.e('TapoRepository', 'saveDevices failed', e);
    }
  }

  /// JSON representation without the password field.
  /// Passwords live exclusively in [SecureStorageSource].
  static Map<String, dynamic> _toJsonWithoutPassword(TapoDevice d) => {
        'id': d.id,
        'name': d.name,
        'ip': d.ip,
        'email': d.email,
      };
}