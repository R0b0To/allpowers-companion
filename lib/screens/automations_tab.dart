import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/automation_settings.dart';
import '../services/ble_service.dart';
import '../services/tapo_service.dart';
import '../services/webhook_service.dart';
import '../theme/app_theme.dart';
import '../widgets/debounced_settings_field.dart';
import '../widgets/section_card.dart';
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
  late final TextEditingController _onUrlCtrl;
  late final TextEditingController _offUrlCtrl;
  late final TextEditingController _lowCtrl;
  late final TextEditingController _highCtrl;

  bool _testingOn = false;
  bool _testingOff = false;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _onUrlCtrl = TextEditingController(text: s.tapoOnUrl);
    _offUrlCtrl = TextEditingController(text: s.tapoOffUrl);
    _lowCtrl = TextEditingController(text: s.lowThreshold.toString());
    _highCtrl = TextEditingController(text: s.highThreshold.toString());
  }

  @override
  void didUpdateWidget(AutomationsTab old) {
    super.didUpdateWidget(old);
    final s = widget.settings;
    _syncIfChanged(_onUrlCtrl, s.tapoOnUrl);
    _syncIfChanged(_offUrlCtrl, s.tapoOffUrl);
    _syncIfChanged(_lowCtrl, s.lowThreshold.toString());
    _syncIfChanged(_highCtrl, s.highThreshold.toString());
  }

  void _syncIfChanged(TextEditingController c, String value) {
    if (c.text != value) c.text = value;
  }

  @override
  void dispose() {
    for (final c in [_onUrlCtrl, _offUrlCtrl, _lowCtrl, _highCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onFieldsChanged() {
    final low = int.tryParse(_lowCtrl.text) ?? widget.settings.lowThreshold;
    final high = int.tryParse(_highCtrl.text) ?? widget.settings.highThreshold;

    widget.onSettingsChanged(widget.settings.copyWith(
      tapoOnUrl: _onUrlCtrl.text,
      tapoOffUrl: _offUrlCtrl.text,
      lowThreshold: low,
      highThreshold: high,
    ));
  }

  Future<void> _selectTime(bool isStart) async {
    final initial =
        isStart ? widget.settings.startTime : widget.settings.endTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) =>
          Theme(data: AppTheme.timePickerTheme, child: child!),
    );
    if (picked == null) return;
    widget.onSettingsChanged(
      isStart
          ? widget.settings.copyWith(startTime: picked)
          : widget.settings.copyWith(endTime: picked),
    );
  }

  Future<String> _executeAction({required bool on}) async {
    final s = widget.strings;
    final settings = widget.settings;

    if (settings.hasLocalTapoCredentials) {
      final success = await widget.tapo.setOn(
        ip: settings.tapoIp,
        email: settings.tapoEmail,
        password: settings.tapoPassword,
        on: on,
      );
      if (success) {
        return on
            ? s.t('tapo_local_on_successful')
            : s.t('tapo_local_off_successful');
      }
    }

    final webhookUrl = on ? settings.tapoOnUrl : settings.tapoOffUrl;
    if (webhookUrl.isEmpty) return s.t('webhook_url_missing');

    final code = await widget.webhooks.test(webhookUrl);
    if (code == null) return s.t('webhook_failed');
    if (code == 200) return '${s.t('webhook_successful_prefix')} (HTTP $code)';
    return '${s.t('webhook_failed_with_code_prefix')} (HTTP $code)';
  }

  Future<void> _testOnAction() async {
    if (_testingOn) return;
    setState(() => _testingOn = true);
    try {
      final result = await _executeAction(on: true);
      if (!mounted) return;
      _showResult(result);
    } finally {
      if (mounted) setState(() => _testingOn = false);
    }
  }

  Future<void> _testOffAction() async {
    if (_testingOff) return;
    setState(() => _testingOff = true);
    try {
      final result = await _executeAction(on: false);
      if (!mounted) return;
      _showResult(result);
    } finally {
      if (mounted) setState(() => _testingOff = false);
    }
  }

  void _showResult(String message, {bool? isError}) {
    final success = isError == null
        ? message.toLowerCase().contains('success') ||
            message.toLowerCase().contains('ok') ||
            message.toLowerCase().contains('connected') ||
            message.toLowerCase().contains('riuscito') ||
            message.toLowerCase().contains('connesso')
        : !isError;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.check_circle_outline : Icons.error_outline,
                size: 18,
                color: success ? AppColors.success : AppColors.error,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: AppColors.surfaceElevated,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String? _validateThreshold(String value) {
    final v = int.tryParse(value);
    if (v == null || v < 0 || v > 100) {
      return widget.strings.t('threshold_error');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final settings = widget.settings;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Smart Charging card ──────────────────────────────────────
                SectionCard(
                  title: s.t('automation'),
                  icon: Icons.auto_mode_rounded,
                  isActive: settings.enabled,
                  switchValue: settings.enabled,
                  onSwitchChanged: (v) =>
                      widget.onSettingsChanged(settings.copyWith(enabled: v)),
                  children: [
                    Text('Active window', style: AppTypography.labelLg),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        TimeSelectorTile(
                          label: s.t('start_time'),
                          formattedTime: _fmt(settings.startTime),
                          onTap: () => _selectTime(true),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        TimeSelectorTile(
                          label: s.t('end_time'),
                          formattedTime: _fmt(settings.endTime),
                          onTap: () => _selectTime(false),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Battery thresholds', style: AppTypography.labelLg),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: DebouncedSettingsField(
                            controller: _lowCtrl,
                            label: s.t('low_limit'),
                            prefixIcon: Icons.battery_alert_rounded,
                            keyboardType: TextInputType.number,
                            onChangedDebounced: _onFieldsChanged,
                            validator: _validateThreshold,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: DebouncedSettingsField(
                            controller: _highCtrl,
                            label: s.t('high_limit'),
                            prefixIcon: Icons.battery_charging_full_rounded,
                            keyboardType: TextInputType.number,
                            onChangedDebounced: _onFieldsChanged,
                            validator: _validateThreshold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(s.t('plug_control_actions'), style: AppTypography.labelLg),
                    const SizedBox(height: AppSpacing.sm),
                    _ActionField(
                      controller: _onUrlCtrl,
                      label: settings.useLocalTapo
                          ? s.t('on_webhook_url_fallback')
                          : s.t('on_webhook_url'),
                      icon: Icons.power_settings_new_rounded,
                      iconColor: AppColors.success,
                      isTesting: _testingOn,
                      onTest: _testOnAction,
                      onChanged: _onFieldsChanged,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _ActionField(
                      controller: _offUrlCtrl,
                      label: settings.useLocalTapo
                          ? s.t('off_webhook_url_fallback')
                          : s.t('off_webhook_url'),
                      icon: Icons.power_off_rounded,
                      iconColor: AppColors.error,
                      isTesting: _testingOff,
                      onTest: _testOffAction,
                      onChanged: _onFieldsChanged,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionField extends StatelessWidget {
  const _ActionField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.isTesting,
    required this.onTest,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Color iconColor;
  final bool isTesting;
  final VoidCallback onTest;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return DebouncedSettingsField(
      controller: controller,
      label: label,
      prefixIcon: icon,
      keyboardType: TextInputType.url,
      onChangedDebounced: onChanged,
      suffixIcon: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: isTesting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                icon: Icon(Icons.send_rounded, size: 18, color: iconColor),
                tooltip: 'Test',
                onPressed: onTest,
              ),
      ),
    );
  }
}