import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/app_strings.dart';
import '../models/automation_flow.dart';
import '../models/automation_settings.dart';
import '../models/mqtt_settings.dart';
import '../services/ble_service.dart';
import '../services/energy_log_service.dart';
import '../services/flow_engine.dart';
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
import 'settings_tab.dart';

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

  late final HistoryService _history;
  late final EnergyLogService _energyLog;
  late final BleService _ble;
  late final FlowEngine _flowEngine;

  // ── MQTT publish throttling ────────────────────────────────────────────────
  DateTime? _lastMqttPublishTime;
  bool? _lastAcState;
  bool? _lastDcState;
  bool? _lastUsbState;

  // ── State ──────────────────────────────────────────────────────────────────
  AutomationSettings _settings = const AutomationSettings();
  MqttSettings _mqttSettings = const MqttSettings();
  List<AutomationFlow> _flows = [];
  bool _permissionsPermanentlyDenied = false;
  int _selectedIndex = 0;
  bool _bootstrapped = false;

  /// Prevents re-publishing flows that were just received from MQTT,
  /// which would create an unnecessary echo on the broker.
  bool _applyingRemoteFlows = false;

  @override
  void initState() {
    super.initState();
    // Enforce Android 16 transparent edge-to-edge style on entry
    AppTheme.applySystemOverlay();
    
    _history = HistoryService(_storage);
    _energyLog = EnergyLogService(_storage);
    _ble = BleService(_storage);
    _flowEngine = FlowEngine(_ble, _webhooks, _tapo, _history, _storage);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  // ── Bootstrap ──────────────────────────────────────────────────────────────

  Future<void> _bootstrap() async {
    await _notifications.init();
    await _requestPermissions();

    final results = await Future.wait([
      _storage.loadAutomationSettings(),
      _storage.loadMqttSettings(),
      _storage.loadFlows(),
    ]);
    final autoSettings = results[0] as AutomationSettings;
    final mqttSettings = results[1] as MqttSettings;
    final flows = results[2] as List<AutomationFlow>;

    if (!mounted) return;
    setState(() {
      _settings = autoSettings;
      _mqttSettings = mqttSettings;
      _flows = flows;
      _bootstrapped = true;
    });

    _ble.addListener(_onBleStateChanged);
    _ble.onStatus = _onBleStatus;

    await _history.init();
    await _energyLog.init();
    await _flowEngine.init(flows);
    await _ble.init();

    _mqtt.onCommand = _onMqttCommand;
    _mqtt.onFlowsReceived = _onMqttFlowsReceived;
    await _mqtt.configure(mqttSettings);

    // Foreground service only needed when this device owns the BLE connection.
    // In client mode the app is an MQTT consumer only.
    if (mqttSettings.mode != AppMode.client) {
      await ForegroundService.start();
      await ForegroundService.requestBatteryOptimizationExemption();
    }
  }

  // ── BLE callbacks ──────────────────────────────────────────────────────────

  void _onBleStatus(status) {
    _notifications.handleBatteryLevel(status.batteryLevel);
    // Flows only execute on the device that holds the BLE connection.
    if (_mqttSettings.mode != AppMode.client) {
      _flowEngine.evaluate(_flows, _settings);
    }
    _energyLog.recordSample(status);
    ForegroundService.updateStatus(connected: true, status: status);

    if (_mqttSettings.mode == AppMode.gateway) {
      final now = DateTime.now();
      final stateChanged = _lastAcState == null ||
          status.isAcOn != _lastAcState ||
          status.isDcOn != _lastDcState ||
          status.isUsbOn != _lastUsbState;

      if (stateChanged ||
          _lastMqttPublishTime == null ||
          now.difference(_lastMqttPublishTime!).inSeconds >= 5) {
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

  // ── MQTT callbacks ─────────────────────────────────────────────────────────

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
    }
  }

  /// Incoming flows from the other device. Apply locally without
  /// re-broadcasting.
  Future<void> _onMqttFlowsReceived(List<AutomationFlow> flows) async {
    if (!mounted) return;
    _applyingRemoteFlows = true;
    try {
      await _applyFlows(flows);
    } finally {
      _applyingRemoteFlows = false;
    }
  }

  // ── Settings callbacks ─────────────────────────────────────────────────────

  Future<void> _onSettingsChanged(AutomationSettings updated) async {
    setState(() => _settings = updated);
    await _storage.saveAutomationSettings(updated);
  }

  Future<void> _onMqttSettingsChanged(MqttSettings updated) async {
    final wasClient = _mqttSettings.mode == AppMode.client;
    final nowClient = updated.mode == AppMode.client;

    setState(() {
      _mqttSettings = updated;
      // Clamp selected tab index when the tab count changes.
      final maxIndex = nowClient ? 2 : 4;
      if (_selectedIndex > maxIndex) _selectedIndex = 0;
    });

    await _storage.saveMqttSettings(updated);
    await _mqtt.configure(updated);

    if (!wasClient && nowClient) {
      // No longer holding the BLE connection — stop the foreground service.
      await ForegroundService.stop();
    } else if (wasClient && !nowClient) {
      // Now holding the BLE connection — start the foreground service.
      await ForegroundService.start();
      await ForegroundService.requestBatteryOptimizationExemption();
    }
  }

  Future<void> _onFlowsChanged(List<AutomationFlow> updated) async {
    await _applyFlows(updated);

    // Publish to MQTT so the other device gets the update.
    if (!_applyingRemoteFlows &&
        _mqttSettings.mode != AppMode.standalone) {
      _mqtt.publishFlows(updated);
    }
  }

  /// Shared logic for both local edits and remote MQTT updates.
  Future<void> _applyFlows(List<AutomationFlow> updated) async {
    // Tell the engine about deletions.
    final deletedIds = _flows
        .map((f) => f.id)
        .toSet()
        .difference(updated.map((f) => f.id).toSet());
    for (final id in deletedIds) {
      await _flowEngine.onFlowDeleted(id);
    }

    // Initialise trigger state for newly added flows.
    final addedIds = updated
        .map((f) => f.id)
        .toSet()
        .difference(_flows.map((f) => f.id).toSet());
    for (final flow in updated.where((f) => addedIds.contains(f.id))) {
      await _flowEngine.init([flow]);
    }

    if (!mounted) return;
    setState(() => _flows = updated);
    await _storage.saveFlows(updated);
  }

  // ── Permissions ────────────────────────────────────────────────────────────

  Future<void> _requestPermissions() async {
    final permissions = [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
      if (Platform.isAndroid) ...[
        Permission.notification,
      ],
    ];
    final statuses = await permissions.request();
    if (!mounted) return;
    setState(() {
      _permissionsPermanentlyDenied =
          statuses.values.any((s) => s.isPermanentlyDenied);
    });
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
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
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

    final automationsTab = AutomationsTab(
      flows: _flows,
      settings: _settings,
      strings: strings,
      onFlowsChanged: _onFlowsChanged,
      isClientMode: isClientMode,
    );

    final settingsTab = SettingsTab(
      settings: _settings,
      mqttSettings: _mqttSettings,
      mqtt: _mqtt,
      tapo: _tapo,
      strings: strings,
      onSettingsChanged: _onSettingsChanged,
      onMqttSettingsChanged: _onMqttSettingsChanged,
    );

    final List<Widget> tabScreens;
    final List<NavigationDestination> destinations;

    if (isClientMode) {
      tabScreens = [controlTab, automationsTab, settingsTab];
      destinations = [
        NavigationDestination(
          icon: const Icon(Icons.cloud_outlined),
          selectedIcon: const Icon(Icons.cloud_rounded),
          label: strings.t('tab_control'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.auto_mode_outlined),
          selectedIcon: const Icon(Icons.auto_mode_rounded),
          label: strings.t('tab_automations'),
        ),
        const NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings_rounded),
          label: 'Settings',
        ),
      ];
    } else {
      tabScreens = [
        controlTab,
        automationsTab,
        EnergyTab(energyLog: _energyLog, strings: strings),
        HistoryTab(history: _history, strings: strings),
        settingsTab,
      ];
      destinations = [
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
        const NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings_rounded),
          label: 'Settings',
        ),
      ];
    }

    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: tabScreens),
      bottomNavigationBar: Container(
        // Integrates with edge-to-edge transparent system navigation bar colors
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_mqttSettings.mode != AppMode.standalone)
              _MqttModeStrip(mqtt: _mqtt, mode: _mqttSettings.mode),
            Container(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant, 
                    width: 1,
                  ),
                ),
              ),
              child: NavigationBar(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (i) =>
                    setState(() => _selectedIndex = i),
                destinations: destinations,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── MQTT mode strip ───────────────────────────────────────────────────────────

class _MqttModeStrip extends StatelessWidget {
  const _MqttModeStrip({required this.mqtt, required this.mode});

  final MqttService mqtt;
  final AppMode mode;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: mqtt,
      builder: (context, __) {
        final (bgColor, fgColor, icon, label) = _resolve();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, 
            vertical: 6,
          ),
          color: bgColor,
          child: Row(
            children: [
              Icon(icon, size: 12, color: fgColor),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: AppTypography.labelSm.copyWith(
                  color: fgColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  (Color bg, Color fg, IconData icon, String label) _resolve() {
    final tag = mode == AppMode.gateway ? 'GATEWAY' : 'CLIENT';
    if (mqtt.isConnecting) {
      return (
        AppColors.warningSurface, 
        AppColors.warning,
        Icons.pending_rounded, 
        '$tag · Connecting…'
      );
    }
    if (mqtt.isConnected) {
      return (
        AppColors.successSurface, 
        AppColors.success,
        Icons.cloud_done_rounded, 
        '$tag · MQTT connected'
      );
    }
    return (
      AppColors.errorSurface, 
      AppColors.error,
      Icons.cloud_off_rounded, 
      '$tag · MQTT disconnected — check Settings'
    );
  }
}