import 'dart:convert';

import '../models/tapo_device.dart';
import '../utils/logger.dart';
import 'shared_preferences_source.dart';

/// Persists the list of saved TP-Link Tapo smart plug configurations.
///
/// Runtime-only state (`isOnline`, `isOn`, `model`) is intentionally not
/// persisted — [TapoDevice.toJson] already excludes these fields and they
/// are refreshed on each poll cycle by [TapoDeviceService].
///
/// ## Testing
/// ```dart
/// SharedPreferences.setMockInitialValues({});
/// final repo = SharedPrefsTapoRepository(SharedPreferencesSource());
///
/// final device = TapoDevice(
///   id: 'dev_1', name: 'Garage', ip: '192.168.1.100',
///   email: 'user@example.com', password: 'secret',
/// );
/// await repo.saveDevices([device]);
/// final loaded = await repo.loadDevices();
/// expect(loaded.first.name, 'Garage');
/// ```
abstract class TapoRepository {
  Future<List<TapoDevice>> loadDevices();
  Future<void> saveDevices(List<TapoDevice> devices);
}

final class SharedPrefsTapoRepository implements TapoRepository {
  SharedPrefsTapoRepository(this._source);

  final SharedPreferencesSource _source;

  static const _keyTapoDevices = 'tapo_devices';

  @override
  Future<List<TapoDevice>> loadDevices() async {
    try {
      final prefs   = await _source.prefs;
      final raw     = prefs.getStringList(_keyTapoDevices) ?? [];
      final devices = <TapoDevice>[];
      for (final s in raw) {
        try {
          final d = TapoDevice.tryFromJson(jsonDecode(s) as Map<String, dynamic>);
          if (d != null) devices.add(d);
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
      await prefs.setStringList(
        _keyTapoDevices,
        devices.map((d) => jsonEncode(d.toJson())).toList(),
      );
    } catch (e) {
      Log.e('TapoRepository', 'saveDevices failed', e);
    }
  }
}
