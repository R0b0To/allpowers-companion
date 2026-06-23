import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/app_strings.dart';
import '../models/automation_settings.dart';
import '../services/automation_engine.dart';
import '../services/ble_service.dart';
import '../services/energy_log_service.dart';
import '../services/foreground_service.dart';
import '../services/history_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/tapo_service.dart';
import '../services/webhook_service.dart';
import '../theme/app_theme.dart';
import 'automations_tab.dart';
import 'control_tab.dart';
import 'energy_tab.dart';
import 'history_tab.dart';

/// Root shell: owns all service singletons and hosts the bottom navigation.
///
/// ## Background execution
/// After bootstrap completes, [ForegroundService.start] promotes the process
/// to an Android foreground service so it survives screen-off, app switch,
/// and device reboot. All BLE callbacks and the automation engine continue
/// running on the main isolate — the foreground service is a thin shell
/// whose only job is to prevent the OS from killing the process.
///
/// On iOS the foreground service is a no-op; background BLE continuity is
/// handled instead by the `bluetooth-central` background mode declared in
/// Info.plist.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // ── Services ───────────────────────────────────────────────────────────────
  final _storage = StorageService();
  final _notifications = NotificationService();
  final _webhooks = WebhookService();
  final _tapo = TapoService();

  late final HistoryService _history = HistoryService(_storage);
  late final EnergyLogService _energyLog = EnergyLogService(_storage);
  late final BleService _ble;
  late final AutomationEngine _automation;

  // ── UI state ───────────────────────────────────────────────────────────────
  AutomationSettings _settings = const AutomationSettings();
  bool _permissionsPermanentlyDenied = false;
  int _selectedIndex = 0;
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    _ble = BleService(_storage);
    _automation = AutomationEngine(_ble, _webhooks, _tapo, _storage, _history);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  // ── Bootstrap ──────────────────────────────────────────────────────────────

  Future<void> _bootstrap() async {
    await _notifications.init();
    await _requestPermissions();

    // Start the foreground service early so that even if the user background
    // the app during the rest of bootstrap, the process stays alive.
    await ForegroundService.start();

    // One-time prompt to exempt from battery optimisation (Samsung / Xiaomi /
    // Huawei OEM battery savers can suspend foreground services without this).
    await ForegroundService.requestBatteryOptimizationExemption();

    final settings = await _storage.loadAutomationSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _bootstrapped = true;
    });

    // Keep the foreground notification in sync with connection state changes.
    _ble.addListener(_onBleStateChanged);

    _ble.onStatus = (status) {
      _notifications.handleBatteryLevel(status.batteryLevel);
      _automation.evaluate(_settings);
      _energyLog.recordSample(status);
      // Update notification text with live battery / wattage data.
      ForegroundService.updateStatus(connected: true, status: status);
    };

    await _history.init();
    await _energyLog.init();
    await _automation.init();
    await _ble.init();
  }

  // ── BLE state listener ─────────────────────────────────────────────────────

  /// Called by [BleService] (ChangeNotifier) on every state change:
  /// scanning start/stop, connect, disconnect, characteristic discovery…
  ///
  /// We use this to keep the foreground notification accurate even when
  /// no status packets are arriving (e.g. while scanning or disconnected).
  void _onBleStateChanged() {
    ForegroundService.updateStatus(
      connected: _ble.isConnected,
      status: _ble.isConnected ? _ble.status : null,
    );
  }

  // ── Permissions ────────────────────────────────────────────────────────────

  Future<void> _requestPermissions() async {
    final permissions = [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
      // POST_NOTIFICATIONS: required on Android 13+ for any notification
      // (including the foreground service notification).
      // Gracefully granted / ignored on older Android and iOS.
      if (Platform.isAndroid) Permission.notification,
    ];

    final statuses = await permissions.request();

    if (!mounted) return;
    setState(() {
      _permissionsPermanentlyDenied =
          statuses.values.any((s) => s.isPermanentlyDenied);
    });
  }

  // ── Settings ───────────────────────────────────────────────────────────────

  Future<void> _onSettingsChanged(AutomationSettings updated) async {
    setState(() => _settings = updated);
    await _storage.saveAutomationSettings(updated);
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    // Remove listener before disposing BLE service to avoid callbacks on a
    // dead widget. The foreground service itself is NOT stopped here — it
    // should continue running after the widget tree is torn down.
    _ble.removeListener(_onBleStateChanged);
    _ble.dispose();
    _history.dispose();
    _energyLog.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isIt = Localizations.localeOf(context).languageCode == 'it';
    final strings = AppStrings(isIt);

    if (!_bootstrapped) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.teal),
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          ControlTab(
            ble: _ble,
            strings: strings,
            permissionsPermanentlyDenied: _permissionsPermanentlyDenied,
          ),
          AutomationsTab(
            ble: _ble,
            strings: strings,
            settings: _settings,
            webhooks: _webhooks,
            tapo: _tapo,
            onSettingsChanged: _onSettingsChanged,
          ),
          EnergyTab(
            energyLog: _energyLog,
            strings: strings,
          ),
          HistoryTab(
            history: _history,
            strings: strings,
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border:
              Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) =>
              setState(() => _selectedIndex = i),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.bolt_outlined),
              selectedIcon: const Icon(Icons.bolt_rounded),
              label: strings.t('tab_control'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.auto_mode_outlined),
              selectedIcon: const Icon(Icons.auto_mode_rounded),
              label: strings.t('tab_automations'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.show_chart_outlined),
              selectedIcon: const Icon(Icons.show_chart_rounded),
              label: strings.t('tab_energy'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.history_outlined),
              selectedIcon: const Icon(Icons.history_rounded),
              label: strings.t('tab_history'),
            ),
          ],
        ),
      ),
    );
  }
}