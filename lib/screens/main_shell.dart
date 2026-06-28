import 'package:flutter/material.dart';

import '../app_coordinator.dart';
import '../l10n/app_strings.dart';
import '../models/mqtt_settings.dart';
import '../services/mqtt_service.dart';
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
  late final AppCoordinator _coordinator;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    AppTheme.applySystemOverlay();
    _coordinator = AppCoordinator();
    _coordinator.addListener(_onCoordinatorChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _coordinator.init());
  }

  @override
  void dispose() {
    _coordinator.removeListener(_onCoordinatorChanged);
    _coordinator.dispose();
    super.dispose();
  }

  void _onCoordinatorChanged() {
    // Clamp the tab index whenever the tab count changes (e.g. mode switch).
    final maxIndex = _coordinator.tabCount - 1;
    if (_selectedIndex > maxIndex) {
      setState(() => _selectedIndex = 0);
    } else {
      setState(() {});
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_coordinator.isBootstrapped) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    final isIt    = Localizations.localeOf(context).languageCode == 'it';
    final strings = AppStrings(isIt);
    final c       = _coordinator;
    final isClientMode = c.mqttSettings.mode == AppMode.client;

    // ── Tab screens ────────────────────────────────────────────────────────

    final controlTab = isClientMode
        ? MqttClientTab(mqtt: c.mqtt, strings: strings)
        : ControlTab(
            ble: c.ble,
            strings: strings,
            permissionsPermanentlyDenied: c.permissionsPermanentlyDenied,
          );

    final devicesTab = isClientMode
        ? DevicesTab(
            tapoDevices: c.tapoDevices,
            tapo: c.tapo,
            strings: strings,
            mqttClient: c.mqtt,
          )
        : DevicesTab(
            tapoDevices: c.tapoDevices,
            tapo: c.tapo,
            strings: strings,
          );

    final automationsTab = AutomationsTab(
      flows:          c.flows,
      settings:       c.settings,
      strings:        strings,
      tapoDevices:    c.tapoDevices.devices,
      history:        c.history,
      onFlowsChanged: c.onFlowsChanged,
      isClientMode:   isClientMode,
    );

    final settingsTab = SettingsTab(
      settings:              c.settings,
      mqttSettings:          c.mqttSettings,
      mqtt:                  c.mqtt,
      strings:               strings,
      onSettingsChanged:     c.onSettingsChanged,
      onMqttSettingsChanged: c.onMqttSettingsChanged,
    );

    // ── Navigation ─────────────────────────────────────────────────────────

    final List<Widget> tabScreens;
    final List<NavigationDestination> destinations;

    if (isClientMode) {
      tabScreens = [controlTab, devicesTab, automationsTab, settingsTab];
      destinations = [
        NavigationDestination(
          icon: const Icon(Icons.cloud_outlined),
          selectedIcon: const Icon(Icons.cloud_rounded),
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
        EnergyTab(energyLog: c.energyLog, strings: strings),
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
            if (c.mqttSettings.mode != AppMode.standalone)
              _MqttModeStrip(mqtt: c.mqtt, mode: c.mqttSettings.mode),
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