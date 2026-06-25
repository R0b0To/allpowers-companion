import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/history_service.dart';
import '../theme/app_theme.dart';
import '../widgets/history_entry_tile.dart';

/// Displays a log of every automation ON/OFF action: when it ran, the
/// battery level that triggered it, whether it succeeded, and which path
/// (local Tapo / webhook / none) carried it out.
///
/// Receives [HistoryService] from [MainShell] — creates nothing itself,
/// matching the pattern used by [ControlTab] and [AutomationsTab].
class HistoryTab extends StatelessWidget {
  const HistoryTab({
    super.key,
    required this.history,
    required this.strings,
  });

  final HistoryService history;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: history,
      builder: (context, _) => SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    if (!history.isLoaded) {
      return Center(
        child: CircularProgressIndicator(
          color: theme.colorScheme.primary,
        ),
      );
    }

    final entries = history.entries;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entries.isNotEmpty)
                  IconButton(
                    onPressed: () => _confirmClear(context),
                    tooltip: strings.t('clear_history'),
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (entries.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxxl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 48,
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      strings.t('no_history'),
                      style: AppTypography.bodyMd,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            sliver: SliverList.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) => HistoryEntryTile(
                entry: entries[index],
                strings: strings,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        // Shape and background removed to let this card inherit the globally 
        // registered dialogTheme configuration inside theme.dart automatically
        title: Text(strings.t('clear_history'), style: AppTypography.headingMd),
        content: Text(strings.t('clear_history_confirm'), style: AppTypography.bodyMd),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              strings.t('cancel'),
              style: AppTypography.headingSm.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              strings.t('clear_history'),
              style: AppTypography.headingSm.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) await history.clear();
  }
}