import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum BannerVariant { info, success, warning, error }

/// An inline banner for displaying contextual feedback without a snackbar.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.message,
    this.variant = BannerVariant.info,
    this.onDismiss,
  });

  final String message;
  final BannerVariant variant;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Maps variants directly to M3 ColorScheme properties for standard systems,
    // and falls back to semantic telemetry values for custom diagnostic states.
    final (color, surface, icon) = switch (variant) {
      BannerVariant.info => (
          AppColors.info, 
          AppColors.infoSurface, 
          Icons.info_outline,
        ),
      BannerVariant.success => (
          AppColors.success, 
          AppColors.successSurface, 
          Icons.check_circle_outline,
        ),
      BannerVariant.warning => (
          AppColors.warning, 
          AppColors.warningSurface, 
          Icons.warning_amber_outlined,
        ),
      BannerVariant.error => (
          theme.colorScheme.error, 
          theme.colorScheme.errorContainer, 
          Icons.error_outline,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: AppRadius.mdBR,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodyMd.copyWith(color: color),
            ),
          ),
          if (onDismiss != null) ...[
            const SizedBox(width: AppSpacing.sm),
            GestureDetector(
              onTap: onDismiss,
              child: Icon(
                Icons.close, 
                size: 16, 
                color: color.withOpacity(0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}