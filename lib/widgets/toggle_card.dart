import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Tappable card representing a single outlet (USB / AC / DC).
///
/// Provides haptic feedback on tap and uses [Semantics] so screen readers
/// can announce the outlet name and current state.
class ToggleCard extends StatelessWidget {
  const ToggleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
    this.activeLabel = 'Active',
    this.disabledLabel = 'Disabled',
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String activeLabel;
  final String disabledLabel;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Semantics(
        label: '$title outlet',
        value: isActive ? activeLabel : disabledLabel,
        button: true,
        child: GestureDetector(
          onTap: enabled
              ? () {
                  HapticFeedback.selectionClick();
                  onTap();
                }
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.lg,
              horizontal: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? activeColor.withOpacity(0.08)
                  : AppColors.surface,
              borderRadius: AppRadius.lgBR,
              border: Border.all(
                color: isActive ? activeColor : AppColors.border,
                width: isActive ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _OutletIcon(
                  icon: icon,
                  isActive: isActive,
                  activeColor: activeColor,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTypography.labelMd.copyWith(
                    color: isActive
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                _StatusPill(
                  label: isActive ? activeLabel : disabledLabel,
                  isActive: isActive,
                  color: activeColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OutletIcon extends StatelessWidget {
  const _OutletIcon({
    required this.icon,
    required this.isActive,
    required this.activeColor,
  });

  final IconData icon;
  final bool isActive;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isActive
            ? activeColor.withOpacity(0.15)
            : AppColors.surfaceElevated,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: 20,
        color: isActive ? activeColor : AppColors.textTertiary,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.isActive,
    required this.color,
  });

  final String label;
  final bool isActive;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isActive ? color.withOpacity(0.15) : AppColors.surfaceElevated,
        borderRadius: AppRadius.xsBR,
      ),
      child: Text(
        label,
        style: AppTypography.labelSm.copyWith(
          color: isActive ? color : AppColors.textTertiary,
          fontSize: 9,
        ),
      ),
    );
  }
}