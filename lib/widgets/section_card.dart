import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A titled section card with an optional toggle switch.
///
/// Used throughout the Automations tab to group related settings.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.description,
    this.isActive = false,
    this.switchValue,
    this.onSwitchChanged,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final String? description;
  final bool isActive;
  final bool? switchValue;
  final ValueChanged<bool>? onSwitchChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.lgBR,
        border: Border.all(
          color: isActive
              ? theme.colorScheme.primary.withOpacity(0.4)
              : theme.colorScheme.outline,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                _IconBadge(icon: icon, isActive: isActive),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(title, style: AppTypography.headingMd),
                ),
                if (switchValue != null && onSwitchChanged != null)
                  Switch(
                    value: switchValue!,
                    onChanged: onSwitchChanged,
                  )
                else if (trailing != null)
                  trailing!,
              ],
            ),
            if (description != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                description!, 
                style: AppTypography.bodyMd.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                ),
              ),
            ],
            if (children.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.lg),
              ...children,
            ],
          ],
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.isActive});

  final IconData icon;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainer,
        borderRadius: AppRadius.smBR,
      ),
      child: Icon(
        icon,
        size: 18,
        color: isActive 
            ? theme.colorScheme.primary 
            : theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
      ),
    );
  }
}