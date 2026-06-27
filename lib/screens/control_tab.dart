import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/app_strings.dart';
import '../models/power_station_status.dart';
import '../services/ble_service.dart';
import '../theme/app_theme.dart';
import '../widgets/metric_card.dart';
import '../widgets/toggle_card.dart';

/// Displays connection state, live station metrics, and outlet controls.
///
/// Receives [BleService] from [MainShell] — creates nothing itself.
class ControlTab extends StatelessWidget {
  const ControlTab({
    super.key,
    required this.ble,
    required this.strings,
    required this.permissionsPermanentlyDenied,
  });

  final BleService ble;
  final AppStrings strings;
  final bool permissionsPermanentlyDenied;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ble,
      builder: (context, _) {
        return SafeArea(
          child: _buildBody(context),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    if (ble.blueAdapterState == BluetoothAdapterState.off ||
        ble.blueAdapterState == BluetoothAdapterState.unavailable) {
      return _BluetoothOffView(strings: strings);
    }
    if (ble.isAutoConnecting) {
      return _ConnectingView(ble: ble, strings: strings);
    }
    if (!ble.isConnected) {
      return _ScanView(
        ble: ble,
        strings: strings,
        permissionsPermanentlyDenied: permissionsPermanentlyDenied,
      );
    }
    return _ConnectedView(ble: ble, strings: strings);
  }
}

// ── Bluetooth disabled ──────────────────────────────────────────────────────

class _BluetoothOffView extends StatelessWidget {
  const _BluetoothOffView({required this.strings});
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
                Icons.bluetooth_disabled_rounded,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha:0.6),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              strings.t('bluetooth_off_title'),
              style: AppTypography.headingLg,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              strings.t('bluetooth_off_body'),
              style: AppTypography.bodyMd,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Auto-connecting ─────────────────────────────────────────────────────────

class _ConnectingView extends StatelessWidget {
  const _ConnectingView({required this.ble, required this.strings});
  final BleService ble;
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
              strings.t('connecting'),
              style: AppTypography.headingMd,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xxxl),
            OutlinedButton.icon(
              onPressed: ble.forgetDevice,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: Text(strings.t('cancel_forget')),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Scan view ───────────────────────────────────────────────────────────────

class _ScanView extends StatelessWidget {
  const _ScanView({
    required this.ble,
    required this.strings,
    required this.permissionsPermanentlyDenied,
  });

  final BleService ble;
  final AppStrings strings;
  final bool permissionsPermanentlyDenied;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xxl,
              AppSpacing.lg,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AP Companion', style: AppTypography.displaySm),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Find your Allpowers station',
                  style: AppTypography.bodyMd,
                ),
                const SizedBox(height: AppSpacing.xxl),
                if (permissionsPermanentlyDenied)
                  _PermissionsBanner(strings: strings),
                if (permissionsPermanentlyDenied)
                  const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: ble.isScanning ? null : ble.startScan,
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: ble.isScanning
                          ? SizedBox(
                              key: const ValueKey('spinner'),
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onPrimary,
                              ),
                            )
                          : const Icon(
                              key: ValueKey('icon'),
                              Icons.bluetooth_searching_rounded,
                              size: 18,
                            ),
                    ),
                    label: Text(
                      ble.isScanning
                          ? strings.t('scanning')
                          : strings.t('scan'),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
        if (!ble.isScanning && ble.scanResults.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxxl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.radar_rounded,
                      size: 48,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha:0.4),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      strings.t('no_devices_found'),
                      style: AppTypography.bodyMd,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            sliver: SliverList.separated(
              itemCount: ble.scanResults.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final result = ble.scanResults[index];
                final device = result.device;
                final name = device.platformName.isNotEmpty
                    ? device.platformName
                    : 'AP Station';
                final rssi = result.rssi;
                return _DeviceTile(
                  name: name,
                  rssi: rssi,
                  onConnect: () => ble.connectToDevice(device),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.name,
    required this.rssi,
    required this.onConnect,
  });

  final String name;
  final int rssi;
  final VoidCallback onConnect;

  IconData get _signalIcon {
    if (rssi >= -60) return Icons.signal_wifi_4_bar_rounded;
    if (rssi >= -75) return Icons.network_wifi_3_bar_rounded;
    if (rssi >= -85) return Icons.network_wifi_2_bar_rounded;
    return Icons.network_wifi_1_bar_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.mdBR,
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: AppRadius.smBR,
          ),
          child: Icon(
            Icons.battery_charging_full_rounded,
            color: theme.colorScheme.primary,
            size: 20,
          ),
        ),
        title: Text(name, style: AppTypography.headingSm),
        subtitle: Row(
          children: [
            Icon(
              _signalIcon, 
              size: 12, 
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha:0.6),
            ),
            const SizedBox(width: 4),
            Text('$rssi dBm', style: AppTypography.labelSm),
          ],
        ),
        trailing: FilledButton(
          onPressed: onConnect,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            'Connect', 
            style: AppTypography.labelMd.copyWith(color: theme.colorScheme.primary),
          ),
        ),
      ),
    );
  }
}

class _PermissionsBanner extends StatelessWidget {
  const _PermissionsBanner({required this.strings});
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.warningSurface,
        borderRadius: AppRadius.mdBR,
        border: Border.all(color: AppColors.warning.withValues(alpha:0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 16, color: AppColors.warning),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  strings.t('permissions_required_title'),
                  style: AppTypography.headingSm
                      .copyWith(color: AppColors.warning),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            strings.t('permissions_required_body'),
            style: AppTypography.bodySm
                .copyWith(color: AppColors.warning.withValues(alpha:0.8)),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            onPressed: openAppSettings,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.warning,
              side: BorderSide(color: AppColors.warning.withValues(alpha:0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              strings.t('open_settings'),
              style: AppTypography.labelMd.copyWith(color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Connected view ──────────────────────────────────────────────────────────

class _ConnectedView extends StatelessWidget {
  const _ConnectedView({required this.ble, required this.strings});
  final BleService ble;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final status = ble.status;
    final deviceName =
        ble.connectedDevice?.platformName.isNotEmpty == true
            ? ble.connectedDevice!.platformName
            : 'AP Station';

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ConnectionHeader(
                  deviceName: deviceName,
                  onForget: ble.forgetDevice,
                ),
                const SizedBox(height: AppSpacing.xxl),
                _BatteryRing(status: status),
                const SizedBox(height: AppSpacing.xxl),
                _MetricsRow(status: status, strings: strings),
                const SizedBox(height: AppSpacing.xl),
                _OutletSection(ble: ble, status: status, strings: strings),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ConnectionHeader extends StatelessWidget {
  const _ConnectionHeader({
    required this.deviceName,
    required this.onForget,
  });

  final String deviceName;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppColors.success,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            deviceName,
            style: AppTypography.headingSm,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          onPressed: onForget,
          tooltip: 'Forget device',
          style: IconButton.styleFrom(
            backgroundColor: theme.colorScheme.errorContainer,
            foregroundColor: theme.colorScheme.onErrorContainer,
          ),
          icon: const Icon(Icons.link_off_rounded, size: 18),
        ),
      ],
    );
  }
}

class _BatteryRing extends StatelessWidget {
  const _BatteryRing({required this.status});
  final PowerStationStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = status.batteryLevel;
    final color = AppColors.batteryColor(level);
    final remainingTime = status.formattedRemainingTime;

    return Semantics(
      label: 'Battery level: $level percent',
      child: Center(
        child: SizedBox(
          width: 160,
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Track ring (uses tone-based surfaceContainer)
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: 1,
                  strokeWidth: 12,
                  color: theme.colorScheme.surfaceContainer,
                ),
              ),
              // Value ring
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: level / 100,
                  strokeWidth: 12,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              // Centre content
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
                  // Remaining time indicator
                  if (remainingTime != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      status.isCharging ? '$remainingTime to full' : '$remainingTime left',
                      style: AppTypography.labelSm.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha:0.6),
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

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.status, required this.strings});
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

class _OutletSection extends StatelessWidget {
  const _OutletSection({
    required this.ble,
    required this.status,
    required this.strings,
  });

  final BleService ble;
  final PowerStationStatus status;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(strings.t('controls'), style: AppTypography.labelLg),
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
                onTap: () => ble.setUsb(!status.isUsbOn),
              ),
              const SizedBox(width: AppSpacing.sm),
              ToggleCard(
                icon: Icons.power_rounded,
                title: strings.t('ac'),
                activeLabel: strings.t('active'),
                disabledLabel: strings.t('disabled'),
                isActive: status.isAcOn,
                activeColor: AppColors.ac,
                onTap: () => ble.setAc(!status.isAcOn),
              ),
              const SizedBox(width: AppSpacing.sm),
              ToggleCard(
                icon: Icons.cable_rounded,
                title: strings.t('dc'),
                activeLabel: strings.t('active'),
                disabledLabel: strings.t('disabled'),
                isActive: status.isDcOn,
                activeColor: AppColors.dc,
                onTap: () => ble.setDc(!status.isDcOn),
              ),
            ],
          ),
        ),
      ],
    );
  }
}