import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/automation_history_entry.dart';
import '../theme/app_theme.dart';

/// A single row in the automation history list.
class HistoryEntryTile extends StatelessWidget {
  const HistoryEntryTile({
    super.key,
    required this.entry,
    required this.strings,
  });

  final AutomationHistoryEntry entry;
  final AppStrings strings;

  Color _accentColor(BuildContext context) {
    final theme = Theme.of(context);
    if (!entry.success) return theme.colorScheme.error;
    return switch (entry.action) {
      HistoryAction.tapoOn || HistoryAction.turnOn => AppColors.success,
      HistoryAction.tapoOff || HistoryAction.turnOff => AppColors.textSecondary,
      HistoryAction.webhookFired => AppColors.info,
      HistoryAction.outletToggled => AppColors.teal,
    };
  }

  IconData get _actionIcon => switch (entry.action) {
        HistoryAction.tapoOn || HistoryAction.turnOn =>
          Icons.power_settings_new_rounded,
        HistoryAction.tapoOff || HistoryAction.turnOff =>
          Icons.power_off_rounded,
        HistoryAction.webhookFired => Icons.link_rounded,
        HistoryAction.outletToggled => Icons.bolt_rounded,
      };

  String _actionLabel(BuildContext context) => switch (entry.action) {
        HistoryAction.tapoOn => 'Tapo turned ON',
        HistoryAction.tapoOff => 'Tapo turned OFF',
        HistoryAction.turnOn => strings.t('history_action_on'),
        HistoryAction.turnOff => strings.t('history_action_off'),
        HistoryAction.webhookFired => 'Webhook fired',
        HistoryAction.outletToggled =>
          'Outlet ${entry.deviceName} toggled',
      };

  IconData get _methodIcon => switch (entry.method) {
        ActivationMethod.localTapo => Icons.wifi_tethering_rounded,
        ActivationMethod.webhook => Icons.link_rounded,
        ActivationMethod.bleOutlet => Icons.bluetooth_rounded,
        ActivationMethod.none => Icons.block_rounded,
      };

  String _methodLabel(BuildContext context) => switch (entry.method) {
        ActivationMethod.localTapo => strings.t('history_method_local_tapo'),
        ActivationMethod.webhook => strings.t('history_method_webhook'),
        ActivationMethod.bleOutlet => 'BLE outlet',
        ActivationMethod.none => strings.t('history_method_none'),
      };

  String _formatTimestamp(DateTime dt) {
    final local = dt.toLocal();
    final date =
        '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date · $time';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accentColor(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.mdBR,
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon badge
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha:0.12),
              borderRadius: AppRadius.smBR,
            ),
            child: Icon(_actionIcon, size: 18, color: accent),
          ),
          const SizedBox(width: AppSpacing.md),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Action label + status chip
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _actionLabel(context),
                        style: AppTypography.headingSm,
                      ),
                    ),
                    _StatusChip(success: entry.success, strings: strings),
                  ],
                ),
                const SizedBox(height: 2),

                // Timestamp
                Text(_formatTimestamp(entry.timestamp),
                    style: AppTypography.labelSm),

                const SizedBox(height: AppSpacing.sm),

                // Meta row: battery + method + device name
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: 4,
                  children: [
                    // Battery
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.battery_std_rounded,
                            size: 12,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha:0.6)),
                        const SizedBox(width: 4),
                        Text('${entry.batteryLevel}%',
                            style: AppTypography.bodySm.copyWith(
                                color: theme.colorScheme.onSurface)),
                      ],
                    ),
                    // Method
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_methodIcon,
                            size: 12,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha:0.6)),
                        const SizedBox(width: 4),
                        Text(_methodLabel(context),
                            style: AppTypography.bodySm.copyWith(
                                color: theme.colorScheme.onSurface)),
                      ],
                    ),
                    // Device name (Tapo)
                    if (entry.deviceName.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.electrical_services_rounded,
                              size: 12,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha:0.6)),
                          const SizedBox(width: 4),
                          Text(entry.deviceName,
                              style: AppTypography.bodySm.copyWith(
                                  color: theme.colorScheme.onSurface)),
                        ],
                      ),
                  ],
                ),

                // Flow name pill
                if (entry.flowName.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainer,
                      borderRadius: AppRadius.xsBR,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_mode_rounded,
                            size: 10,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha:0.6)),
                        const SizedBox(width: 3),
                        Text(
                          entry.flowName,
                          style: AppTypography.labelSm.copyWith(
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha:0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
    final theme = Theme.of(context);
    final color = success ? AppColors.success : theme.colorScheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.12),
        borderRadius: AppRadius.xsBR,
      ),
      child: Text(
        success
            ? strings.t('history_success')
            : strings.t('history_failed'),
        style:
            AppTypography.labelSm.copyWith(color: color, fontSize: 9),
      ),
    );
  }
}