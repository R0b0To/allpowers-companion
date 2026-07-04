import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/automation_flow.dart';
import '../models/automation_settings.dart';
import '../models/tapo_device.dart';
import '../services/history_service.dart';
import '../theme/app_theme.dart';
import '../widgets/history_entry_tile.dart';
import 'flow_editor_screen.dart';

class AutomationsTab extends StatefulWidget {
  const AutomationsTab({
    super.key,
    required this.flows,
    required this.settings,
    required this.strings,
    required this.tapoDevices,
    required this.history,
    required this.onFlowsChanged,
    this.isClientMode = false,
  });

  final List<AutomationFlow> flows;
  final AutomationSettings settings;
  final AppStrings strings;
  final List<TapoDevice> tapoDevices;
  final HistoryService history;
  final ValueChanged<List<AutomationFlow>> onFlowsChanged;
  final bool isClientMode;

  @override
  State<AutomationsTab> createState() => _AutomationsTabState();
}

class _AutomationsTabState extends State<AutomationsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _isFlowsTab => _tabController.index == 0;

  // ── Flow actions ───────────────────────────────────────────────────────────

  Future<void> _openEditor(AutomationFlow? existing) async {
    final result = await Navigator.of(context).push<AutomationFlow>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FlowEditorScreen(
          flow: existing,
          settings: widget.settings,
          tapoDevices: widget.tapoDevices,
        ),
      ),
    );
    if (result == null) return;
    if (existing == null) {
      widget.onFlowsChanged([...widget.flows, result]);
    } else {
      widget.onFlowsChanged(
        widget.flows.map((f) => f.id == result.id ? result : f).toList(),
      );
    }
  }

  void _toggleFlow(AutomationFlow flow, bool enabled) {
    widget.onFlowsChanged(
      widget.flows
          .map((f) => f.id == flow.id ? f.copyWith(enabled: enabled) : f)
          .toList(),
    );
  }

  Future<void> _deleteFlow(AutomationFlow flow) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${flow.name}"?', style: AppTypography.headingMd),
        content: Text(
          'This automation will be permanently removed.',
          style: AppTypography.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              widget.strings.t('cancel'),
              style: AppTypography.headingSm.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha:0.7),
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
      widget.onFlowsChanged(
          widget.flows.where((f) => f.id != flow.id).toList());
    }
  }

  void _addTemplates() {
    widget.onFlowsChanged([...widget.flows, ...buildDefaultFlows()]);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(
        content: Text('2 starter automations added — tap to customise'),
      ));
  }

  // ── History actions ────────────────────────────────────────────────────────

  Future<void> _confirmHistoryClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          widget.strings.t('clear_history'),
          style: AppTypography.headingMd,
        ),
        content: Text(
          widget.strings.t('clear_history_confirm'),
          style: AppTypography.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              widget.strings.t('cancel'),
              style: AppTypography.headingSm.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha:0.7),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              widget.strings.t('clear_history'),
              style: AppTypography.headingSm.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.history.clear();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.strings;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Shared header — title and description change with active tab ──
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, 0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          _isFlowsTab
                              ? s.t('tab_automations')
                              : s.t('tab_history'),
                          style: AppTypography.displaySm,
                        ),
                      ),
                      // Trailing action placeholder to avoid horizontal and vertical shifts
                      AnimatedBuilder(
                        animation: widget.history,
                        builder: (_, __) {
                          final showClearButton = !_isFlowsTab && widget.history.entries.isNotEmpty;
                          return Visibility(
                            visible: showClearButton,
                            maintainSize: true,
                            maintainAnimation: true,
                            maintainState: true,
                            child: IconButton(
                              onPressed: _confirmHistoryClear,
                              tooltip: s.t('clear_history'),
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _isFlowsTab
                        ? 'Custom sequences triggered by battery or plug events.'
                        : s.t('history_description'),
                    style: AppTypography.bodyMd,
                  ),
                  // Note: Client banner removed from here to prevent tab-switching jumps.
                  const SizedBox(height: AppSpacing.md),
                ],
              ),
            ),

            // ── Tab bar ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: TabBar(
                controller: _tabController,
                labelStyle: AppTypography.headingSm,
                unselectedLabelStyle: AppTypography.bodyMd,
                indicatorColor: theme.colorScheme.primary,
                labelColor: theme.colorScheme.primary,
                unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                dividerColor: theme.colorScheme.outlineVariant,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_mode_rounded, size: 14),
                        const SizedBox(width: AppSpacing.xs),
                        Text(s.t('tab_automations')),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.history_rounded, size: 14),
                        const SizedBox(width: AppSpacing.xs),
                        Text(s.t('tab_history')),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Tab content ───────────────────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _FlowsView(
                    flows: widget.flows,
                    strings: s,
                    tapoDevices: widget.tapoDevices,
                    onAddBlank: () => _openEditor(null),
                    onAddTemplates: _addTemplates,
                    onTap: _openEditor,
                    onToggle: _toggleFlow,
                    onDelete: _deleteFlow,
                    isClientMode: widget.isClientMode,
                  ),
                  _HistoryView(
                    history: widget.history,
                    strings: s,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isFlowsTab && widget.flows.isNotEmpty
          ? FloatingActionButton(
              onPressed: () => _openEditor(null),
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              tooltip: 'New automation',
              child: const Icon(Icons.add_rounded),
            )
          : null,
    );
  }
}

// ── Flows view ────────────────────────────────────────────────────────────────

class _FlowsView extends StatelessWidget {
  const _FlowsView({
    required this.flows,
    required this.strings,
    required this.tapoDevices,
    required this.onAddBlank,
    required this.onAddTemplates,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
    required this.isClientMode,
  });

  final List<AutomationFlow> flows;
  final AppStrings strings;
  final List<TapoDevice> tapoDevices;
  final VoidCallback onAddBlank;
  final VoidCallback onAddTemplates;
  final ValueChanged<AutomationFlow> onTap;
  final void Function(AutomationFlow flow, bool enabled) onToggle;
  final ValueChanged<AutomationFlow> onDelete;
  final bool isClientMode;

  @override
  Widget build(BuildContext context) {
    if (flows.isEmpty) {
      return Column(
        children: [
          if (isClientMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0,
              ),
              child: _ClientModeBanner(strings: strings),
            ),
          Expanded(
            child: _EmptyState(
              onAddBlank: onAddBlank,
              onAddTemplates: onAddTemplates,
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      // Extra bottom padding so content is not hidden behind the FAB.
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 88,
      ),
      itemCount: flows.length + (isClientMode ? 1 : 0),
      itemBuilder: (context, index) {
        if (isClientMode && index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _ClientModeBanner(strings: strings),
          );
        }

        final flowIndex = isClientMode ? index - 1 : index;
        final flow = flows[flowIndex];

        return Padding(
          padding: EdgeInsets.only(
            bottom: flowIndex == flows.length - 1 ? 0 : AppSpacing.sm,
          ),
          child: _FlowCard(
            flow: flow,
            tapoDevices: tapoDevices,
            onTap: () => onTap(flow),
            onToggle: (v) => onToggle(flow, v),
            onDelete: () => onDelete(flow),
          ),
        );
      },
    );
  }
}

// ── History view ──────────────────────────────────────────────────────────────

class _HistoryView extends StatelessWidget {
  const _HistoryView({required this.history, required this.strings});

  final HistoryService history;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: history,
      builder: (context, _) {
        if (!history.isLoaded) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.teal),
          );
        }

        final entries = history.entries;

        if (entries.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxxl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 48,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha:0.4),
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
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl,
          ),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, i) => HistoryEntryTile(
            entry: entries[i],
            strings: strings,
          ),
        );
      },
    );
  }
}

// ── Client mode banner ────────────────────────────────────────────────────────

class _ClientModeBanner extends StatelessWidget {
  const _ClientModeBanner({required this.strings});
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.infoSurface,
        borderRadius: AppRadius.mdBR,
        border: Border.all(color: AppColors.info.withValues(alpha:0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync_rounded, size: 14, color: AppColors.info),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Automations sync to the gateway and run there. '
              'Changes publish automatically when connected.',
              style: AppTypography.labelSm.copyWith(color: AppColors.info),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Flow card, Step count pill, and Empty state widgets remain identical ──

// ── Flow card ─────────────────────────────────────────────────────────────────

class _FlowCard extends StatelessWidget {
  const _FlowCard({
    required this.flow,
    required this.tapoDevices,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  final AutomationFlow flow;
  final List<TapoDevice> tapoDevices;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  String _deviceName(String? id) {
    if (id == null) return 'Plug';
    return tapoDevices.where((d) => d.id == id).firstOrNull?.name ??
        'Unknown plug';
  }

  /// Builds the trigger summary line, e.g.:
  /// - `Falls below 10%  ·  21:00–08:00`
  /// - `Falls below 10%  ·  "Garage" OFF  ·  21:00–08:00` (combined condition)
  /// - `Plug "Garage" found OFF  ·  21:00–08:00`
  String get _triggerLine {
    final t = flow.trigger;
    final String base;

    switch (t.type) {
      case FlowTriggerType.batteryFallsBelow:
        base = 'Falls below ${t.threshold}%';
      case FlowTriggerType.batteryRisesAbove:
        base = 'Rises above ${t.threshold}%';
      case FlowTriggerType.tapoPlugState:
        final deviceName = _deviceName(t.tapoDeviceId);
        final stateLabel =
            t.tapoExpectedOn == true ? 'found OFF' : 'found ON';
        base = 'Plug "$deviceName" $stateLabel';
    }

    final parts = <String>[base];

    // Combined battery + plug-state condition (AND). Only meaningful for
    // battery triggers — tapoPlugState already has its own plug semantics.
    if (t.type != FlowTriggerType.tapoPlugState && t.requirePlugState) {
      final deviceName = _deviceName(t.tapoDeviceId);
      final stateLabel = t.tapoExpectedOn == true ? 'OFF' : 'ON';
      parts.add('"$deviceName" $stateLabel');
    }

    if (t.hasWindow) {
      String fmt(TimeOfDay td) =>
          '${td.hour.toString().padLeft(2, '0')}:${td.minute.toString().padLeft(2, '0')}';
      parts.add('${fmt(t.windowStart!)}–${fmt(t.windowEnd!)}');
    }

    return parts.join('  ·  ');
  }

  (IconData, Color) get _triggerIcon => switch (flow.trigger.type) {
        FlowTriggerType.batteryFallsBelow =>
          (Icons.trending_down_rounded, AppColors.error),
        FlowTriggerType.batteryRisesAbove =>
          (Icons.trending_up_rounded, AppColors.success),
        FlowTriggerType.tapoPlugState =>
          (Icons.power_rounded, AppColors.warning),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (trigIcon, trigColor) = _triggerIcon;

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
        child: Icon(Icons.delete_outline_rounded,
            color: theme.colorScheme.onErrorContainer),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false;
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
                  ? theme.colorScheme.primary.withValues(alpha:0.35)
                  : theme.colorScheme.outline,
              width: flow.enabled ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: trigColor.withValues(alpha:0.12),
                  borderRadius: AppRadius.smBR,
                ),
                child: Icon(trigIcon, size: 16, color: trigColor),
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
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha:0.8),
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
          Icon(Icons.playlist_play_rounded,
              size: 10,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha:0.6)),
          const SizedBox(width: 3),
          Text(
            '$count step${count == 1 ? '' : 's'}',
            style: AppTypography.labelSm.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha:0.8),
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
            Icon(Icons.auto_mode_rounded,
                size: 48,
                color:
                    theme.colorScheme.onSurfaceVariant.withValues(alpha:0.4)),
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