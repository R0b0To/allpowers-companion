import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/app_strings.dart';
import '../models/automation_settings.dart';
import '../services/automation_engine.dart';
import '../services/ble_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/webhook_service.dart';
import 'control_tab.dart';
import 'automations_tab.dart';

/// Root shell: owns every service singleton and hosts the bottom nav.
/// Neither tab creates services — they receive what they need, keeping
/// them easy to extend or test independently.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final _storage = StorageService();
  final _notifications = NotificationService();
  final _webhooks = WebhookService();
  late final BleService _ble = BleService(_storage);
  late final AutomationEngine _automation =
      AutomationEngine(_ble, _webhooks, _storage);

  AutomationSettings _settings = const AutomationSettings();
  bool _permissionsPermanentlyDenied = false;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _ble.onStatus = (status) {
      _notifications.handleBatteryLevel(status.batteryLevel);
      _automation.evaluate(_settings);
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    await _notifications.init();
    await _requestPermissions();

    final settings = await _storage.loadAutomationSettings();
    if (!mounted) return;
    setState(() => _settings = settings);

    await _automation.init();
    await _ble.init();
  }

  Future<void> _requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (mounted) {
      setState(() => _permissionsPermanentlyDenied =
          statuses.values.any((s) => s.isPermanentlyDenied));
    }
  }

  Future<void> _persistSettings(AutomationSettings settings) async {
    setState(() => _settings = settings);
    await _storage.saveAutomationSettings(settings);
  }

  @override
  void dispose() {
    _ble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIt = Localizations.localeOf(context).languageCode == 'it';
    final strings = AppStrings(isIt);

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
            onSettingsChanged: _persistSettings,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.bolt_outlined),
            selectedIcon: const Icon(Icons.bolt),
            label: strings.t('tab_control'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.sync_alt_outlined),
            selectedIcon: const Icon(Icons.sync_alt),
            label: strings.t('tab_automations'),
          ),
        ],
      ),
    );
  }
}