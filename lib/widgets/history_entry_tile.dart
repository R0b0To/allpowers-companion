import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/automation_history_entry.dart';
import '../theme/app_theme.dart';

/// A single row in the automation history list: action, timestamp,
/// the battery level that triggered it, and which path carried it out.
class HistoryEntryTile extends StatelessWidget {
  const HistoryEntryTile({
    super.key,
    required this.entry,
    required this.strings,
  });

  final AutomationHistoryEntry entry;
  final AppStrings strings;

  bool get _isOn => entry.action == HistoryAction.turnOn;

  Color get _accentColor {
    if (!entry.success) return AppColors.error;
    return _isOn ? AppColors.success : AppColors.textSecondary;
  }

  IconData get _methodIcon {
    switch (entry.method) {
      case ActivationMethod.localTapo:
        return Icons.wifi_tethering_rounded;
      case ActivationMethod.webhook:
        return Icons.link_rounded;
      case ActivationMethod.none:
        return Icons.block_rounded;
    }
  }

  String get _methodLabel {
    switch (entry.method) {
      case ActivationMethod.localTapo:
        return strings.t('history_method_local_tapo');
      case ActivationMethod.webhook:
        return strings.t('history_method_webhook');
      case ActivationMethod.none:
        return strings.t('history_method_none');
    }
  }

  String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    final date = '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
    final time = '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return '$date · $time';
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accentColor;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.mdBR,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: AppRadius.smBR,
            ),
            child: Icon(
              _isOn ? Icons.power_settings_new_rounded : Icons.power_off_rounded,
              size: 18,
              color: accent,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isOn
                            ? strings.t('history_action_on')
                            : strings.t('history_action_off'),
                        style: AppTypography.headingSm,
                      ),
                    ),
                    _StatusChip(success: entry.success, strings: strings),
                  ],
                ),
                const SizedBox(height: 2),
                Text(_formatTimestamp(entry.timestamp), style: AppTypography.labelSm),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    const Icon(
                      Icons.battery_std_rounded,
                      size: 12,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text('${entry.batteryLevel}%', style: AppTypography.bodySm),
                    const SizedBox(width: AppSpacing.md),
                    Icon(_methodIcon, size: 12, color: AppColors.textTertiary),
                    const SizedBox(width: 4),
                    Text(_methodLabel, style: AppTypography.bodySm),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.success, required this.strings});

  final bool success;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final color = success ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: AppRadius.xsBR,
      ),
      child: Text(
        success ? strings.t('history_success') : strings.t('history_failed'),
        style: AppTypography.labelSm.copyWith(color: color, fontSize: 9),
      ),
    );
  }
}