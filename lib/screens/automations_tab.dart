import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/automation_settings.dart';
import '../services/ble_service.dart';
import '../services/webhook_service.dart';
import '../services/tapo_service.dart'; 
import '../theme/app_theme.dart';
import '../widgets/debounced_settings_field.dart';
import '../widgets/time_selector_tile.dart';

class AutomationsTab extends StatefulWidget {
  const AutomationsTab({
    super.key,
    required this.ble,
    required this.strings,
    required this.settings,
    required this.webhooks,
    required this.tapo, 
    required this.onSettingsChanged,
  });

  final BleService ble;
  final AppStrings strings;
  final AutomationSettings settings;
  final WebhookService webhooks;
  final TapoService tapo;
  final ValueChanged<AutomationSettings> onSettingsChanged;

  @override
  State<AutomationsTab> createState() => _AutomationsTabState();
}

class _AutomationsTabState extends State<AutomationsTab> {
  late final _tapoOnController =
      TextEditingController(text: widget.settings.tapoOnUrl);
  late final _tapoOffController =
      TextEditingController(text: widget.settings.tapoOffUrl);
  late final _lowController =
      TextEditingController(text: widget.settings.lowThreshold.toString());
  late final _highController =
      TextEditingController(text: widget.settings.highThreshold.toString());

  // Tapo Local Controllers
  late final _tapoIpController =
      TextEditingController(text: widget.settings.tapoIp);
  late final _tapoEmailController =
      TextEditingController(text: widget.settings.tapoEmail);
  late final _tapoPasswordController =
      TextEditingController(text: widget.settings.tapoPassword);

  bool _testingTapo = false;
  bool _testingOnAction = false;
  bool _testingOffAction = false;


  @override
  void didUpdateWidget(AutomationsTab old) {
    super.didUpdateWidget(old);
    _syncIfChanged(_tapoOnController, widget.settings.tapoOnUrl);
    _syncIfChanged(_tapoOffController, widget.settings.tapoOffUrl);
    _syncIfChanged(_lowController, widget.settings.lowThreshold.toString());
    _syncIfChanged(_highController, widget.settings.highThreshold.toString());
    
    // Sync Tapo credentials
    _syncIfChanged(_tapoIpController, widget.settings.tapoIp);
    _syncIfChanged(_tapoEmailController, widget.settings.tapoEmail);
    _syncIfChanged(_tapoPasswordController, widget.settings.tapoPassword);
  }

  void _syncIfChanged(TextEditingController c, String value) {
    if (c.text != value) c.text = value;
  }

  @override
  void dispose() {
    _tapoOnController.dispose();
    _tapoOffController.dispose();
    _lowController.dispose();
    _highController.dispose();
    _tapoIpController.dispose();
    _tapoEmailController.dispose();
    _tapoPasswordController.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  int _parseThreshold(String text, int fallback) {
    final v = int.tryParse(text);
    if (v == null) return fallback;
    return v.clamp(0, 100);
  }

  void _onFieldsChanged() {
    widget.onSettingsChanged(widget.settings.copyWith(
      tapoOnUrl: _tapoOnController.text,
      tapoOffUrl: _tapoOffController.text,
      lowThreshold:
          _parseThreshold(_lowController.text, widget.settings.lowThreshold),
      highThreshold:
          _parseThreshold(_highController.text, widget.settings.highThreshold),
      tapoIp: _tapoIpController.text,
      tapoEmail: _tapoEmailController.text,
      tapoPassword: _tapoPasswordController.text,
    ));
  }

  Future<void> _selectTime(bool isStart) async {
    final initial =
        isStart ? widget.settings.startTime : widget.settings.endTime;
    final selected = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) =>
          Theme(data: AppTheme.timePickerTheme, child: child!),
    );
    if (selected == null) return;
    widget.onSettingsChanged(isStart
        ? widget.settings.copyWith(startTime: selected)
        : widget.settings.copyWith(endTime: selected));
  }

  /// Helper to execute an ON/OFF action, prioritizing local Tapo if configured.
  Future<String> _executeAutomationAction({required bool turnOn}) async {
    final s = widget.strings;
    final settings = widget.settings;
    bool localSuccess = false;
    String actionMessage = '';

    if (settings.useLocalTapo) {
      if (settings.tapoIp.isEmpty || settings.tapoEmail.isEmpty || settings.tapoPassword.isEmpty) {
        actionMessage = s.t('tapo_credentials_incomplete');
      } else {
        actionMessage =
            turnOn ? s.t('tapo_attempting_local_on') : s.t('tapo_attempting_local_off');
        localSuccess = await widget.tapo.setOn(
          ip: settings.tapoIp,
          email: settings.tapoEmail,
          password: settings.tapoPassword,
          on: turnOn,
        );
        if (localSuccess) {
          actionMessage =
              turnOn ? s.t('tapo_local_on_successful') : s.t('tapo_local_off_successful');
        } else {
          actionMessage =
              turnOn ? s.t('tapo_local_on_failed') : s.t('tapo_local_off_failed');
        }
      }
    }

    if (!localSuccess) { // If local control failed or wasn't used
      final webhookUrl = turnOn ? settings.tapoOnUrl : settings.tapoOffUrl;
      if (webhookUrl.isEmpty) {
        actionMessage += (actionMessage.isEmpty ? '' : '\n') + s.t('webhook_url_missing');
      } else {
        actionMessage += (actionMessage.isEmpty ? '' : '\n') + s.t('executing_webhook');
        final code = await widget.webhooks.test(webhookUrl);
        if (code == null) {
          actionMessage += ' ${s.t('webhook_failed')}';
        } else if (code == 200) {
          actionMessage += ' ${s.t('webhook_successful_prefix')} $code).';
        } else {
          actionMessage += ' ${s.t('webhook_failed_with_code_prefix')} $code).';
        }
      }
    }
    return actionMessage;
  }

  Future<void> _testOnAction() async {
    setState(() => _testingOnAction = true);
    final result = await _executeAutomationAction(turnOn: true);
    setState(() => _testingOnAction = false);
    if (!mounted) return;
    _showSnack(result, color: result.contains('successful') || result.contains('riuscito')
        ? Colors.green
        : Colors.red);
  }

  Future<void> _testOffAction() async {
    setState(() => _testingOffAction = true);
    final result = await _executeAutomationAction(turnOn: false);
    setState(() => _testingOffAction = false);
    if (!mounted) return;
    _showSnack(result, color: result.contains('successful') || result.contains('riuscito')
        ? Colors.green
        : Colors.red);
  }

  Future<void> _testLocalTapo() async {
    final s = widget.strings;
    final ip = _tapoIpController.text.trim();
    final email = _tapoEmailController.text.trim();
    final password = _tapoPasswordController.text;

    if (ip.isEmpty || email.isEmpty || password.isEmpty) {
      _showSnack(s.t('tapo_fields_incomplete'), color: Colors.amber);
      return;
    }

    setState(() => _testingTapo = true);
    _showSnack(s.t('tapo_attempting_connection'), color: Colors.blueGrey);

    final result = await widget.tapo.test(
      ip: ip,
      email: email,
      password: password,
    );

    setState(() => _testingTapo = false);
    if (!mounted) return;

    final isSuccess = result.startsWith('Connected');
    _showSnack(result, color: isSuccess ? Colors.green : Colors.red);
  }

  void _showSnack(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: color, content: Text(message)),
    );
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                s.t('tab_automations'),
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),

            _buildSmartChargingCard(s),
            const SizedBox(height: 16),
            _buildTapoLocalCard(s),
          ],
        ),
      ),
    );
  }

  Widget _buildSmartChargingCard(AppStrings s) {
    final enabled = widget.settings.enabled;
    final useLocalTapo = widget.settings.useLocalTapo;
    return Card(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: enabled ? Colors.teal.withValues(alpha: 0.5) : AppColors.border,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                    Text(s.t('automation'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                Switch(
                  value: enabled,
                  activeColor: Colors.teal,
                  onChanged: (v) => widget.onSettingsChanged(
                      widget.settings.copyWith(enabled: v)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              s.t('automation_description'),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                TimeSelectorTile(
                  label: s.t('start_time'),
                  formattedTime: _fmt(widget.settings.startTime),
                  onTap: () => _selectTime(true),
                ),
                const SizedBox(width: 10),
                TimeSelectorTile(
                  label: s.t('end_time'),
                  formattedTime: _fmt(widget.settings.endTime),
                  onTap: () => _selectTime(false),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: DebouncedSettingsField(
                    controller: _lowController,
                    label: s.t('low_limit'),
                    prefixIcon: Icons.battery_alert,
                    keyboardType: TextInputType.number,
                    onChangedDebounced: _onFieldsChanged,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DebouncedSettingsField(
                    controller: _highController,
                    label: s.t('high_limit'),
                    prefixIcon: Icons.battery_charging_full,
                    keyboardType: TextInputType.number,
                    onChangedDebounced: _onFieldsChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            const Divider(color: AppColors.border),
            const SizedBox(height: 12),

            // --- Plug Control Actions Section ---
            Text(s.t('plug_control_actions'),
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8)),
            const SizedBox(height: 10),

            // ON Action
            DebouncedSettingsField(
              controller: _tapoOnController,
              label: useLocalTapo
                  ? s.t('on_webhook_url_fallback')
                  : s.t('on_webhook_url'),
              prefixIcon: Icons.arrow_downward,
              onChangedDebounced: _onFieldsChanged,
              readOnly: useLocalTapo && _tapoOnController.text.isEmpty, // Make read-only if local is on and no URL set
              suffixIcon: IconButton(
                icon: _testingOnAction
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded, color: Colors.green, size: 18),
                onPressed: _testingOnAction ? null : _testOnAction,
              ),
            ),
            const SizedBox(height: 12),

            // OFF Action
            DebouncedSettingsField(
              controller: _tapoOffController,
              label: useLocalTapo
                  ? s.t('off_webhook_url_fallback')
                  : s.t('off_webhook_url'),
              prefixIcon: Icons.arrow_upward,
              onChangedDebounced: _onFieldsChanged,
              readOnly: useLocalTapo && _tapoOffController.text.isEmpty, // Make read-only if local is on and no URL set
              suffixIcon: IconButton(
                icon: _testingOffAction
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded, color: Colors.redAccent, size: 18),
                onPressed: _testingOffAction ? null : _testOffAction,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTapoLocalCard(AppStrings s) {
    final useLocal = widget.settings.useLocalTapo;
    return Card(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: useLocal ? Colors.teal.withValues(alpha: 0.5) : AppColors.border,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.wifi_tethering, color: Colors.teal),
                    const SizedBox(width: 10),
                    Text(s.t('local_tapo_title'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                Switch(
                  value: useLocal,
                  activeColor: Colors.teal,
                  onChanged: (v) => widget.onSettingsChanged(
                      widget.settings.copyWith(useLocalTapo: v)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              s.t('local_tapo_description'),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            
            if (useLocal) ...[
              const SizedBox(height: 16),
              DebouncedSettingsField(
                controller: _tapoIpController,
                label: s.t('tapo_ip_label'),
                prefixIcon: Icons.wifi,
                onChangedDebounced: _onFieldsChanged,
              ),
              const SizedBox(height: 12),
              DebouncedSettingsField(
                controller: _tapoEmailController,
                label: s.t('tapo_email_label'),
                prefixIcon: Icons.email_outlined,
                onChangedDebounced: _onFieldsChanged,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tapoPasswordController,
                obscureText: true,
                onChanged: (_) => _onFieldsChanged(),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  labelText: s.t('tapo_password_label'),
                  prefixIcon: const Icon(Icons.lock_outline, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _testingTapo ? null : _testLocalTapo,
                  icon: _testingTapo 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.phonelink_ring_rounded),
                  label: Text(s.t('test_local_handshake')),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}