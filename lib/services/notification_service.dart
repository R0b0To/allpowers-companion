import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/logger.dart';

/// Wraps local notifications for the app.
///
/// ## Low-battery debouncing
/// The alert fires exactly once per "drop below threshold" event. It resets
/// only after the battery climbs back above the threshold, preventing
/// notification spam on every BLE packet while at low charge.
///
/// ## Notification IDs
/// We use fixed IDs so re-posting the same logical notification replaces
/// the previous one rather than stacking new entries in the drawer.
final class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _lowBatteryAlertActive = false;
  bool _initialized = false;

  static const int _lowBatteryNotificationId = 1;

  Future<void> init() async {
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const initSettings =
          InitializationSettings(android: androidSettings, iOS: iosSettings);

      await _plugin.initialize(initSettings);
      _initialized = true;
      Log.i('NotificationService', 'Initialized');
    } catch (e) {
      Log.e('NotificationService', 'Init failed', e);
    }
  }

  /// Call this on every BLE status update.
  ///
  /// Fires a notification only when the battery first crosses below
  /// [threshold]; resets the guard once the level rises above it.
  Future<void> handleBatteryLevel(int level, {int threshold = 20}) async {
    if (!_initialized) return;

    // Ignore bogus zero readings (common before the first real packet).
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
    try {
      const androidDetails = AndroidNotificationDetails(
        'battery_warnings',
        'Battery warnings',
        channelDescription: 'Alerts when the power station battery is low',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const details =
          NotificationDetails(android: androidDetails, iOS: iosDetails);

      await _plugin.show(
        _lowBatteryNotificationId,
        '⚡ Low battery',
        'Power station is at $level% — charge soon.',
        details,
      );
      Log.i('NotificationService', 'Low battery notification shown ($level%)');
    } catch (e) {
      Log.e('NotificationService', 'Failed to show notification', e);
    }
  }
}