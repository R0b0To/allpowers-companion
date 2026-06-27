import '../utils/logger.dart';
import 'shared_preferences_source.dart';

/// Persists the remote ID of the last successfully connected BLE device so
/// [BleService] can auto-reconnect on the next app launch without scanning.
///
/// ## Testing
/// ```dart
/// SharedPreferences.setMockInitialValues({});
/// final repo = SharedPrefsBleRepository(SharedPreferencesSource());
/// await repo.setSavedDeviceId('AA:BB:CC:DD:EE:FF');
/// expect(await repo.getSavedDeviceId(), 'AA:BB:CC:DD:EE:FF');
/// ```
abstract class BleRepository {
  Future<String?> getSavedDeviceId();
  Future<void> setSavedDeviceId(String id);
  Future<void> clearSavedDeviceId();
}

final class SharedPrefsBleRepository implements BleRepository {
  SharedPrefsBleRepository(this._source);

  final SharedPreferencesSource _source;

  static const _keyDeviceId = 'saved_device_id';

  @override
  Future<String?> getSavedDeviceId() async {
    try {
      return (await _source.prefs).getString(_keyDeviceId);
    } catch (e) {
      Log.e('BleRepository', 'getSavedDeviceId failed', e);
      return null;
    }
  }

  @override
  Future<void> setSavedDeviceId(String id) async {
    try {
      await (await _source.prefs).setString(_keyDeviceId, id);
    } catch (e) {
      Log.e('BleRepository', 'setSavedDeviceId failed', e);
    }
  }

  @override
  Future<void> clearSavedDeviceId() async {
    try {
      await (await _source.prefs).remove(_keyDeviceId);
    } catch (e) {
      Log.e('BleRepository', 'clearSavedDeviceId failed', e);
    }
  }
}
