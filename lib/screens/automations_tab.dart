import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/automation_flow.dart';
import '../models/automation_settings.dart';
import '../theme/app_theme.dart';
import 'flow_editor_screen.dart';

/// Shows the list of automation flows and lets users add, toggle, and delete them.
///
/// Tapo credentials and MQTT configuration live in [SettingsTab].
/// Each flow's internal steps (outlets, webhooks, waits) are edited in
/// [FlowEditorScreen].
class AutomationsTab extends StatelessWidget {
  const AutomationsTab({
    super.key,
    required this.flows,
    required this.settings,
    required this.strings,
    required this.onFlowsChanged,
    this.isClientMode = false,
  });

  final List<AutomationFlow> flows;
  final AutomationSettings settings;
  final AppStrings strings;
  final ValueChanged<List<AutomationFlow>> onFlowsChanged;
  final bool isClientMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      // Let the Scaffold fall back to the custom background configured globally
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.t('tab_automations'),
                      style: AppTypography.displaySm,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Custom sequences triggered by battery events.',
                      style: AppTypography.bodyMd,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (isClientMode) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, 
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.infoSurface,
                          borderRadius: AppRadius.mdBR,
                          border: Border.all(
                            color: AppColors.info.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.sync_rounded,
                              size: 14, 
                              color: AppColors.info,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'Automations sync to the gateway and run there. '
                                'Changes publish automatically when connected.',
                                style: AppTypography.labelSm.copyWith(
                                  color: AppColors.info,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (flows.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(
                  onAddBlank: () => _openEditor(context, null),
                  onAddTemplates: () => _addTemplates(context),
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
                  itemCount: flows.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) => _FlowCard(
                    flow: flows[i],
                    onTap: () => _openEditor(context, flows[i]),
                    onToggle: (v) => _toggleFlow(flows[i], v),
                    onDelete: () => _deleteFlow(context, flows[i]),
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: flows.isEmpty
          ? null
          : FloatingActionButton(
              onPressed: () => _openEditor(context, null),
              // Leverages theme color scheme mapping
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              tooltip: 'New automation',
              child: const Icon(Icons.add_rounded),
            ),
    );
  }

  Future<void> _openEditor(
      BuildContext context, AutomationFlow? existing) async {
    final result = await Navigator.of(context).push<AutomationFlow>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            FlowEditorScreen(flow: existing, settings: settings),
      ),
    );
    if (result == null) return;

    if (existing == null) {
      onFlowsChanged([...flows, result]);
    } else {
      onFlowsChanged(
          flows.map((f) => f.id == result.id ? result : f).toList());
    }
  }

  void _toggleFlow(AutomationFlow flow, bool enabled) {
    onFlowsChanged(flows
        .map((f) => f.id == flow.id ? f.copyWith(enabled: enabled) : f)
        .toList());
  }

  Future<void> _deleteFlow(
      BuildContext context, AutomationFlow flow) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        // Removed custom shape and color parameters because they are now
        // globally applied and resolved via your dark ThemeData.dialogTheme
        title: Text(
          'Delete "${flow.name}"?',
          style: AppTypography.headingMd,
        ),
        content: Text(
          'This automation will be permanently removed.',
          style: AppTypography.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: AppTypography.headingSm.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Delete',
              style: AppTypography.headingSm.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onFlowsChanged(flows.where((f) => f.id != flow.id).toList());
    }
  }

  void _addTemplates(BuildContext context) {
    onFlowsChanged([...flows, ...buildDefaultFlows()]);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        content: Text('2 starter automations added — tap to customise'),
      ));
  }
}

// ── Flow card ─────────────────────────────────────────────────────────────────

class _FlowCard extends StatelessWidget {
  const _FlowCard({
    required this.flow,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  final AutomationFlow flow;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  String get _triggerLine {
    final t = flow.trigger;
    final pct = t.type == FlowTriggerType.batteryFallsBelow
        ? 'Falls below ${t.threshold}%'
        : 'Rises above ${t.threshold}%';
    if (!t.hasWindow) return pct;
    String fmt(TimeOfDay td) =>
        '${td.hour.toString().padLeft(2, '0')}:${td.minute.toString().padLeft(2, '0')}';
    return '$pct  ·  ${fmt(t.windowStart!)}–${fmt(t.windowEnd!)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey(flow.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: AppRadius.lgBR,
        ),
        child: Icon(
          Icons.delete_outline_rounded, 
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false; // Handle state modifications locally
      },
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgBR,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: AppRadius.lgBR,
            border: Border.all(
              color: flow.enabled
                  ? theme.colorScheme.primary.withOpacity(0.35)
                  : theme.colorScheme.outline,
              width: flow.enabled ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: flow.enabled
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(flow.name, style: AppTypography.headingSm),
                    const SizedBox(height: 2),
                    Text(
                      _triggerLine, 
                      style: AppTypography.bodySm.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _StepCountPill(count: flow.actions.length),
                  ],
                ),
              ),
              Switch(value: flow.enabled, onChanged: onToggle),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepCountPill extends StatelessWidget {
  const _StepCountPill({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: AppRadius.xsBR,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.playlist_play_rounded,
            size: 10, 
            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
          ),
          const SizedBox(width: 3),
          Text(
            '$count step${count == 1 ? '' : 's'}',
            style: AppTypography.labelSm.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onAddBlank, 
    required this.onAddTemplates,
  });
  
  final VoidCallback onAddBlank;
  final VoidCallback onAddTemplates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_mode_rounded,
              size: 48, 
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No automations yet', style: AppTypography.headingMd),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Build custom step sequences or start from the charging template.',
              style: AppTypography.bodyMd,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onAddTemplates,
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: const Text('Use charging templates'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onAddBlank,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Build from scratch'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}