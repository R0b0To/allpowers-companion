import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/app_strings.dart';
import '../models/automation_settings.dart';
import '../services/automation_engine.dart';
import '../services/ble_service.dart';
import '../services/energy_log_service.dart';
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
/// Neither tab constructs services — they receive them as constructor
/// parameters, keeping tabs independently testable and free of hidden
/// dependencies.
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

    _ble.onStatus = (status) {
      _notifications.handleBatteryLevel(status.batteryLevel);
      _automation.evaluate(_settings);
      _energyLog.recordSample(status);
    };

    // Defer bootstrap until the first frame so the widget tree is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    await _notifications.init();
    await _requestPermissions();

    final settings = await _storage.loadAutomationSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _bootstrapped = true;
    });

    await _history.init();
    await _energyLog.init();
    await _automation.init();
    await _ble.init();
  }

  Future<void> _requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (!mounted) return;
    setState(() {
      _permissionsPermanentlyDenied =
          statuses.values.any((s) => s.isPermanentlyDenied);
    });
  }

  Future<void> _onSettingsChanged(AutomationSettings updated) async {
    setState(() => _settings = updated);
    await _storage.saveAutomationSettings(updated);
  }

  @override
  void dispose() {
    _ble.dispose();
    _history.dispose();
    _energyLog.dispose();
    super.dispose();
  }

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
          border: Border(top: BorderSide(color: AppColors.border, width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) => setState(() => _selectedIndex = i),
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