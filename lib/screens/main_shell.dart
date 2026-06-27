import 'dart:async';
import 'dart:io';
import 'package:ap_companion/models/power_station_status.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/app_strings.dart';
import '../models/automation_flow.dart';
import '../models/automation_history_entry.dart';
import '../models/automation_settings.dart';
import '../models/mqtt_settings.dart';
import '../repositories/app_repositories.dart';
import '../services/ble_service.dart';
import '../services/energy_log_service.dart';
import '../services/flow_engine.dart';
import '../services/foreground_service.dart';
import '../services/history_service.dart';
import '../services/mqtt_service.dart';
import '../services/notification_service.dart';
import '../services/tapo_device_service.dart';
import '../services/tapo_service.dart';
import '../services/webhook_service.dart';
import '../theme/app_theme.dart';
import 'automations_tab.dart';
import 'control_tab.dart';
import 'devices_tab.dart';
import 'energy_tab.dart';
import 'mqtt_client_tab.dart';
import 'settings_tab.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // ── Repository layer ───────────────────────────────────────────────────────
  /// Single composition root. Each service receives only its specific
  /// repository interface, keeping all services independently unit-testable.
  final _repos = AppRepositories();

  // ── Services ───────────────────────────────────────────────────────────────
  final _notifications = NotificationService();
  final _webhooks      = WebhookService();
  final _tapo          = TapoService();
  final _mqtt          = MqttService();

  late final HistoryService     _history;
  late final EnergyLogService   _energyLog;
  late final BleService         _ble;
  late final TapoDeviceService  _tapoDevices;
  late final FlowEngine         _flowEngine;

  // ── MQTT publish throttling ────────────────────────────────────────────────
  DateTime? _lastMqttPublishTime;
  bool? _lastAcState;
  bool? _lastDcState;
  bool? _lastUsbState;

  // ── MQTT gateway history sync ──────────────────────────────────────────────
  int _lastKnownHistoryCount = 0;

  // ── State ──────────────────────────────────────────────────────────────────
  AutomationSettings _settings    = const AutomationSettings();
  MqttSettings       _mqttSettings = const MqttSettings();
  List<AutomationFlow> _flows     = [];
  bool _permissionsPermanentlyDenied = false;
  int  _selectedIndex = 0;
  bool _bootstrapped  = false;
  bool _applyingRemoteFlows = false;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay();

    // Each service receives only the repository interface it needs.
    _history     = HistoryService(_repos.history);
    _energyLog   = EnergyLogService(_repos.energyLog);
    _ble         = BleService(_repos.ble);
    _tapoDevices = TapoDeviceService(_tapo, _repos.tapo);
    _flowEngine  = FlowEngine(
      _ble, _webhooks, _tapo, _tapoDevices, _history, _repos.flows,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  // ── Bootstrap ──────────────────────────────────────────────────────────────

  Future<void> _bootstrap() async {
    await _notifications.init();
    if (!mounted) return;

    await _requestPermissions();
    if (!mounted) return;

    // All three repository reads run in parallel — they share the same
    // SharedPreferencesSource so only one native getInstance() call is made.
    final results = await Future.wait([
      _repos.automationSettings.load(),
      _repos.mqttSettings.load(),
      _repos.flows.loadFlows(),
    ]);
    if (!mounted) return;

    final autoSettings = results[0] as AutomationSettings;
    final mqttSettings = results[1] as MqttSettings;
    final flows        = results[2] as List<AutomationFlow>;

    setState(() {
      _settings     = autoSettings;
      _mqttSettings = mqttSettings;
      _flows        = flows;
      _bootstrapped = true;
    });

    _ble.addListener(_onBleStateChanged);
    _ble.onStatus = _onBleStatus;

    await _history.init();
    if (!mounted) return;

    _lastKnownHistoryCount = _history.entries.length;
    _history.addListener(_onHistoryChanged);

    await _energyLog.init();
    await _tapoDevices.init();
    if (!mounted) return;

    await _flowEngine.init(flows);
    await _ble.init();
    if (!mounted) return;

    _tapoDevices.addListener(_onTapoDevicesChanged);

    _mqtt.onCommand         = _onMqttCommand;
    _mqtt.onFlowsReceived   = _onMqttFlowsReceived;
    _mqtt.onHistoryReceived = _onMqttHistoryReceived;
    await _mqtt.configure(mqttSettings);
    if (!mounted) return;

    if (mqttSettings.mode != AppMode.client) {
      await ForegroundService.start();
      await ForegroundService.requestBatteryOptimizationExemption();
    }
  }

  // ── BLE callbacks ──────────────────────────────────────────────────────────

  void _onBleStatus(PowerStationStatus status) {
    _notifications.handleBatteryLevel(status.batteryLevel);
    if (_mqttSettings.mode != AppMode.client) {
      _flowEngine.evaluate(_flows, _settings);
    }
    _energyLog.recordSample(status);
    ForegroundService.updateStatus(connected: true, status: status);

    if (_mqttSettings.mode == AppMode.gateway) {
      final now = DateTime.now();
      final stateChanged = _lastAcState == null ||
          status.isAcOn  != _lastAcState ||
          status.isDcOn  != _lastDcState ||
          status.isUsbOn != _lastUsbState;

      if (stateChanged ||
          _lastMqttPublishTime == null ||
          now.difference(_lastMqttPublishTime!).inSeconds >= 5) {
        _mqtt.publishStatus(status, bleConnected: true);
        _lastMqttPublishTime = now;
        _lastAcState  = status.isAcOn;
        _lastDcState  = status.isDcOn;
        _lastUsbState = status.isUsbOn;
      }
    }
  }

  void _onBleStateChanged() {
    ForegroundService.updateStatus(
      connected: _ble.isConnected,
      status:    _ble.isConnected ? _ble.status : null,
    );
    if (!_ble.isConnected && _mqttSettings.mode == AppMode.gateway) {
      _mqtt.publishStatus(_ble.status, bleConnected: false);
    }
  }

  // ── History listener (gateway MQTT publish) ────────────────────────────────

  void _onHistoryChanged() {
    if (_mqttSettings.mode != AppMode.gateway) return;
    final entries = _history.entries;
    if (entries.length > _lastKnownHistoryCount && entries.isNotEmpty) {
      _mqtt.publishHistoryEntry(entries.first);
      _mqtt.publishHistorySnapshot(entries);
    }
    _lastKnownHistoryCount = entries.length;
  }

  // ── Tapo polling callback ──────────────────────────────────────────────────

  void _onTapoDevicesChanged() {
    if (_mqttSettings.mode != AppMode.client) {
      _flowEngine.evaluateTapoTriggers(_flows, _settings);
    }
  }

  // ── MQTT callbacks ─────────────────────────────────────────────────────────

  void _onMqttCommand(String outlet, bool value) {
    if (_mqttSettings.mode != AppMode.gateway) return;
    if (!_ble.isConnected) return;
    switch (outlet) {
      case 'usb': _ble.setUsb(value);
      case 'ac':  _ble.setAc(value);
      case 'dc':  _ble.setDc(value);
    }
  }

  Future<void> _onMqttFlowsReceived(List<AutomationFlow> flows) async {
    if (!mounted || _applyingRemoteFlows) return;
    _applyingRemoteFlows = true;
    try {
      await _applyFlows(flows);
    } finally {
      _applyingRemoteFlows = false;
    }
  }

  Future<void> _onMqttHistoryReceived(
      List<AutomationHistoryEntry> entries) async {
    if (!mounted) return;
    if (_mqttSettings.mode != AppMode.client) return;
    if (entries.length == 1) {
      await _history.addEntry(entries.first);
    } else {
      await _history.replaceAll(entries);
    }
  }

  // ── Settings callbacks ─────────────────────────────────────────────────────

  Future<void> _onSettingsChanged(AutomationSettings updated) async {
    setState(() => _settings = updated);
    await _repos.automationSettings.save(updated);
  }

  Future<void> _onMqttSettingsChanged(MqttSettings updated) async {
    final wasClient = _mqttSettings.mode == AppMode.client;
    final nowClient = updated.mode    == AppMode.client;

    setState(() {
      _mqttSettings = updated;
      final maxIndex = _tabCount(nowClient) - 1;
      if (_selectedIndex > maxIndex) _selectedIndex = 0;
    });

    await _repos.mqttSettings.save(updated);
    await _mqtt.configure(updated);

    if (!wasClient && nowClient) {
      await ForegroundService.stop();
    } else if (wasClient && !nowClient) {
      await ForegroundService.start();
      await ForegroundService.requestBatteryOptimizationExemption();
    }
  }

  Future<void> _onFlowsChanged(List<AutomationFlow> updated) async {
    await _applyFlows(updated);
    if (!_applyingRemoteFlows && _mqttSettings.mode != AppMode.standalone) {
      _mqtt.publishFlows(updated);
    }
  }

  Future<void> _applyFlows(List<AutomationFlow> updated) async {
    final deletedIds = _flows
        .map((f) => f.id)
        .toSet()
        .difference(updated.map((f) => f.id).toSet());
    for (final id in deletedIds) {
      await _flowEngine.onFlowDeleted(id);
    }

    final addedIds = updated
        .map((f) => f.id)
        .toSet()
        .difference(_flows.map((f) => f.id).toSet());
    for (final flow in updated.where((f) => addedIds.contains(f.id))) {
      await _flowEngine.init([flow]);
    }

    if (!mounted) return;
    setState(() => _flows = updated);
    await _repos.flows.saveFlows(updated);
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

  // ── Helpers ────────────────────────────────────────────────────────────────

  int _tabCount(bool isClientMode) => isClientMode ? 3 : 5;

  // ── Dispose ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _history.removeListener(_onHistoryChanged);
    _tapoDevices.removeListener(_onTapoDevicesChanged);
    _ble.removeListener(_onBleStateChanged);

    _ble.onStatus           = null;
    _mqtt.onCommand         = null;
    _mqtt.onFlowsReceived   = null;
    _mqtt.onHistoryReceived = null;

    _ble.dispose();
    _history.dispose();
    _energyLog.dispose();
    _tapoDevices.dispose();
    _tapo.dispose();
    _mqtt.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isIt     = Localizations.localeOf(context).languageCode == 'it';
    final strings  = AppStrings(isIt);

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

    // ── Tab screens ────────────────────────────────────────────────────────
    final controlTab = isClientMode
        ? MqttClientTab(mqtt: _mqtt, strings: strings)
        : ControlTab(
            ble: _ble,
            strings: strings,
            permissionsPermanentlyDenied: _permissionsPermanentlyDenied,
          );

    final automationsTab = AutomationsTab(
      flows:          _flows,
      settings:       _settings,
      strings:        strings,
      tapoDevices:    _tapoDevices.devices,
      history:        _history,
      onFlowsChanged: _onFlowsChanged,
      isClientMode:   isClientMode,
    );

    final settingsTab = SettingsTab(
      settings:               _settings,
      mqttSettings:           _mqttSettings,
      mqtt:                   _mqtt,
      strings:                strings,
      onSettingsChanged:      _onSettingsChanged,
      onMqttSettingsChanged:  _onMqttSettingsChanged,
    );

    final devicesTab = DevicesTab(
      tapoDevices: _tapoDevices,
      tapo:        _tapo,
      strings:     strings,
    );

    // ── Navigation ─────────────────────────────────────────────────────────
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
        devicesTab,
        automationsTab,
        EnergyTab(energyLog: _energyLog, strings: strings),
        settingsTab,
      ];
      destinations = [
        NavigationDestination(
          icon: const Icon(Icons.bolt_outlined),
          selectedIcon: const Icon(Icons.bolt_rounded),
          label: strings.t('tab_control'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.power_outlined),
          selectedIcon: const Icon(Icons.power_rounded),
          label: strings.t('tab_devices'),
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
        const NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings_rounded),
          label: 'Settings',
        ),
      ];
    }

    final safeIndex = _selectedIndex.clamp(0, tabScreens.length - 1);

    return Scaffold(
      body: IndexedStack(index: safeIndex, children: tabScreens),
      bottomNavigationBar: Container(
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
                selectedIndex: safeIndex,
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
  final AppMode     mode;

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

  (Color, Color, IconData, String) _resolve() {
    final tag = mode == AppMode.gateway ? 'GATEWAY' : 'CLIENT';
    if (mqtt.isConnecting) {
      return (AppColors.warningSurface, AppColors.warning,
          Icons.pending_rounded, '$tag · Connecting…');
    }
    if (mqtt.isConnected) {
      return (AppColors.successSurface, AppColors.success,
          Icons.cloud_done_rounded, '$tag · MQTT connected');
    }
    return (AppColors.errorSurface, AppColors.error,
        Icons.cloud_off_rounded, '$tag · MQTT disconnected — check Settings');
  }
}