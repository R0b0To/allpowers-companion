import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/power_station_status.dart';
import '../services/mqtt_service.dart';
import '../theme/app_theme.dart';
import '../widgets/metric_card.dart';
import '../widgets/toggle_card.dart';

/// Control screen shown when the app is running in [AppMode.client].
///
/// All data comes from the MQTT broker (via [MqttService.remoteStatus]) rather
/// than a direct BLE connection. Outlet-toggle taps publish MQTT commands
/// which the gateway executes over BLE.
///
/// The three nested states mirror [ControlTab]'s pattern:
/// - MQTT not connected → [_MqttOfflineView]
/// - MQTT connected but gateway's BLE is down → [_GatewayOfflineView]
/// - Fully operational → [_RemoteStationView]
class MqttClientTab extends StatelessWidget {
  const MqttClientTab({
    super.key,
    required this.mqtt,
    required this.strings,
  });

  final MqttService mqtt;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: mqtt,
      builder: (context, _) => SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (mqtt.isConnecting) {
      return _MqttConnectingView(strings: strings);
    }
    if (!mqtt.isConnected) {
      return _MqttOfflineView(mqtt: mqtt, strings: strings);
    }
    if (!mqtt.bleConnectedRemote) {
      return _GatewayOfflineView(mqtt: mqtt, strings: strings);
    }
    return _RemoteStationView(mqtt: mqtt, strings: strings);
  }
}

// ── Connecting ────────────────────────────────────────────────────────────────

class _MqttConnectingView extends StatelessWidget {
  const _MqttConnectingView({required this.strings});
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 3, 
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              strings.t('mqtt_connecting'),
              style: AppTypography.headingMd, 
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── MQTT Offline ──────────────────────────────────────────────────────────────

class _MqttOfflineView extends StatelessWidget {
  const _MqttOfflineView({required this.mqtt, required this.strings});
  final MqttService mqtt;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 40, 
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              strings.t('mqtt_broker_offline'),
              style: AppTypography.headingLg, 
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              mqtt.lastError ?? strings.t('mqtt_check_settings'),
              style: AppTypography.bodyMd,
              textAlign: TextAlign.center,
            ),
            if (mqtt.lastError != null) ...[
              const SizedBox(height: AppSpacing.xl),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: AppRadius.mdBR,
                  border: Border.all(
                    color: theme.colorScheme.error.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 16, 
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        mqtt.lastError!,
                        style: AppTypography.bodySm.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            Text(
              strings.t('mqtt_configure_hint'),
              style: AppTypography.labelSm, 
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Gateway BLE Offline ───────────────────────────────────────────────────────

class _GatewayOfflineView extends StatelessWidget {
  const _GatewayOfflineView({required this.mqtt, required this.strings});
  final MqttService mqtt;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // MQTT connected badge using theme status mappings
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, 
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.successSurface,
                borderRadius: AppRadius.xsBR,
                border: Border.all(
                  color: AppColors.success.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    strings.t('mqtt_connected'),
                    style: AppTypography.labelSm.copyWith(
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.bluetooth_disabled_rounded,
                size: 40, 
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              strings.t('mqtt_gateway_ble_offline'),
              style: AppTypography.headingLg, 
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              strings.t('mqtt_gateway_ble_offline_body'),
              style: AppTypography.bodyMd, 
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Remote station view ───────────────────────────────────────────────────────

class _RemoteStationView extends StatelessWidget {
  const _RemoteStationView({required this.mqtt, required this.strings});
  final MqttService mqtt;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final status = mqtt.remoteStatus;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xl,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _RemoteHeader(mqtt: mqtt, strings: strings),
              const SizedBox(height: AppSpacing.xxl),
              _RemoteBatteryRing(status: status),
              const SizedBox(height: AppSpacing.xxl),
              _RemoteMetricsRow(status: status, strings: strings),
              const SizedBox(height: AppSpacing.xl),
              _RemoteOutletSection(
                mqtt: mqtt, 
                status: status, 
                strings: strings,
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _RemoteHeader extends StatelessWidget {
  const _RemoteHeader({required this.mqtt, required this.strings});
  final MqttService mqtt;
  final AppStrings strings;

  String _formatLastUpdate() {
    final t = mqtt.lastRemoteUpdate;
    if (t == null) return '';
    final local = t.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        // MQTT link indicator using primaryContainer token (tealSurface)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: AppRadius.xsBR,
            border: Border.all(
              color: theme.colorScheme.primary.withOpacity(0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_done_rounded,
                size: 12, 
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                strings.t('mqtt_remote_label'),
                style: AppTypography.labelSm.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            mqtt.settings.topicPrefix,
            style: AppTypography.bodySm,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (mqtt.lastRemoteUpdate != null)
          Text(
            _formatLastUpdate(),
            style: AppTypography.labelSm,
          ),
      ],
    );
  }
}

// ── Battery ring ──────────────────────────────────────────────────────────────

class _RemoteBatteryRing extends StatelessWidget {
  const _RemoteBatteryRing({required this.status});
  final PowerStationStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = status.batteryLevel;
    final color = AppColors.batteryColor(level);
    final remaining = status.formattedRemainingTime;

    return Semantics(
      label: 'Remote battery level: $level percent',
      child: Center(
        child: SizedBox(
          width: 160,
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Uses tone-based background track container
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: 1,
                  strokeWidth: 12,
                  color: theme.colorScheme.surfaceContainer,
                ),
              ),
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: level / 100,
                  strokeWidth: 12,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$level%',
                    style: AppTypography.monoLg.copyWith(color: color),
                  ),
                  if (status.isCharging) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.bolt_rounded,
                          size: 12, 
                          color: AppColors.success,
                        ),
                        Text(
                          'Charging',
                          style: AppTypography.labelSm.copyWith(
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (remaining != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      status.isCharging
                          ? '$remaining to full'
                          : '$remaining left',
                      style: AppTypography.labelSm.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Metrics ───────────────────────────────────────────────────────────────────

class _RemoteMetricsRow extends StatelessWidget {
  const _RemoteMetricsRow({required this.status, required this.strings});
  final PowerStationStatus status;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: MetricCard(
            icon: Icons.arrow_downward_rounded,
            iconColor: AppColors.success,
            title: strings.t('charging'),
            value: '${status.inputWatts} W',
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: MetricCard(
            icon: Icons.arrow_upward_rounded,
            iconColor: AppColors.error,
            title: strings.t('discharging'),
            value: '${status.outputWatts} W',
          ),
        ),
      ],
    );
  }
}

// ── Outlet controls ───────────────────────────────────────────────────────────

class _RemoteOutletSection extends StatelessWidget {
  const _RemoteOutletSection({
    required this.mqtt,
    required this.status,
    required this.strings,
  });
  final MqttService mqtt;
  final PowerStationStatus status;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.t('controls'), style: AppTypography.labelLg),
        const SizedBox(height: AppSpacing.sm),
        // Information block
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, 
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.infoSurface,
            borderRadius: AppRadius.xsBR,
            border: Border.all(
              color: AppColors.info.withOpacity(0.25),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline,
                size: 12, 
                color: AppColors.info,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                strings.t('mqtt_command_latency_note'),
                style: AppTypography.labelSm.copyWith(color: AppColors.info),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ToggleCard(
                icon: Icons.usb_rounded,
                title: strings.t('usb'),
                activeLabel: strings.t('active'),
                disabledLabel: strings.t('disabled'),
                isActive: status.isUsbOn,
                activeColor: AppColors.usb,
                onTap: () => mqtt.sendCommand('usb', !status.isUsbOn),
              ),
              const SizedBox(width: AppSpacing.sm),
              ToggleCard(
                icon: Icons.power_rounded,
                title: strings.t('ac'),
                activeLabel: strings.t('active'),
                disabledLabel: strings.t('disabled'),
                isActive: status.isAcOn,
                activeColor: AppColors.ac,
                onTap: () => mqtt.sendCommand('ac', !status.isAcOn),
              ),
              const SizedBox(width: AppSpacing.sm),
              ToggleCard(
                icon: Icons.cable_rounded,
                title: strings.t('dc'),
                activeLabel: strings.t('active'),
                disabledLabel: strings.t('disabled'),
                isActive: status.isDcOn,
                activeColor: AppColors.dc,
                onTap: () => mqtt.sendCommand('dc', !status.isDcOn),
              ),
            ],
          ),
        ),
      ],
    );
  }
}