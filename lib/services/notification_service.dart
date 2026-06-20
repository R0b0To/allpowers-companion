import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Wraps local notifications. Unlike the original implementation, this only
/// fires a low-battery alert once per "drop below threshold" event instead
/// of on every single BLE status packet (which could arrive several times
/// a second) -- the alert resets once the level rises back above it.
class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _lowBatteryAlertActive = false;

  Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _plugin.initialize(initSettings);
  }

  /// Call this on every status update. Only emits a notification the
  /// moment the level first crosses at or below [threshold].
  Future<void> handleBatteryLevel(int level, {int threshold = 20}) async {
    if (level <= 0) return;

    if (level <= threshold) {
      if (!_lowBatteryAlertActive) {
        _lowBatteryAlertActive = true;
        await _showLowBatteryNotification(level);
      }
    } else {
      _lowBatteryAlertActive = false;
    }
  }

  Future<void> _showLowBatteryNotification(int level) async {
    const androidDetails = AndroidNotificationDetails(
      'battery_warnings',
      'Battery warnings',
      importance: Importance.max,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _plugin.show(1, '⚠️ Low battery', '$level%', details);
  }
}