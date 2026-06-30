import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Tappable card representing a single outlet (USB / AC / DC).
///
/// ## Layout
/// By default the card wraps itself in an [Expanded] widget so it fills
/// its share of a [Row]. Set [expanded] to `false` when the caller
/// supplies its own [Expanded] (e.g. `DevicesTab`, where the card is
/// one child of an [Expanded] alongside an info panel). This eliminates
/// the need for a parallel copy of this widget with the Expanded stripped.
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
    this.expanded = true,
  });

  final IconData icon;
  final String title;
  final String activeLabel;
  final String disabledLabel;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;
  final bool enabled;

  /// When `true` (default) the card wraps itself in [Expanded].
  /// Set to `false` when the parent already provides an [Expanded] wrapper.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final content = Semantics(
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
                ? activeColor.withValues(alpha: 0.08)
                : theme.colorScheme.surfaceContainerLow,
            borderRadius: AppRadius.lgBR,
            border: Border.all(
              color: isActive ? activeColor : theme.colorScheme.outline,
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
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.8),
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
    );

    return expanded ? Expanded(child: content) : content;
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
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isActive
            ? activeColor.withValues(alpha: 0.15)
            : theme.colorScheme.surfaceContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: 20,
        color: isActive
            ? activeColor
            : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isActive
            ? color.withValues(alpha: 0.15)
            : theme.colorScheme.surfaceContainer,
        borderRadius: AppRadius.xsBR,
      ),
      child: Text(
        label,
        style: AppTypography.labelSm.copyWith(
          color: isActive
              ? color
              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          fontSize: 9,
        ),
      ),
    );
  }
}