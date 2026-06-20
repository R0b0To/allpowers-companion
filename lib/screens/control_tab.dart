import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/app_strings.dart';
import '../services/ble_service.dart';
import '../theme/app_theme.dart';
import '../widgets/metric_card.dart';
import '../widgets/toggle_card.dart';

/// Shows BT state / scan / connected device UI.
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
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: AnimatedBuilder(
          animation: ble,
          builder: (context, _) => _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (ble.blueAdapterState == BluetoothAdapterState.off ||
        ble.blueAdapterState == BluetoothAdapterState.unavailable) {
      return _buildBluetoothOffView();
    }
    if (ble.isAutoConnecting) return _buildConnectingView();
    if (!ble.isConnected) return _buildScanView(context);
    return _buildConnectedView();
  }

  // ── Bluetooth disabled ────────────────────────────────────────────────────

  Widget _buildBluetoothOffView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey),
        const SizedBox(height: 24),
        Text(
          strings.t('bluetooth_off_title'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          strings.t('bluetooth_off_body'),
          style: const TextStyle(color: Colors.grey, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ── Connecting ────────────────────────────────────────────────────────────

  Widget _buildConnectingView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 120),
        const CircularProgressIndicator(),
        const SizedBox(height: 30),
        Text(
          strings.t('connecting'),
          style: const TextStyle(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
        Center(
          child: IconButton(
            onPressed: ble.forgetDevice,
            icon: const Icon(Icons.close, color: Colors.red, size: 32),
          ),
        ),
      ],
    );
  }

  // ── Scan ──────────────────────────────────────────────────────────────────

  Widget _buildScanView(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (permissionsPermanentlyDenied) _buildPermissionsBanner(),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: ble.isScanning ? null : ble.startScan,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(ble.isScanning
                  ? strings.t('scanning')
                  : strings.t('scan')),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (!ble.isScanning && ble.scanResults.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              strings.t('no_devices_found'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: ble.scanResults.length,
          itemBuilder: (context, index) {
            final device = ble.scanResults[index].device;
            final name =
                device.platformName.isNotEmpty ? device.platformName : 'AP';
            return Card(
              child: ListTile(
                leading: const Icon(Icons.bluetooth, color: Colors.grey),
                title: Text(name),
                trailing: IconButton(
                  icon: const Icon(Icons.link, color: Colors.teal),
                  onPressed: () => ble.connectToDevice(device),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPermissionsBanner() {
    return Card(
      color: Colors.amber.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.amber.withOpacity(0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.t('permissions_required_title'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(strings.t('permissions_required_body'),
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: openAppSettings,
              child: Text(strings.t('open_settings')),
            ),
          ],
        ),
      ),
    );
  }

  // ── Connected ─────────────────────────────────────────────────────────────

  Widget _buildConnectedView() {
    final status = ble.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.bluetooth_connected,
                    color: Colors.green, size: 22),
                const SizedBox(width: 8),
                Text(
                  '${strings.t('connected')} '
                  '${ble.connectedDevice?.platformName ?? 'AP'}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            IconButton(
              onPressed: ble.forgetDevice,
              icon: const Icon(Icons.link_off, color: Colors.red, size: 24),
            ),
          ],
        ),
        const Divider(height: 20, color: AppColors.borderSubtle),
        const SizedBox(height: 10),
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 130,
              height: 130,
              child: CircularProgressIndicator(
                value: status.batteryLevel / 100,
                strokeWidth: 10,
                backgroundColor: const Color(0xFF222222),
                valueColor: AlwaysStoppedAnimation<Color>(
                    status.batteryLevel <= 20 ? Colors.red : Colors.teal),
              ),
            ),
            Text(
              '${status.batteryLevel}%',
              style: const TextStyle(
                  fontSize: 32, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 30),
        Row(
          children: [
            Expanded(
              child: MetricCard(
                icon: Icons.arrow_downward,
                iconColor: Colors.green,
                title: strings.t('charging'),
                value: '${status.inputWatts} W',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: MetricCard(
                icon: Icons.arrow_upward,
                iconColor: Colors.redAccent,
                title: strings.t('discharging'),
                value: '${status.outputWatts} W',
              ),
            ),
          ],
        ),
        const SizedBox(height: 30),
        Row(
          children: [
            ToggleCard(
              icon: Icons.usb,
              title: strings.t('usb'),
              activeLabel: strings.t('active'),
              disabledLabel: strings.t('disabled'),
              isActive: status.isUsbOn,
              activeColor: Colors.blue,
              onTap: () => ble.setUsb(!status.isUsbOn),
            ),
            const SizedBox(width: 10),
            ToggleCard(
              icon: Icons.power,
              title: strings.t('ac'),
              activeLabel: strings.t('active'),
              disabledLabel: strings.t('disabled'),
              isActive: status.isAcOn,
              activeColor: Colors.orange,
              onTap: () => ble.setAc(!status.isAcOn),
            ),
            const SizedBox(width: 10),
            ToggleCard(
              icon: Icons.circle_outlined,
              title: strings.t('dc'),
              activeLabel: strings.t('active'),
              disabledLabel: strings.t('disabled'),
              isActive: status.isDcOn,
              activeColor: Colors.green,
              onTap: () => ble.setDc(!status.isDcOn),
            ),
          ],
        ),
      ],
    );
  }
}