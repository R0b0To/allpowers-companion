import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/automation_settings.dart';
import '../services/ble_service.dart';
import '../services/webhook_service.dart';
import '../theme/app_theme.dart';
import '../widgets/debounced_settings_field.dart';
import '../widgets/time_selector_tile.dart';

/// Lists all automations. Currently only the smart-charging card.
/// Add future automations as additional cards below [_buildSmartChargingCard].
class AutomationsTab extends StatefulWidget {
  const AutomationsTab({
    super.key,
    required this.ble,
    required this.strings,
    required this.settings,
    required this.webhooks,
    required this.onSettingsChanged,
  });

  final BleService ble;
  final AppStrings strings;
  final AutomationSettings settings;
  final WebhookService webhooks;
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

  @override
  void didUpdateWidget(AutomationsTab old) {
    super.didUpdateWidget(old);
    // Keep text fields in sync if settings were changed externally (e.g. loaded
    // from disk on startup) without clobbering the cursor position.
    _syncIfChanged(_tapoOnController, widget.settings.tapoOnUrl);
    _syncIfChanged(_tapoOffController, widget.settings.tapoOffUrl);
    _syncIfChanged(_lowController, widget.settings.lowThreshold.toString());
    _syncIfChanged(_highController, widget.settings.highThreshold.toString());
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

  Future<void> _testWebhook(String url) async {
    final s = widget.strings;
    if (url.isEmpty) {
      _showSnack(s.t('webhook_url_missing'), color: Colors.amber);
      return;
    }
    final code = await widget.webhooks.test(url);
    if (!mounted) return;
    _showSnack(
      code == null ? 'Error' : '$code',
      color: code == null
          ? Colors.red
          : (code == 200 ? Colors.green : Colors.red),
    );
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
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                s.t('tab_automations'),
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),

            // ── Smart charging card ──────────────────────────────────────────
            _buildSmartChargingCard(s),

            // ── Future automations go here ───────────────────────────────────
            // e.g. _buildScheduledOutletCard(s),
            //      _buildLowBatteryAlertCard(s),
          ],
        ),
      ),
    );
  }

  Widget _buildSmartChargingCard(AppStrings s) {
    final enabled = widget.settings.enabled;
    return Card(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: enabled ? Colors.teal.withOpacity(0.5) : AppColors.border,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row + toggle
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

            // Time window
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

            // Battery thresholds
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

            // Webhooks
            Text(s.t('webhooks_section'),
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8)),
            const SizedBox(height: 10),
            DebouncedSettingsField(
              controller: _tapoOnController,
              label: s.t('on_webhook'),
              prefixIcon: Icons.arrow_downward,
              onChangedDebounced: _onFieldsChanged,
              suffixIcon: IconButton(
                icon: const Icon(Icons.send_rounded,
                    color: Colors.green, size: 18),
                onPressed: () => _testWebhook(_tapoOnController.text),
              ),
            ),
            const SizedBox(height: 12),
            DebouncedSettingsField(
              controller: _tapoOffController,
              label: s.t('off_webhook'),
              prefixIcon: Icons.arrow_upward,
              onChangedDebounced: _onFieldsChanged,
              suffixIcon: IconButton(
                icon: const Icon(Icons.send_rounded,
                    color: Colors.redAccent, size: 18),
                onPressed: () => _testWebhook(_tapoOffController.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}