import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../models/power_station_status.dart';
import '../utils/logger.dart';

/// Keeps the app alive in the background as an Android foreground service.
///
/// ## Why this is needed
/// When the user switches away from the app or the screen turns off, Android
/// will eventually kill the process to reclaim memory. A foreground service
/// prevents that: it shows a persistent notification in the status bar and
/// the OS treats the process as if it were in the foreground.
///
/// ## Boot autostart
/// The `autoRunOnBoot: true` option (plus the `BootReceiver` in
/// AndroidManifest.xml) tells Android to restart the service automatically
/// after a device reboot — no user interaction required.
///
/// ## Battery optimisation
/// Even with a foreground service, aggressive OEM battery savers (Samsung,
/// Xiaomi, Huawei…) can suspend the process. Call
/// [requestBatteryOptimizationExemption] once on first launch to prompt
/// the user to whitelist the app.
abstract final class ForegroundService {
  static bool _started = false;

  // ── Initialisation ──────────────────────────────────────────────────────

  /// Must be called at the very start of [main], before [runApp].
  static void initCommunicationPort() {
    if (Platform.isAndroid) {
      FlutterForegroundTask.initCommunicationPort();
    }
  }

  // ── Start / stop ────────────────────────────────────────────────────────

  /// Configures and starts the foreground service.
  ///
  /// Safe to call multiple times — repeated calls are ignored.
  static Future<void> start() async {
    if (!Platform.isAndroid) return;
    if (_started) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ap_companion_service',
        channelName: 'AP Companion',
        channelDescription:
            'Keeps BLE monitoring and automations running in the background.',
        // LOW importance = no sound / heads-up, but still visible in the
        // notification drawer. Users expect a silent persistent notification
        // from a background service.
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // We do not poll — BLE events drive everything. A long repeat
        // interval minimises unnecessary wakeups.
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    final result = await FlutterForegroundTask.startService(
      serviceId: 1001,
      notificationTitle: 'AP Companion',
      notificationText: 'Searching for station…',
      callback: _serviceEntryPoint,
    );

    _started = result is ServiceRequestSuccess;
    if (_started) {
      Log.i('ForegroundService', 'Started');
    } else {
      Log.w('ForegroundService', 'Start result: $result');
    }
  }

  /// Stops the foreground service and removes the notification.
  ///
  /// Only call this when the user explicitly disconnects or logs out — do
  /// NOT call it in [State.dispose], since the whole purpose is to keep
  /// running after the widget tree is torn down.
  static Future<void> stop() async {
    if (!Platform.isAndroid || !_started) return;
    await FlutterForegroundTask.stopService();
    _started = false;
    Log.i('ForegroundService', 'Stopped');
  }

  // ── Notification update ─────────────────────────────────────────────────

  /// Refreshes the notification text with live station data.
  ///
  /// Called on every BLE status update so the user can glance at the
  /// notification shade to check battery without opening the app.
  static Future<void> updateStatus({
    required bool connected,
    PowerStationStatus? status,
  }) async {
    if (!Platform.isAndroid || !_started) return;

    final String title;
    final String text;

    if (!connected || status == null) {
      title = 'AP Companion';
      text = 'Searching for station…';
    } else {
      title = 'AP Companion · Connected';
      final parts = <String>['${status.batteryLevel}%'];
      if (status.isCharging) parts.add('⚡ ${status.inputWatts} W in');
      if (status.outputWatts > 0) parts.add('${status.outputWatts} W out');
      if (status.formattedRemainingTime != null) {
        parts.add(status.isCharging
            ? '${status.formattedRemainingTime} to full'
            : '${status.formattedRemainingTime} left');
      }
      text = parts.join('  ·  ');
    }

    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  // ── Battery optimisation ────────────────────────────────────────────────

  /// Prompts the user to exempt the app from battery optimisation.
  ///
  /// On Android 6+ (and especially on Samsung / Xiaomi / Huawei devices),
  /// the OS can suspend processes in the background even when a foreground
  /// service is active. Exempting the app from "battery optimisation" (also
  /// called "unrestricted battery usage") prevents this.
  ///
  /// This opens the system dialog only if the exemption has not already
  /// been granted.
  static Future<void> requestBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) return;
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }
}

// ── Task handler ──────────────────────────────────────────────────────────────

/// Minimal handler — the service shell just keeps the process alive.
/// All real work (BLE, automation engine) is driven by stream events
/// in the normal Flutter widget tree running on the main isolate.
class _MinimalTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    Log.i('ForegroundService',
        'TaskHandler.onStart (starter: ${starter.name})');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Intentionally empty — no polling needed.
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    Log.i('ForegroundService', 'TaskHandler.onDestroy (isTimeout: $isTimeout)');
  }
}

/// Top-level entry point invoked by native code when the service starts
/// (including after a device reboot). Must be a top-level function.
@pragma('vm:entry-point')
void _serviceEntryPoint() {
  FlutterForegroundTask.setTaskHandler(_MinimalTaskHandler());
}