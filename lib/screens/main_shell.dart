import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/app_strings.dart';
import '../models/automation_settings.dart';
import '../models/mqtt_settings.dart';
import '../services/automation_engine.dart';
import '../services/ble_service.dart';
import '../services/energy_log_service.dart';
import '../services/foreground_service.dart';
import '../services/history_service.dart';
import '../services/mqtt_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/tapo_service.dart';
import '../services/webhook_service.dart';
import '../theme/app_theme.dart';
import 'automations_tab.dart';
import 'control_tab.dart';
import 'energy_tab.dart';
import 'history_tab.dart';
import 'mqtt_client_tab.dart';
import 'settings_tab.dart'; // Import your new settings tab

/// Root shell: owns all service singletons and hosts the bottom navigation.
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
  final _mqtt = MqttService();

  // ── Throttling states ──────────────────────────────────────────────────────
  DateTime? _lastMqttPublishTime;
  bool? _lastAcState;
  bool? _lastDcState;
  bool? _lastUsbState;

  late final HistoryService _history = HistoryService(_storage);
  late final EnergyLogService _energyLog = EnergyLogService(_storage);
  late final BleService _ble;
  late final AutomationEngine _automation;

  // ── UI / settings state ────────────────────────────────────────────────────
  AutomationSettings _settings = const AutomationSettings();
  MqttSettings _mqttSettings = const MqttSettings();
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

    await ForegroundService.start();
    await ForegroundService.requestBatteryOptimizationExemption();

    // Load both settings bundles in parallel.
    final results = await Future.wait([
      _storage.loadAutomationSettings(),
      _storage.loadMqttSettings(),
    ]);
    final autoSettings = results[0] as AutomationSettings;
    final mqttSettings = results[1] as MqttSettings;

    if (!mounted) return;
    setState(() {
      _settings = autoSettings;
      _mqttSettings = mqttSettings;
      _bootstrapped = true;
    });

    _ble.addListener(_onBleStateChanged);
    _ble.onStatus = _onBleStatus;

    await _history.init();
    await _energyLog.init();
    await _automation.init();
    await _ble.init();

    _mqtt.onCommand = _onMqttCommand;
    _mqtt.onConfigReceived = _onMqttConfigReceived;

    await _mqtt.configure(mqttSettings);
  }

  /// Called on every decoded BLE status packet.
  void _onBleStatus(status) {
    _notifications.handleBatteryLevel(status.batteryLevel);
    _automation.evaluate(_settings);
    _energyLog.recordSample(status);
    ForegroundService.updateStatus(connected: true, status: status);

    // Forward to MQTT broker when acting as gateway.
    if (_mqttSettings.mode == AppMode.gateway) {
      final now = DateTime.now();
      final lastPublish = _lastMqttPublishTime;

      // Detect if an outlet state changed (forces an immediate bypass)
      final stateChanged = _lastAcState == null ||
          status.isAcOn != _lastAcState ||
          status.isDcOn != _lastDcState ||
          status.isUsbOn != _lastUsbState;

      // Publish instantly on state changes, otherwise throttle standard telemetry to 5-second intervals
      if (stateChanged || lastPublish == null || now.difference(lastPublish).inSeconds >= 5) {
        _mqtt.publishStatus(status, bleConnected: true);
        _lastMqttPublishTime = now;
        _lastAcState = status.isAcOn;
        _lastDcState = status.isDcOn;
        _lastUsbState = status.isUsbOn;
      }
    }
  }

  void _onBleStateChanged() {
    ForegroundService.updateStatus(
      connected: _ble.isConnected,
      status: _ble.isConnected ? _ble.status : null,
    );

    if (!_ble.isConnected && _mqttSettings.mode == AppMode.gateway) {
      _mqtt.publishStatus(_ble.status, bleConnected: false);
    }
  }

  // ── MQTT Command Routing ───────────────────────────────────────────────────

  void _onMqttCommand(String outlet, bool value) {
    if (_mqttSettings.mode != AppMode.gateway) return;
    if (!_ble.isConnected) return;

    switch (outlet) {
      case 'usb':
        _ble.setUsb(value);
      case 'ac':
        _ble.setAc(value);
      case 'dc':
        _ble.setDc(value);
      default:
        break;
    }
  }

  // ── MQTT Config Syncing ────────────────────────────────────────────────────

  void _onMqttConfigReceived(AutomationSettings updated) {
    if (_mqttSettings.mode != AppMode.gateway) return;
    
    setState(() {
      _settings = updated;
    });
    _storage.saveAutomationSettings(updated);
  }

  // ── Permissions ────────────────────────────────────────────────────────────

  Future<void> _requestPermissions() async {
    final permissions = [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
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

    if (_mqttSettings.mode == AppMode.client) {
      _mqtt.publishAutomationConfig(updated);
    }
  }

  Future<void> _onMqttSettingsChanged(MqttSettings updated) async {
    setState(() => _mqttSettings = updated);
    await _storage.saveMqttSettings(updated);
    await _mqtt.configure(updated);
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _ble.removeListener(_onBleStateChanged);
    _ble.dispose();
    _history.dispose();
    _energyLog.dispose();
    _mqtt.dispose();
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

    final isClientMode = _mqttSettings.mode == AppMode.client;

    final controlTab = isClientMode
        ? MqttClientTab(mqtt: _mqtt, strings: strings)
        : ControlTab(
            ble: _ble,
            strings: strings,
            permissionsPermanentlyDenied: _permissionsPermanentlyDenied,
          );

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          controlTab,
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
          SettingsTab(
            settings: _settings,
            mqttSettings: _mqttSettings,
            mqtt: _mqtt,
            tapo: _tapo,
            strings: strings,
            onSettingsChanged: _onSettingsChanged,
            onMqttSettingsChanged: _onMqttSettingsChanged,
          ), // Added the 5th Settings Tab
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_mqttSettings.mode != AppMode.standalone)
            _MqttModeStrip(mqtt: _mqtt, mode: _mqttSettings.mode),
          Container(
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border, width: 1)),
            ),
            child: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (i) =>
                  setState(() => _selectedIndex = i),
              destinations: [
                NavigationDestination(
                  icon: isClientMode
                      ? const Icon(Icons.cloud_outlined)
                      : const Icon(Icons.bolt_outlined),
                  selectedIcon: isClientMode
                      ? const Icon(Icons.cloud_rounded)
                      : const Icon(Icons.bolt_rounded),
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
                NavigationDestination(
                  icon: const Icon(Icons.settings_outlined),
                  selectedIcon: const Icon(Icons.settings_rounded),
                  label: strings.t('Settings') ?? 'Settings',
                ), // Added the 5th Navigation Destination
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MqttModeStrip extends StatelessWidget {
  const _MqttModeStrip({required this.mqtt, required this.mode});

  final MqttService mqtt;
  final AppMode mode;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: mqtt,
      builder: (_, __) {
        final (bgColor, fgColor, icon, label) = _resolve();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: 5),
          color: bgColor,
          child: Row(
            children: [
              Icon(icon, size: 12, color: fgColor),
              const SizedBox(width: AppSpacing.xs),
              Text(label,
                  style: AppTypography.labelSm.copyWith(color: fgColor)),
            ],
          ),
        );
      },
    );
  }

  (Color bg, Color fg, IconData icon, String label) _resolve() {
    final modeTag = mode == AppMode.gateway ? 'GATEWAY' : 'CLIENT';

    if (mqtt.isConnecting) {
      return (
        AppColors.warningSurface,
        AppColors.warning,
        Icons.pending_rounded,
        '$modeTag · Connecting…',
      );
    }
    if (mqtt.isConnected) {
      return (
        AppColors.successSurface,
        AppColors.success,
        Icons.cloud_done_rounded,
        '$modeTag · MQTT connected',
      );
    }
    return (
      AppColors.errorSurface,
      AppColors.error,
      Icons.cloud_off_rounded,
      '$modeTag · MQTT disconnected — check Settings tab', // Updated message to refer to the Settings Tab
    );
  }
}