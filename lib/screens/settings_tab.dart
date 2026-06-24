import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../models/automation_settings.dart';
import '../models/mqtt_settings.dart';
import '../services/mqtt_service.dart';
import '../services/tapo_service.dart';
import '../theme/app_theme.dart';
import '../widgets/debounced_settings_field.dart';
import '../widgets/mqtt_settings_card.dart';
import '../widgets/section_card.dart';

/// The 5th bottom navigation tab for global system, MQTT and Tapo settings.
class SettingsTab extends StatefulWidget {
  const SettingsTab({
    super.key,
    required this.settings,
    required this.mqttSettings,
    required this.mqtt,
    required this.tapo,
    required this.strings,
    required this.onSettingsChanged,
    required this.onMqttSettingsChanged,
  });

  final AutomationSettings settings;
  final MqttSettings mqttSettings;
  final MqttService mqtt;
  final TapoService tapo;
  final AppStrings strings;
  final ValueChanged<AutomationSettings> onSettingsChanged;
  final ValueChanged<MqttSettings> onMqttSettingsChanged;

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late final TextEditingController _ipCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passwordCtrl;

  bool _testingTapo = false;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _ipCtrl = TextEditingController(text: s.tapoIp);
    _emailCtrl = TextEditingController(text: s.tapoEmail);
    _passwordCtrl = TextEditingController(text: s.tapoPassword);
  }

  @override
  void didUpdateWidget(SettingsTab old) {
    super.didUpdateWidget(old);
    final s = widget.settings;
    _syncIfChanged(_ipCtrl, s.tapoIp);
    _syncIfChanged(_emailCtrl, s.tapoEmail);
    _syncIfChanged(_passwordCtrl, s.tapoPassword);
  }

  void _syncIfChanged(TextEditingController c, String value) {
    if (c.text != value) c.text = value;
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _onTapoFieldsChanged() {
    widget.onSettingsChanged(widget.settings.copyWith(
      tapoIp: _ipCtrl.text.trim(),
      tapoEmail: _emailCtrl.text.trim(),
      tapoPassword: _passwordCtrl.text,
    ));
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

  void _showResult(String message, {bool isError = false}) {
    final success = !isError;
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
                const SizedBox(height: AppSpacing.md),
                
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
                            onChangedDebounced: _onTapoFieldsChanged,
                            keyboardType: TextInputType.url,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          DebouncedSettingsField(
                            controller: _emailCtrl,
                            label: s.t('tapo_email_label'),
                            prefixIcon: Icons.email_outlined,
                            onChangedDebounced: _onTapoFieldsChanged,
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          DebouncedSettingsField(
                            controller: _passwordCtrl,
                            label: s.t('tapo_password_label'),
                            prefixIcon: Icons.lock_outline_rounded,
                            onChangedDebounced: _onTapoFieldsChanged,
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
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.phonelink_ring_rounded),
                              label: Text(s.t('test_local_handshake')),
                            ),
                          ),
                        ]
                      : [],
                ),

                const SizedBox(height: AppSpacing.lg),

                // ── Remote Access / MQTT card ─────────────────────────────────
                MqttSettingsCard(
                  settings: widget.mqttSettings,
                  mqtt: widget.mqtt,
                  strings: s,
                  onSettingsChanged: widget.onMqttSettingsChanged,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}