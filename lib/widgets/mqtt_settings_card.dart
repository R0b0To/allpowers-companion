import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../models/mqtt_settings.dart';
import '../services/mqtt_service.dart';
import '../theme/app_theme.dart';
import '../widgets/debounced_settings_field.dart';
import '../widgets/section_card.dart';

/// Self-contained MQTT configuration card, embedded in [AutomationsTab].
///
/// Exposes mode selection (Standalone / Gateway / Client), broker connection
/// details, topic prefix, and a one-shot connection test button.
///
/// The card intentionally matches the visual style of the existing
/// [SectionCard]-based settings in [AutomationsTab] (Local Tapo card, Smart
/// Charging card) so it fits naturally without any custom styling.
class MqttSettingsCard extends StatefulWidget {
  const MqttSettingsCard({
    super.key,
    required this.settings,
    required this.mqtt,
    required this.strings,
    required this.onSettingsChanged,
  });

  final MqttSettings settings;
  final MqttService mqtt;
  final AppStrings strings;
  final ValueChanged<MqttSettings> onSettingsChanged;

  @override
  State<MqttSettingsCard> createState() => _MqttSettingsCardState();
}

class _MqttSettingsCardState extends State<MqttSettingsCard> {
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _topicCtrl;
  late final TextEditingController _clientIdCtrl;

  bool _testing = false;
  bool _obscurePass = true;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _hostCtrl = TextEditingController(text: s.brokerHost);
    _portCtrl = TextEditingController(text: s.port.toString());
    _userCtrl = TextEditingController(text: s.username);
    _passCtrl = TextEditingController(text: s.password);
    _topicCtrl = TextEditingController(text: s.topicPrefix);
    _clientIdCtrl = TextEditingController(text: s.clientId);
  }

  @override
  void didUpdateWidget(MqttSettingsCard old) {
    super.didUpdateWidget(old);
    final s = widget.settings;
    _syncIf(_hostCtrl, s.brokerHost);
    _syncIf(_portCtrl, s.port.toString());
    _syncIf(_userCtrl, s.username);
    _syncIf(_passCtrl, s.password);
    _syncIf(_topicCtrl, s.topicPrefix);
    _syncIf(_clientIdCtrl, s.clientId);
  }

  void _syncIf(TextEditingController c, String v) {
    if (c.text != v) c.text = v;
  }

  @override
  void dispose() {
    for (final c in [
      _hostCtrl, _portCtrl, _userCtrl, _passCtrl, _topicCtrl, _clientIdCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Settings helpers ──────────────────────────────────────────────────────

  void _persist() {
    widget.onSettingsChanged(widget.settings.copyWith(
      brokerHost: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? widget.settings.port,
      username: _userCtrl.text.trim(),
      password: _passCtrl.text,
      topicPrefix: _topicCtrl.text.trim(),
      clientId: _clientIdCtrl.text.trim(),
    ));
  }

  void _setMode(AppMode mode) {
    widget.onSettingsChanged(widget.settings.copyWith(mode: mode));
  }

  void _setTls(bool value) {
    // Default port to 8883 when enabling TLS, back to 1883 when disabling.
    final port = value ? 8883 : 1883;
    _portCtrl.text = port.toString();
    widget.onSettingsChanged(
        widget.settings.copyWith(useTls: value, port: port));
  }

  Future<void> _testConnection() async {
    if (_testing) return;
    _persist(); // Flush text fields before testing.
    setState(() => _testing = true);
    try {
      final result = await widget.mqtt.testConnection(widget.settings.copyWith(
        brokerHost: _hostCtrl.text.trim(),
        port: int.tryParse(_portCtrl.text.trim()) ?? widget.settings.port,
        username: _userCtrl.text.trim(),
        password: _passCtrl.text,
      ));
      if (!mounted) return;
      _showSnack(result,
          success: result.contains('✓') || result.contains('Connected'));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _showSnack(String message, {bool success = true}) {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          Icon(
            success ? Icons.check_circle_outline : Icons.error_outline,
            size: 18,
            color: success ? AppColors.success : theme.colorScheme.error,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message)),
        ]),
        // Removed explicit AppColors.surfaceElevated to match the globally
        // registered snackBarTheme behavior configured in theme.dart
        duration: const Duration(seconds: 4),
      ));
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    final settings = widget.settings;
    final mqtt = widget.mqtt;
    final isActive = settings.mode != AppMode.standalone;
    final theme = Theme.of(context);

    return SectionCard(
      title: s.t('mqtt_section_title'),
      icon: Icons.cloud_sync_rounded,
      isActive: isActive,
      children: [
        // ── Mode selector ──────────────────────────────────────────────────
        Text(s.t('mqtt_mode_label'), style: AppTypography.labelLg),
        const SizedBox(height: AppSpacing.sm),
        _ModeSelector(
          mode: settings.mode,
          strings: s,
          onChanged: _setMode,
        ),

        if (settings.mode != AppMode.standalone) ...[
          const SizedBox(height: AppSpacing.lg),

          // ── Mode description ───────────────────────────────────────────
          _ModeDescription(mode: settings.mode, strings: s),
          const SizedBox(height: AppSpacing.lg),

          // ── Connection status badge ─────────────────────────────────────
          AnimatedBuilder(
            animation: mqtt,
            builder: (_, __) => _ConnectionBadge(mqtt: mqtt, strings: s),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Broker host ────────────────────────────────────────────────
          DebouncedSettingsField(
            controller: _hostCtrl,
            label: s.t('mqtt_broker_host'),
            prefixIcon: Icons.dns_rounded,
            onChangedDebounced: _persist,
            keyboardType: TextInputType.url,
            hint: 'broker.hivemq.com',
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Port + TLS row ─────────────────────────────────────────────
          Row(
            children: [
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _portCtrl,
                  onChanged: (_) => _persist(),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: AppTypography.bodyLg,
                  decoration: InputDecoration(
                    labelText: s.t('mqtt_port'),
                    prefixIcon:
                        const Icon(Icons.electrical_services_rounded, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Row(
                  children: [
                    Switch(
                      value: settings.useTls,
                      onChanged: _setTls,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(s.t('mqtt_use_tls'),
                        style: AppTypography.bodyMd),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Credentials ────────────────────────────────────────────────
          DebouncedSettingsField(
            controller: _userCtrl,
            label: s.t('mqtt_username'),
            prefixIcon: Icons.person_outline_rounded,
            onChangedDebounced: _persist,
          ),
          const SizedBox(height: AppSpacing.sm),
          DebouncedSettingsField(
            controller: _passCtrl,
            label: s.t('mqtt_password'),
            prefixIcon: Icons.lock_outline_rounded,
            obscureText: _obscurePass,
            onChangedDebounced: _persist,
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePass
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
              ),
              onPressed: () =>
                  setState(() => _obscurePass = !_obscurePass),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Topic prefix ───────────────────────────────────────────────
          DebouncedSettingsField(
            controller: _topicCtrl,
            label: s.t('mqtt_topic_prefix'),
            prefixIcon: Icons.topic_rounded,
            onChangedDebounced: _persist,
            hint: 'ap/garage',
          ),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              '${s.t('mqtt_status_topic')}: ${settings.topicPrefix}/status\n'
              '${s.t('mqtt_cmd_topic')}: ${settings.topicPrefix}/cmd/+',
              style: AppTypography.labelSm,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Client ID (optional) ───────────────────────────────────────
          DebouncedSettingsField(
            controller: _clientIdCtrl,
            label: s.t('mqtt_client_id'),
            prefixIcon: Icons.fingerprint_rounded,
            onChangedDebounced: _persist,
            hint: s.t('mqtt_client_id_hint'),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Test button ────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _testing ? null : _testConnection,
              icon: _testing
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : const Icon(Icons.wifi_find_rounded),
              label: Text(s.t('mqtt_test_connection')),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Mode selector ─────────────────────────────────────────────────────────────

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.mode,
    required this.strings,
    required this.onChanged,
  });

  final AppMode mode;
  final AppStrings strings;
  final ValueChanged<AppMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: AppMode.values.map((m) {
        final selected = m == mode;
        final (icon, color) = switch (m) {
          AppMode.standalone => (Icons.bluetooth_rounded, AppColors.teal),
          AppMode.gateway => (Icons.router_rounded, AppColors.info),
          AppMode.client => (Icons.phone_android_rounded, AppColors.success),
        };
        return GestureDetector(
          onTap: () => onChanged(m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: selected
                  ? color.withValues(alpha:0.08)
                  : theme.colorScheme.surfaceContainer,
              borderRadius: AppRadius.mdBR,
              border: Border.all(
                color: selected
                    ? color.withValues(alpha:0.4)
                    : theme.colorScheme.outline,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: selected
                        ? color.withValues(alpha:0.15)
                        : theme.colorScheme.surface,
                    borderRadius: AppRadius.smBR,
                  ),
                  child: Icon(
                    icon,
                    size: 16,
                    color: selected
                        ? color
                        : theme.colorScheme.onSurfaceVariant.withValues(alpha:0.6),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.t('mqtt_mode_${m.name}'),
                        style: AppTypography.headingSm.copyWith(
                          color: selected
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        strings.t('mqtt_mode_${m.name}_sub'),
                        style: AppTypography.bodySm.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha:0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded,
                      size: 18, color: color),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Mode description banner ───────────────────────────────────────────────────

class _ModeDescription extends StatelessWidget {
  const _ModeDescription({required this.mode, required this.strings});
  final AppMode mode;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (mode) {
      AppMode.gateway => (AppColors.info, Icons.router_rounded),
      AppMode.client => (AppColors.success, Icons.phone_android_rounded),
      AppMode.standalone => (AppColors.teal, Icons.bluetooth_rounded),
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.06),
        borderRadius: AppRadius.mdBR,
        border: Border.all(color: color.withValues(alpha:0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              strings.t('mqtt_mode_${mode.name}_desc'),
              style:
                  AppTypography.bodyMd.copyWith(color: color.withValues(alpha:0.9)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Connection status badge ───────────────────────────────────────────────────

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.mqtt, required this.strings});
  final MqttService mqtt;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, label, icon) = mqtt.isConnecting
        ? (AppColors.warning, strings.t('mqtt_connecting'),
            Icons.pending_rounded)
        : mqtt.isConnected
            ? (AppColors.success, strings.t('mqtt_connected'),
                Icons.cloud_done_rounded)
            : (theme.colorScheme.error,
                mqtt.lastError ?? strings.t('mqtt_disconnected'),
                Icons.cloud_off_rounded);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.08),
        borderRadius: AppRadius.mdBR,
        border: Border.all(color: color.withValues(alpha:0.3)),
      ),
      child: Row(
        children: [
          if (mqtt.isConnecting)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2, 
                color: color,
              ),
            )
          else
            Icon(icon, size: 14, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(label,
                style: AppTypography.bodyMd.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}