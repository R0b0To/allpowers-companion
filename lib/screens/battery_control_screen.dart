import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/app_strings.dart';
import '../models/automation_settings.dart';
import '../services/automation_engine.dart';
import '../services/ble_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/webhook_service.dart';
import '../theme/app_theme.dart';
import '../widgets/debounced_settings_field.dart';
import '../widgets/metric_card.dart';
import '../widgets/time_selector_tile.dart';
import '../widgets/toggle_card.dart';

class BatteryControlScreen extends StatefulWidget {
  const BatteryControlScreen({super.key});

  @override
  State<BatteryControlScreen> createState() => _BatteryControlScreenState();
}

class _BatteryControlScreenState extends State<BatteryControlScreen> {
  final _storage = StorageService();
  final _notifications = NotificationService();
  final _webhooks = WebhookService();
  late final BleService _ble = BleService(_storage);
  late final AutomationEngine _automation = AutomationEngine(_ble, _webhooks);

  final _tapoOnController = TextEditingController();
  final _tapoOffController = TextEditingController();
  final _lowBatteryController = TextEditingController();
  final _highBatteryController = TextEditingController();

  AutomationSettings _settings = const AutomationSettings();
  bool _permissionsPermanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    _ble.onStatus = (status) {
      _notifications.handleBatteryLevel(status.batteryLevel);
      _automation.evaluate(_settings);
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    await _notifications.init();
    await _requestPermissions();

    final settings = await _storage.loadAutomationSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _tapoOnController.text = settings.tapoOnUrl;
      _tapoOffController.text = settings.tapoOffUrl;
      _lowBatteryController.text = settings.lowThreshold.toString();
      _highBatteryController.text = settings.highThreshold.toString();
    });

    await _ble.init();
  }

  Future<void> _requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    final permanentlyDenied = statuses.values.any((s) => s.isPermanentlyDenied);
    if (mounted) {
      setState(() => _permissionsPermanentlyDenied = permanentlyDenied);
    }
  }

  Future<void> _persistSettings(AutomationSettings settings) async {
    setState(() => _settings = settings);
    await _storage.saveAutomationSettings(settings);
  }

  void _onAutomationToggled(bool enabled) {
    _persistSettings(_settings.copyWith(enabled: enabled));
  }

  int _parseThreshold(String text, int fallback) {
    final parsed = int.tryParse(text);
    if (parsed == null) return fallback;
    if (parsed < 0) return 0;
    if (parsed > 100) return 100;
    return parsed;
  }

  void _onTextFieldsChanged() {
    final low = _parseThreshold(_lowBatteryController.text, _settings.lowThreshold);
    final high = _parseThreshold(_highBatteryController.text, _settings.highThreshold);
    _persistSettings(_settings.copyWith(
      tapoOnUrl: _tapoOnController.text,
      tapoOffUrl: _tapoOffController.text,
      lowThreshold: low,
      highThreshold: high,
    ));
  }

  Future<void> _selectTime(bool isStart) async {
    final initial = isStart ? _settings.startTime : _settings.endTime;
    final selected = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => Theme(data: AppTheme.timePickerTheme, child: child!),
    );
    if (selected == null) return;
    _persistSettings(isStart
        ? _settings.copyWith(startTime: selected)
        : _settings.copyWith(endTime: selected));
  }

  Future<void> _testWebhook(String url, AppStrings strings) async {
    if (url.isEmpty) {
      _showSnack(strings.t('webhook_url_missing'), color: Colors.amber);
      return;
    }
    final statusCode = await _webhooks.test(url);
    if (!mounted) return;
    if (statusCode == null) {
      _showSnack('Error', color: Colors.red);
    } else {
      _showSnack('$statusCode', color: statusCode == 200 ? Colors.green : Colors.red);
    }
  }

  void _showSnack(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: color, content: Text(message)),
    );
  }

  @override
  void dispose() {
    _ble.dispose();
    _tapoOnController.dispose();
    _tapoOffController.dispose();
    _lowBatteryController.dispose();
    _highBatteryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIt = Localizations.localeOf(context).languageCode == 'it';
    final strings = AppStrings(isIt);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
          child: AnimatedBuilder(
            animation: _ble,
            builder: (context, _) => _buildBody(strings),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(AppStrings strings) {
    if (_ble.isAutoConnecting) return _buildConnectingView(strings);
    if (!_ble.isConnected) return _buildScanView(strings);
    return _buildConnectedView(strings);
  }

  Widget _buildConnectingView(AppStrings strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 120),
        const CircularProgressIndicator(),
        const SizedBox(height: 30),
        Text(strings.t('connecting'), style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        const SizedBox(height: 40),
        IconButton(
          onPressed: _ble.forgetDevice,
          icon: const Icon(Icons.close, color: Colors.red, size: 32),
        ),
      ],
    );
  }

  Widget _buildScanView(AppStrings strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_permissionsPermanentlyDenied) _buildPermissionsBanner(strings),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _ble.isScanning ? null : _ble.startScan,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(_ble.isScanning ? strings.t('scanning') : strings.t('scan')),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (!_ble.isScanning && _ble.scanResults.isEmpty)
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
          itemCount: _ble.scanResults.length,
          itemBuilder: (context, index) {
            final device = _ble.scanResults[index].device;
            final displayName = device.platformName.isNotEmpty ? device.platformName : 'AP';
            return Card(
              child: ListTile(
                leading: const Icon(Icons.bluetooth, color: Colors.grey),
                title: Text(displayName),
                trailing: IconButton(
                  icon: const Icon(Icons.link, color: Colors.teal),
                  onPressed: () => _ble.connectToDevice(device),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPermissionsBanner(AppStrings strings) {
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
            Text(strings.t('permissions_required_title'), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(strings.t('permissions_required_body'), style: const TextStyle(fontSize: 13, color: Colors.grey)),
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

  Widget _buildConnectedView(AppStrings strings) {
    final status = _ble.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.bluetooth_connected, color: Colors.green, size: 22),
                const SizedBox(width: 8),
                Text(
                  '${strings.t('connected')} ${_ble.connectedDevice?.platformName ?? 'AP'}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            IconButton(
              onPressed: _ble.forgetDevice,
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
                valueColor: AlwaysStoppedAnimation<Color>(status.batteryLevel <= 20 ? Colors.red : Colors.teal),
              ),
            ),
            Text('${status.batteryLevel}%', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 30),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ToggleCard(
              icon: Icons.usb,
              title: strings.t('usb'),
              activeLabel: strings.t('active'),
              disabledLabel: strings.t('disabled'),
              isActive: status.isUsbOn,
              activeColor: Colors.blue,
              onTap: () => _ble.setUsb(!status.isUsbOn),
            ),
            const SizedBox(width: 10),
            ToggleCard(
              icon: Icons.power,
              title: strings.t('ac'),
              activeLabel: strings.t('active'),
              disabledLabel: strings.t('disabled'),
              isActive: status.isAcOn,
              activeColor: Colors.orange,
              onTap: () => _ble.setAc(!status.isAcOn),
            ),
            const SizedBox(width: 10),
            ToggleCard(
              icon: Icons.circle_outlined,
              title: strings.t('dc'),
              activeLabel: strings.t('active'),
              disabledLabel: strings.t('disabled'),
              isActive: status.isDcOn,
              activeColor: Colors.green,
              onTap: () => _ble.setDc(!status.isDcOn),
            ),
          ],
        ),
        const SizedBox(height: 30),
        _buildAutomationCard(strings),
      ],
    );
  }

  Widget _buildAutomationCard(AppStrings strings) {
    return Card(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _settings.enabled ? Colors.teal.withOpacity(0.5) : AppColors.border,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.sync_alt, color: Colors.teal),
                    const SizedBox(width: 10),
                    Text(strings.t('automation'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                Switch(
                  value: _settings.enabled,
                  activeColor: Colors.teal,
                  onChanged: _onAutomationToggled,
                ),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                TimeSelectorTile(
                  label: strings.t('start_time'),
                  formattedTime: _formatTimeOfDay(_settings.startTime),
                  onTap: () => _selectTime(true),
                ),
                const SizedBox(width: 10),
                TimeSelectorTile(
                  label: strings.t('end_time'),
                  formattedTime: _formatTimeOfDay(_settings.endTime),
                  onTap: () => _selectTime(false),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DebouncedSettingsField(
              controller: _tapoOnController,
              label: strings.t('on_webhook'),
              prefixIcon: Icons.arrow_downward,
              onChangedDebounced: _onTextFieldsChanged,
              suffixIcon: IconButton(
                icon: const Icon(Icons.send_rounded, color: Colors.green, size: 18),
                onPressed: () => _testWebhook(_tapoOnController.text, strings),
              ),
            ),
            const SizedBox(height: 12),
            DebouncedSettingsField(
              controller: _tapoOffController,
              label: strings.t('off_webhook'),
              prefixIcon: Icons.arrow_upward,
              onChangedDebounced: _onTextFieldsChanged,
              suffixIcon: IconButton(
                icon: const Icon(Icons.send_rounded, color: Colors.redAccent, size: 18),
                onPressed: () => _testWebhook(_tapoOffController.text, strings),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DebouncedSettingsField(
                    controller: _lowBatteryController,
                    label: strings.t('low_limit'),
                    prefixIcon: Icons.battery_alert,
                    keyboardType: TextInputType.number,
                    onChangedDebounced: _onTextFieldsChanged,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DebouncedSettingsField(
                    controller: _highBatteryController,
                    label: strings.t('high_limit'),
                    prefixIcon: Icons.battery_charging_full,
                    keyboardType: TextInputType.number,
                    onChangedDebounced: _onTextFieldsChanged,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeOfDay(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}