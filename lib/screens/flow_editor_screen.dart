import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/automation_flow.dart';
import '../models/automation_settings.dart';
import '../models/tapo_device.dart';
import '../theme/app_theme.dart';

/// Full-screen editor for a single [AutomationFlow].
///
/// Push via [Navigator.push] and await the result:
/// ```dart
/// final saved = await Navigator.of(context).push<AutomationFlow>(
///   MaterialPageRoute(
///     fullscreenDialog: true,
///     builder: (_) => FlowEditorScreen(
///       flow: existing,
///       settings: settings,
///       tapoDevices: devices,
///     ),
///   ),
/// );
/// ```
/// Returns null when the user dismisses without saving.
class FlowEditorScreen extends StatefulWidget {
  const FlowEditorScreen({
    super.key,
    required this.flow,
    required this.settings,
    required this.tapoDevices,
  });

  final AutomationFlow? flow;
  final AutomationSettings settings;
  final List<TapoDevice> tapoDevices;

  @override
  State<FlowEditorScreen> createState() => _FlowEditorScreenState();
}

class _FlowEditorScreenState extends State<FlowEditorScreen> {
  late String _name;
  late FlowTrigger _trigger;
  late List<FlowAction> _actions;
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    final f = widget.flow;
    _name = f?.name ?? 'New Automation';
    _trigger = f?.trigger ??
        const FlowTrigger(
          type: FlowTriggerType.batteryFallsBelow,
          threshold: 20,
        );
    _actions = List.of(f?.actions ?? const []);
    _nameCtrl = TextEditingController(text: _name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final base = widget.flow ??
        AutomationFlow(
          id: newFlowId(),
          name: _name,
          trigger: _trigger,
          actions: _actions,
        );
    Navigator.of(context).pop(base.copyWith(
      name: _name.trim().isEmpty ? 'Unnamed' : _name.trim(),
      trigger: _trigger,
      actions: _actions,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        title: TextField(
          controller: _nameCtrl,
          onChanged: (v) => setState(() => _name = v),
          style: AppTypography.headingMd,
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: 'Automation name',
            isDense: true,
            contentPadding: EdgeInsets.zero,
            filled: false,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              'Save',
              style: AppTypography.headingSm.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: theme.colorScheme.outline),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          // ── Trigger ─────────────────────────────────────────────────────
          const _SectionLabel(title: 'Trigger', icon: Icons.flash_on_rounded),
          const SizedBox(height: AppSpacing.sm),
          _TriggerCard(
            trigger: _trigger,
            tapoDevices: widget.tapoDevices,
            onChanged: (t) => setState(() => _trigger = t),
          ),
          const SizedBox(height: AppSpacing.xl),

          // ── Actions ──────────────────────────────────────────────────────
          _SectionLabel(
            title: 'Action steps',
            icon: Icons.playlist_play_rounded,
            trailing: Text(
              '${_actions.length} step${_actions.length == 1 ? '' : 's'}',
              style: AppTypography.labelMd,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          if (_actions.isEmpty)
            _EmptyActionsHint(onAdd: _showAddSheet)
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = _actions.removeAt(oldIndex);
                  _actions.insert(newIndex, item);
                });
              },
              buildDefaultDragHandles: false,
              itemCount: _actions.length,
              itemBuilder: (context, index) => _ActionCard(
                key: ValueKey(_actions[index].id),
                index: index,
                action: _actions[index],
                settings: widget.settings,
                tapoDevices: widget.tapoDevices,
                onChanged: (updated) =>
                    setState(() => _actions[index] = updated),
                onDelete: () => setState(() => _actions.removeAt(index)),
              ),
            ),

          const SizedBox(height: AppSpacing.lg),
          _AddStepButton(onPressed: _showAddSheet),
          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }

  void _showAddSheet() {
    showModalBottomSheet<FlowActionType>(
      context: context,
      builder: (_) => const _AddActionSheet(),
    ).then((type) {
      if (type == null) return;
      setState(() => _actions.add(FlowAction(id: newFlowId(), type: type)));
    });
  }
}

// ── Trigger card ──────────────────────────────────────────────────────────────

class _TriggerCard extends StatelessWidget {
  const _TriggerCard({
    required this.trigger,
    required this.tapoDevices,
    required this.onChanged,
  });

  final FlowTrigger trigger;
  final List<TapoDevice> tapoDevices;
  final ValueChanged<FlowTrigger> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTapo = trigger.type == FlowTriggerType.tapoPlugState;
    final isFall = trigger.type == FlowTriggerType.batteryFallsBelow;

    Color accentColor;
    if (isTapo) {
      accentColor = AppColors.warning;
    } else if (isFall) {
      accentColor = theme.colorScheme.error;
    } else {
      accentColor = AppColors.success;
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.lgBR,
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Type selector ──────────────────────────────────────────────
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _ChoiceChip(
                label: 'Falls Below',
                icon: Icons.trending_down_rounded,
                selected: isFall,
                color: theme.colorScheme.error,
                onTap: () => onChanged(trigger.copyWith(
                    type: FlowTriggerType.batteryFallsBelow)),
              ),
              _ChoiceChip(
                label: 'Rises Above',
                icon: Icons.trending_up_rounded,
                selected: trigger.type == FlowTriggerType.batteryRisesAbove,
                color: AppColors.success,
                onTap: () => onChanged(trigger.copyWith(
                    type: FlowTriggerType.batteryRisesAbove)),
              ),
              _ChoiceChip(
                label: 'Plug State',
                icon: Icons.power_rounded,
                selected: isTapo,
                color: AppColors.warning,
                // FIX: previously this only set `type`, leaving windowStart/
                // windowEnd null. The UI below shows fallback placeholder
                // times (8:00/22:00) for this trigger type, which made it
                // *look* like a window was active and required, but
                // `hasWindow` stayed false and `isTimeInWindow` treats "no
                // window" as "always active" — so newly created Plug State
                // triggers fired at any hour until the user happened to tap
                // both time tiles. Populate a real default window here so
                // what's shown always matches what's actually enforced.
                onTap: () {
                  final next =
                      trigger.copyWith(type: FlowTriggerType.tapoPlugState);
                  onChanged(next.hasWindow
                      ? next
                      : next.copyWith(
                          windowStart: const TimeOfDay(hour: 21, minute: 0),
                          windowEnd: const TimeOfDay(hour: 8, minute: 0),
                        ));
                },
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.lg),

          // ── Battery threshold (only for battery triggers) ───────────────
          if (!isTapo) ...[
            Row(
              children: [
                Icon(
                  Icons.battery_std_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha:0.6),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text('Battery threshold', style: AppTypography.bodyMd),
                const Spacer(),
                Text(
                  '${trigger.threshold}%',
                  style: AppTypography.headingSm.copyWith(color: accentColor),
                ),
              ],
            ),
            Slider(
              value: trigger.threshold.toDouble(),
              min: 1,
              max: 99,
              divisions: 98,
              activeColor: accentColor,
              inactiveColor: theme.colorScheme.outline,
              onChanged: (v) =>
                  onChanged(trigger.copyWith(threshold: v.round())),
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),

            // ── Combined plug-state condition (AND) ───────────────────────
            Row(
              children: [
                Icon(Icons.power_rounded,
                    size: 16,
                    color:
                        theme.colorScheme.onSurfaceVariant.withValues(alpha:0.6)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text('Also require plug state',
                      style: AppTypography.bodyMd),
                ),
                Switch(
                  value: trigger.requirePlugState,
                  onChanged: (v) => onChanged(v
                      ? trigger.copyWith(
                          requirePlugState: true,
                          tapoExpectedOn: trigger.tapoExpectedOn ?? false,
                        )
                      : trigger.copyWith(requirePlugState: false)),
                ),
              ],
            ),
            if (trigger.requirePlugState) ...[
              const SizedBox(height: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
                child: Text(
                  'e.g. battery below ${trigger.threshold}% AND plug is '
                  '${trigger.tapoExpectedOn == false ? 'ON' : 'OFF'}',
                  style: AppTypography.labelSm,
                ),
              ),
              if (tapoDevices.isEmpty)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.warningSurface,
                    borderRadius: AppRadius.mdBR,
                    border: Border.all(
                        color: AppColors.warning.withValues(alpha:0.3)),
                  ),
                  child: Text(
                    'No Tapo devices found. Add one in the Devices tab.',
                    style: AppTypography.bodySm
                        .copyWith(color: AppColors.warning),
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  value: trigger.tapoDeviceId?.isNotEmpty == true
                      ? (tapoDevices.any((d) => d.id == trigger.tapoDeviceId)
                          ? trigger.tapoDeviceId
                          : null)
                      : null,
                  hint: Text('Select plug', style: AppTypography.bodyMd),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: AppRadius.mdBR,
                        borderSide:
                            BorderSide(color: theme.colorScheme.outline)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: AppRadius.mdBR,
                        borderSide:
                            BorderSide(color: theme.colorScheme.outline)),
                  ),
                  items: tapoDevices
                      .map((d) => DropdownMenuItem(
                            value: d.id,
                            child: Text(d.name, style: AppTypography.bodyLg),
                          ))
                      .toList(),
                  onChanged: (id) =>
                      onChanged(trigger.copyWith(tapoDeviceId: id)),
                  dropdownColor: AppColors.surfaceElevated,
                ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Icon(Icons.electric_bolt_rounded,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha:0.6)),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Plug must be', style: AppTypography.bodyMd),
                  const Spacer(),
                  _SmallChip(
                    label: 'ON',
                    selected: trigger.tapoExpectedOn == false,
                    color: AppColors.success,
                    onTap: () =>
                        onChanged(trigger.copyWith(tapoExpectedOn: false)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _SmallChip(
                    label: 'OFF',
                    selected: trigger.tapoExpectedOn == true,
                    color: theme.colorScheme.error,
                    onTap: () =>
                        onChanged(trigger.copyWith(tapoExpectedOn: true)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
          ],

          // ── Tapo plug state trigger ─────────────────────────────────────
          if (isTapo) ...[
            Row(
              children: [
                Icon(Icons.power_rounded,
                    size: 16,
                    color:
                        theme.colorScheme.onSurfaceVariant.withValues(alpha:0.6)),
                const SizedBox(width: AppSpacing.sm),
                Text('Plug to monitor', style: AppTypography.bodyMd),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (tapoDevices.isEmpty)
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.warningSurface,
                  borderRadius: AppRadius.mdBR,
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha:0.3)),
                ),
                child: Text(
                  'No Tapo devices found. Add one in the Devices tab.',
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.warning),
                ),
              )
            else
              DropdownButtonFormField<String>(
                value: trigger.tapoDeviceId?.isNotEmpty == true
                    ? (tapoDevices
                            .any((d) => d.id == trigger.tapoDeviceId)
                        ? trigger.tapoDeviceId
                        : null)
                    : null,
                hint: Text('Select plug',
                    style: AppTypography.bodyMd),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: AppRadius.mdBR,
                      borderSide:
                          BorderSide(color: theme.colorScheme.outline)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: AppRadius.mdBR,
                      borderSide:
                          BorderSide(color: theme.colorScheme.outline)),
                ),
                items: tapoDevices
                    .map((d) => DropdownMenuItem(
                          value: d.id,
                          child: Text(d.name,
                              style: AppTypography.bodyLg),
                        ))
                    .toList(),
                onChanged: (id) =>
                    onChanged(trigger.copyWith(tapoDeviceId: id)),
                dropdownColor: AppColors.surfaceElevated,
              ),
            const SizedBox(height: AppSpacing.md),

            Row(
              children: [
                Icon(Icons.electric_bolt_rounded,
                    size: 16,
                    color:
                        theme.colorScheme.onSurfaceVariant.withValues(alpha:0.6)),
                const SizedBox(width: AppSpacing.sm),
                Text('Trigger when plug is', style: AppTypography.bodyMd),
                const Spacer(),
                _SmallChip(
                  label: 'OFF',
                  selected: trigger.tapoExpectedOn == true,
                  color: AppColors.success,
                  onTap: () =>
                      onChanged(trigger.copyWith(tapoExpectedOn: true)),
                ),
                const SizedBox(width: AppSpacing.sm),
                _SmallChip(
                  label: 'ON',
                  selected: trigger.tapoExpectedOn == false,
                  color: theme.colorScheme.error,
                  onTap: () =>
                      onChanged(trigger.copyWith(tapoExpectedOn: false)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                trigger.tapoExpectedOn == true
                    ? 'Fires when plug is OFF and you want it ON (inside window)'
                    : trigger.tapoExpectedOn == false
                        ? 'Fires when plug is ON and you want it OFF (inside window)'
                        : 'Choose the expected plug state',
                style: AppTypography.labelSm,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),
          ],

          // ── Time window ────────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.schedule_rounded,
                  size: 16,
                  color:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha:0.6)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  isTapo
                      ? 'Active window (required)'
                      : 'Time window (optional)',
                  style: AppTypography.bodyMd,
                ),
              ),
              if (!isTapo)
                Switch(
                  value: trigger.hasWindow,
                  onChanged: (v) => onChanged(v
                      ? trigger.copyWith(
                          windowStart:
                              const TimeOfDay(hour: 21, minute: 0),
                          windowEnd: const TimeOfDay(hour: 8, minute: 0),
                        )
                      : trigger.copyWith(
                          windowStart: null, windowEnd: null)),
                ),
            ],
          ),
          if (trigger.hasWindow || isTapo) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                _TimeTile(
                  label: 'From',
                  time: trigger.windowStart ??
                      const TimeOfDay(hour: 8, minute: 0),
                  onPick: () async {
                    final t = await _pickTime(
                        context,
                        trigger.windowStart ??
                            const TimeOfDay(hour: 8, minute: 0));
                    if (t != null) {
                      onChanged(trigger.copyWith(windowStart: t));
                    }
                  },
                ),
                const SizedBox(width: AppSpacing.sm),
                _TimeTile(
                  label: 'To',
                  time: trigger.windowEnd ??
                      const TimeOfDay(hour: 22, minute: 0),
                  onPick: () async {
                    final t = await _pickTime(
                        context,
                        trigger.windowEnd ??
                            const TimeOfDay(hour: 22, minute: 0));
                    if (t != null) {
                      onChanged(trigger.copyWith(windowEnd: t));
                    }
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<TimeOfDay?> _pickTime(BuildContext context, TimeOfDay initial) =>
      showTimePicker(
        context: context,
        initialTime: initial,
        builder: (ctx, child) => Theme(
          data: AppTheme.timePickerTheme,
          child: child!,
        ),
      );
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.label,
    required this.time,
    required this.onPick,
  });

  final String label;
  final TimeOfDay time;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return Expanded(
      child: InkWell(
        onTap: onPick,
        borderRadius: AppRadius.mdBR,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: AppRadius.mdBR,
            border: Border.all(color: theme.colorScheme.outline),
          ),
          child: Row(
            children: [
              Icon(Icons.schedule_outlined,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha:0.6)),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTypography.labelSm),
                    Text(
                      '$h:$m',
                      style: AppTypography.headingSm.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Action cards ──────────────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    super.key,
    required this.index,
    required this.action,
    required this.settings,
    required this.tapoDevices,
    required this.onChanged,
    required this.onDelete,
  });

  final int index;
  final FlowAction action;
  final AutomationSettings settings;
  final List<TapoDevice> tapoDevices;
  final ValueChanged<FlowAction> onChanged;
  final VoidCallback onDelete;

  (IconData, Color) get _meta => switch (action.type) {
        FlowActionType.wait => (Icons.timer_outlined, AppColors.textSecondary),
        FlowActionType.setBleOutlet =>
          (Icons.power_rounded, AppColors.teal),
        FlowActionType.fireWebhook =>
          (Icons.link_rounded, AppColors.info),
        FlowActionType.controlTapo =>
          (Icons.wifi_tethering_rounded, AppColors.warning),
      };

  String get _label => switch (action.type) {
        FlowActionType.wait => 'Wait',
        FlowActionType.setBleOutlet => 'Set outlet',
        FlowActionType.fireWebhook => 'Webhook',
        FlowActionType.controlTapo => 'Tapo plug',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = _meta;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.mdBR,
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding:
                        const EdgeInsets.only(right: AppSpacing.sm),
                    child: Icon(
                      Icons.drag_handle_rounded,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha:0.4),
                    ),
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha:0.12),
                    borderRadius: AppRadius.smBR,
                  ),
                  child: Icon(icon, size: 14, color: color),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(_label, style: AppTypography.headingSm),
                const Spacer(),
                IconButton(
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: Icon(Icons.close_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha:0.6)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl + AppSpacing.lg, 0, AppSpacing.md, AppSpacing.md),
            child: _ActionConfig(
              action: action,
              settings: settings,
              tapoDevices: tapoDevices,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionConfig extends StatelessWidget {
  const _ActionConfig({
    required this.action,
    required this.settings,
    required this.tapoDevices,
    required this.onChanged,
  });

  final FlowAction action;
  final AutomationSettings settings;
  final List<TapoDevice> tapoDevices;
  final ValueChanged<FlowAction> onChanged;

  @override
  Widget build(BuildContext context) => switch (action.type) {
        FlowActionType.wait =>
          _WaitConfig(action: action, onChanged: onChanged),
        FlowActionType.setBleOutlet =>
          _OutletConfig(action: action, onChanged: onChanged),
        FlowActionType.fireWebhook =>
          _WebhookConfig(action: action, onChanged: onChanged),
        FlowActionType.controlTapo => _TapoConfig(
            action: action,
            settings: settings,
            tapoDevices: tapoDevices,
            onChanged: onChanged),
      };
}

// wait
class _WaitConfig extends StatefulWidget {
  const _WaitConfig({required this.action, required this.onChanged});
  final FlowAction action;
  final ValueChanged<FlowAction> onChanged;
  @override
  State<_WaitConfig> createState() => _WaitConfigState();
}

class _WaitConfigState extends State<_WaitConfig> {
  late final TextEditingController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.action.waitSeconds.toString());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text('Pause for', style: AppTypography.bodyMd),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 64,
          child: TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: AppTypography.headingSm
                .copyWith(color: theme.colorScheme.primary),
            onChanged: (v) {
              final s = int.tryParse(v);
              if (s != null && s > 0) {
                widget.onChanged(widget.action.copyWith(waitSeconds: s));
              }
            },
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
              border: OutlineInputBorder(
                borderRadius: AppRadius.smBR,
                borderSide: BorderSide(color: theme.colorScheme.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.smBR,
                borderSide: BorderSide(color: theme.colorScheme.outline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.smBR,
                borderSide: BorderSide(
                    color: theme.colorScheme.primary, width: 1.5),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text('seconds', style: AppTypography.bodyMd),
      ],
    );
  }
}

// setBleOutlet
class _OutletConfig extends StatelessWidget {
  const _OutletConfig({required this.action, required this.onChanged});
  final FlowAction action;
  final ValueChanged<FlowAction> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        ...BleOutlet.values.map((o) => _Chip(
              label: o.name.toUpperCase(),
              selected: action.outlet == o,
              color: theme.colorScheme.primary,
              onTap: () => onChanged(action.copyWith(outlet: o)),
            )),
        const SizedBox(width: AppSpacing.sm),
        _Chip(
          label: 'ON',
          selected: action.outletOn,
          color: AppColors.success,
          onTap: () => onChanged(action.copyWith(outletOn: true)),
        ),
        _Chip(
          label: 'OFF',
          selected: !action.outletOn,
          color: theme.colorScheme.error,
          onTap: () => onChanged(action.copyWith(outletOn: false)),
        ),
      ],
    );
  }
}

// fireWebhook
class _WebhookConfig extends StatefulWidget {
  const _WebhookConfig({required this.action, required this.onChanged});
  final FlowAction action;
  final ValueChanged<FlowAction> onChanged;
  @override
  State<_WebhookConfig> createState() => _WebhookConfigState();
}

class _WebhookConfigState extends State<_WebhookConfig> {
  late final TextEditingController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.action.webhookUrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.url,
      style: AppTypography.bodyLg,
      onChanged: (v) =>
          widget.onChanged(widget.action.copyWith(webhookUrl: v.trim())),
      decoration: const InputDecoration(
        hintText: 'https://…',
        isDense: true,
        prefixIcon: Icon(Icons.link_rounded, size: 16),
      ),
    );
  }
}

// controlTapo — now with device picker
class _TapoConfig extends StatelessWidget {
  const _TapoConfig({
    required this.action,
    required this.settings,
    required this.tapoDevices,
    required this.onChanged,
  });

  final FlowAction action;
  final AutomationSettings settings;
  final List<TapoDevice> tapoDevices;
  final ValueChanged<FlowAction> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Device picker
        if (tapoDevices.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.warningSurface,
              borderRadius: AppRadius.smBR,
            ),
            child: Text(
              'No Tapo devices configured. Add one in the Devices tab.',
              style:
                  AppTypography.labelSm.copyWith(color: AppColors.warning),
            ),
          )
        else ...[
          Text('Device', style: AppTypography.labelMd),
          const SizedBox(height: AppSpacing.xs),
          DropdownButtonFormField<String>(
            value: action.tapoDeviceId.isNotEmpty &&
                    tapoDevices.any((d) => d.id == action.tapoDeviceId)
                ? action.tapoDeviceId
                : null,
            hint: Text('Select plug', style: AppTypography.bodyMd),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: AppRadius.smBR,
                  borderSide:
                      BorderSide(color: theme.colorScheme.outline)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadius.smBR,
                  borderSide:
                      BorderSide(color: theme.colorScheme.outline)),
            ),
            items: tapoDevices
                .map((d) => DropdownMenuItem(
                      value: d.id,
                      child: Text(d.name, style: AppTypography.bodyMd),
                    ))
                .toList(),
            onChanged: (id) =>
                onChanged(action.copyWith(tapoDeviceId: id ?? '')),
            dropdownColor: AppColors.surfaceElevated,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),

        // ON / OFF chips
        Row(
          children: [
            _Chip(
              label: 'ON',
              selected: action.tapoOn,
              color: AppColors.success,
              onTap: () => onChanged(action.copyWith(tapoOn: true)),
            ),
            const SizedBox(width: AppSpacing.sm),
            _Chip(
              label: 'OFF',
              selected: !action.tapoOn,
              color: theme.colorScheme.error,
              onTap: () => onChanged(action.copyWith(tapoOn: false)),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Add action sheet ──────────────────────────────────────────────────────────

class _AddActionSheet extends StatelessWidget {
  const _AddActionSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = [
      (
        FlowActionType.wait,
        Icons.timer_outlined,
        theme.colorScheme.onSurfaceVariant.withValues(alpha:0.6),
        'Wait',
        'Pause for N seconds before the next step'
      ),
      (
        FlowActionType.setBleOutlet,
        Icons.power_rounded,
        theme.colorScheme.primary,
        'Set BLE outlet',
        'Toggle USB, AC, or DC output directly via Bluetooth'
      ),
      (
        FlowActionType.fireWebhook,
        Icons.link_rounded,
        AppColors.info,
        'Fire webhook',
        'Send an HTTP GET request to any URL'
      ),
      (
        FlowActionType.controlTapo,
        Icons.wifi_tethering_rounded,
        AppColors.warning,
        'Control Tapo',
        'Turn a TP-Link Tapo plug on or off'
      ),
    ];

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
            child: Text('Add step', style: AppTypography.headingMd),
          ),
          ...options.map((o) {
            final (type, icon, color, title, sub) = o;
            return ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha:0.12),
                  borderRadius: AppRadius.smBR,
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              title: Text(title, style: AppTypography.headingSm),
              subtitle: Text(sub, style: AppTypography.bodySm),
              onTap: () => Navigator.of(context).pop(type),
            );
          }),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }
}

// ── Shared primitives ─────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.title,
    required this.icon,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(title, style: AppTypography.headingMd)),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha:0.12)
              : theme.colorScheme.surfaceContainer,
          borderRadius: AppRadius.mdBR,
          border: Border.all(
            color: selected
                ? color.withValues(alpha:0.4)
                : theme.colorScheme.outline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14,
                color: selected
                    ? color
                    : theme.colorScheme.onSurfaceVariant
                        .withValues(alpha:0.6)),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: AppTypography.headingSm.copyWith(
                color: selected
                    ? color
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _Chip(
      label: label, selected: selected, color: color, onTap: onTap);
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha:0.15)
              : theme.colorScheme.surfaceContainer,
          borderRadius: AppRadius.xsBR,
          border: Border.all(
            color: selected
                ? color.withValues(alpha:0.5)
                : theme.colorScheme.outline,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.headingSm.copyWith(
            color: selected ? color : theme.colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _EmptyActionsHint extends StatelessWidget {
  const _EmptyActionsHint({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.lgBR,
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        children: [
          Icon(Icons.playlist_add_rounded,
              size: 32,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha:0.4)),
          const SizedBox(height: AppSpacing.md),
          Text('No steps yet', style: AppTypography.headingSm),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Steps run in order when the trigger fires.',
            style: AppTypography.bodyMd,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add first step'),
          ),
        ],
      ),
    );
  }
}

class _AddStepButton extends StatelessWidget {
  const _AddStepButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('Add step'),
        style: OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.primary,
          side: BorderSide(color: theme.colorScheme.primary),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}