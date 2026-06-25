import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A tappable tile displaying a time label and formatted time value.
/// Used for automation window start/end time pickers.
class TimeSelectorTile extends StatelessWidget {
  const TimeSelectorTile({
    super.key,
    required this.label,
    required this.formattedTime,
    required this.onTap,
  });

  final String label;
  final String formattedTime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Semantics(
        label: '$label: $formattedTime',
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.mdBR,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: AppRadius.mdBR,
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.schedule_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: AppTypography.labelSm),
                      const SizedBox(height: 2),
                      Text(
                        formattedTime,
                        style: AppTypography.headingSm.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}