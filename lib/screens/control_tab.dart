import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/app_strings.dart';
import '../models/power_station_status.dart';
import '../services/ble_service.dart';
import '../theme/app_theme.dart';
import '../widgets/outlet_controls_row.dart';
import '../widgets/station_battery_ring.dart';
import '../widgets/station_metrics_row.dart';

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
                // "AP Companion" is the product name — left untranslated,
                // same as any other brand name.
                Text('AP Companion', style: AppTypography.displaySm),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  strings.t('control_find_station'),
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
                  strings: strings,
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
    required this.strings,
    required this.onConnect,
  });

  final String name;
  final int rssi;
  final AppStrings strings;
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
            strings.t('connect'),
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
                  strings: strings,
                  onForget: ble.forgetDevice,
                ),
                const SizedBox(height: AppSpacing.xxl),
                StationBatteryRing(status: status),
                const SizedBox(height: AppSpacing.xxl),
                StationMetricsRow(status: status, strings: strings),
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
    required this.strings,
    required this.onForget,
  });

  final String deviceName;
  final AppStrings strings;
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
          tooltip: strings.t('forget'),
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
        OutletControlsRow(
          strings: strings,
          isUsbOn: status.isUsbOn,
          isAcOn: status.isAcOn,
          isDcOn: status.isDcOn,
          onToggleUsb: () => ble.setUsb(!status.isUsbOn),
          onToggleAc: () => ble.setAc(!status.isAcOn),
          onToggleDc: () => ble.setDc(!status.isDcOn),
        ),
      ],
    );
  }
}