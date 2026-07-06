import 'package:ap_companion/models/mqtt_rpc_methods.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/power_station_status.dart';
import '../services/mqtt_service.dart';
import '../theme/app_theme.dart';
import '../widgets/outlet_controls_row.dart';
import '../widgets/station_battery_ring.dart';
import '../widgets/station_metrics_row.dart';

/// Control screen shown when the app is running in [AppMode.client].
///
/// All data comes from the MQTT broker (via [MqttService.remoteStatus]) rather
/// than a direct BLE connection. Outlet-toggle taps publish RPC commands
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
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.6),
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
                    color:
                        theme.colorScheme.error.withValues(alpha: 0.3),
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
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.successSurface,
                borderRadius: AppRadius.xsBR,
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3),
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
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.6),
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
              StationBatteryRing(
                status: status,
                semanticsLabelPrefix: 'Remote battery level',
              ),
              const SizedBox(height: AppSpacing.xxl),
              StationMetricsRow(status: status, strings: strings),
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
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: AppRadius.xsBR,
            border: Border.all(
              color:
                  theme.colorScheme.primary.withValues(alpha: 0.4),
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

// ── Outlet controls ───────────────────────────────────────────────────────────

class _RemoteOutletSection extends StatefulWidget {
  const _RemoteOutletSection({
    required this.mqtt,
    required this.status,
    required this.strings,
  });
  final MqttService mqtt;
  final PowerStationStatus status;
  final AppStrings strings;

  @override
  State<_RemoteOutletSection> createState() =>
      _RemoteOutletSectionState();
}

class _RemoteOutletSectionState extends State<_RemoteOutletSection> {
  // Per-outlet pending state: while an RPC is in-flight, show optimistic UI.
  bool? _usbPending;
  bool? _acPending;
  bool? _dcPending;

  Future<void> _toggle(
    String outlet,
    bool currentValue,
    void Function(bool?) setPending,
  ) async {
    final next = !currentValue;
    setState(() => setPending(next));
    try {
      final resp = await widget.mqtt.call(
        RpcMethod.setOutlet,
        {'outlet': outlet, 'value': next},
      );
      if (!resp.ok && mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text(
              resp.error ??
                  'Failed to toggle $outlet',
            ),
          ));
      }
    } finally {
      if (mounted) setState(() => setPending(null));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final strings = widget.strings;

    // Resolve displayed state: pending (optimistic) overrides confirmed.
    final usbOn = _usbPending ?? status.isUsbOn;
    final acOn = _acPending ?? status.isAcOn;
    final dcOn = _dcPending ?? status.isDcOn;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.t('controls'), style: AppTypography.labelLg),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.infoSurface,
            borderRadius: AppRadius.xsBR,
            border: Border.all(
              color: AppColors.info.withValues(alpha: 0.25),
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
              Expanded(
                child: Text(
                  strings.t('mqtt_command_latency_note'),
                  style: AppTypography.labelSm
                      .copyWith(color: AppColors.info),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        OutletControlsRow(
          strings: strings,
          isUsbOn: usbOn,
          isAcOn: acOn,
          isDcOn: dcOn,
          onToggleUsb: () =>
              _toggle('usb', status.isUsbOn, (v) => _usbPending = v),
          onToggleAc: () =>
              _toggle('ac', status.isAcOn, (v) => _acPending = v),
          onToggleDc: () =>
              _toggle('dc', status.isDcOn, (v) => _dcPending = v),
        ),
      ],
    );
  }
}