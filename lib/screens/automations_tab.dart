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
  // Automation fields
  late final TextEditingController _onUrlCtrl;
  late final TextEditingController _offUrlCtrl;
  late final TextEditingController _lowCtrl;
  late final TextEditingController _highCtrl;

  // Local Tapo fields
  late final TextEditingController _ipCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passwordCtrl;

  bool _testingTapo = false;
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
    _ipCtrl = TextEditingController(text: s.tapoIp);
    _emailCtrl = TextEditingController(text: s.tapoEmail);
    _passwordCtrl = TextEditingController(text: s.tapoPassword);
  }

  @override
  void didUpdateWidget(AutomationsTab old) {
    super.didUpdateWidget(old);
    final s = widget.settings;
    _syncIfChanged(_onUrlCtrl, s.tapoOnUrl);
    _syncIfChanged(_offUrlCtrl, s.tapoOffUrl);
    _syncIfChanged(_lowCtrl, s.lowThreshold.toString());
    _syncIfChanged(_highCtrl, s.highThreshold.toString());
    _syncIfChanged(_ipCtrl, s.tapoIp);
    _syncIfChanged(_emailCtrl, s.tapoEmail);
    _syncIfChanged(_passwordCtrl, s.tapoPassword);
  }

  void _syncIfChanged(TextEditingController c, String value) {
    if (c.text != value) c.text = value;
  }

  @override
  void dispose() {
    for (final c in [
      _onUrlCtrl, _offUrlCtrl, _lowCtrl, _highCtrl,
      _ipCtrl, _emailCtrl, _passwordCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Settings persistence ────────────────────────────────────────────────────

  void _onFieldsChanged() {
    final low = int.tryParse(_lowCtrl.text) ?? widget.settings.lowThreshold;
    final high = int.tryParse(_highCtrl.text) ?? widget.settings.highThreshold;

    widget.onSettingsChanged(widget.settings.copyWith(
      tapoOnUrl: _onUrlCtrl.text,
      tapoOffUrl: _offUrlCtrl.text,
      lowThreshold: low,
      highThreshold: high,
      tapoIp: _ipCtrl.text,
      tapoEmail: _emailCtrl.text,
      tapoPassword: _passwordCtrl.text,
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

  // ── Action execution ────────────────────────────────────────────────────────

  /// Executes the configured ON or OFF action, trying local Tapo first and
  /// falling back to the webhook URL. Returns a user-visible result message.
  Future<String> _executeAction({required bool on}) async {
    final s = widget.strings;
    final settings = widget.settings;
    final action = on ? 'ON' : 'OFF';

    // 1. Try local Tapo if configured.
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
      // Local failed — continue to webhook fallback.
    }

    // 2. Try webhook.
    final webhookUrl = on ? settings.tapoOnUrl : settings.tapoOffUrl;
    if (webhookUrl.isEmpty) {
      return s.t('webhook_url_missing');
    }

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

  Future<void> _testLocalTapo() async {
    if (_testingTapo) return;

    final ip = _ipCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (ip.isEmpty || email.isEmpty || password.isEmpty) {
      _showResult(widget.strings.t('tapo_fields_incomplete'), isError: true);
      return;
    }

    setState(() => _testingTapo = true);
    try {
      final result = await widget.tapo.test(
        ip: ip,
        email: email,
        password: password,
      );
      if (!mounted) return;
      final isSuccess = result.startsWith('Connected');
      _showResult(result, isError: !isSuccess);
    } finally {
      if (mounted) setState(() => _testingTapo = false);
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

  // ── Validators ──────────────────────────────────────────────────────────────

  String? _validateThreshold(String value) {
    final v = int.tryParse(value);
    if (v == null || v < 0 || v > 100) {
      return widget.strings.t('threshold_error');
    }
    return null;
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final settings = widget.settings;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.xs),
                const SizedBox(height: AppSpacing.xxl),

                // ── Smart Charging card ──────────────────────────────────────
                SectionCard(
                  title: s.t('automation'),
                  icon: Icons.auto_mode_rounded,
                  isActive: settings.enabled,
                  switchValue: settings.enabled,
                  onSwitchChanged: (v) =>
                      widget.onSettingsChanged(settings.copyWith(enabled: v)),
                  children: [
                    // Time window
                    Text(
                      'Active window',
                      style: AppTypography.labelLg,
                    ),
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

                    // Thresholds
                    Text(
                      'Battery thresholds',
                      style: AppTypography.labelLg,
                    ),
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

                    // Plug control
                    Text(
                      s.t('plug_control_actions'),
                      style: AppTypography.labelLg,
                    ),
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

                const SizedBox(height: AppSpacing.lg),

                // ── Local Tapo card ──────────────────────────────────────────
                SectionCard(
                  title: s.t('local_tapo_title'),
                  icon: Icons.wifi_tethering_rounded,
                  description: s.t('local_tapo_description'),
                  isActive: settings.useLocalTapo,
                  switchValue: settings.useLocalTapo,
                  onSwitchChanged: (v) => widget.onSettingsChanged(
                    settings.copyWith(useLocalTapo: v),
                  ),
                  children: settings.useLocalTapo
                      ? [
                          DebouncedSettingsField(
                            controller: _ipCtrl,
                            label: s.t('tapo_ip_label'),
                            prefixIcon: Icons.router_rounded,
                            onChangedDebounced: _onFieldsChanged,
                            keyboardType: TextInputType.url,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          DebouncedSettingsField(
                            controller: _emailCtrl,
                            label: s.t('tapo_email_label'),
                            prefixIcon: Icons.email_outlined,
                            onChangedDebounced: _onFieldsChanged,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          DebouncedSettingsField(
                            controller: _passwordCtrl,
                            label: s.t('tapo_password_label'),
                            prefixIcon: Icons.lock_outline_rounded,
                            onChangedDebounced: _onFieldsChanged,
                            obscureText: true,
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _testingTapo ? null : _testLocalTapo,
                              icon: _testingTapo
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.phonelink_ring_rounded),
                              label: Text(s.t('test_local_handshake')),
                            ),
                          ),
                        ]
                      : [],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A URL field with an inline test button.
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