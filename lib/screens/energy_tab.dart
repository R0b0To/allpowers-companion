import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/energy_log_entry.dart';
import '../services/energy_log_service.dart';
import '../theme/app_theme.dart';
import '../widgets/line_chart_painter.dart';
import '../widgets/metric_card.dart';

enum _Range { day, week, month, all }

/// Displays battery and power trend graphs derived from [EnergyLogService]'s
/// periodically-sampled history.
///
/// Receives [EnergyLogService] from [MainShell] — creates nothing itself,
/// matching the pattern used by the other tabs.
class EnergyTab extends StatefulWidget {
  const EnergyTab({
    super.key,
    required this.energyLog,
    required this.strings,
  });

  final EnergyLogService energyLog;
  final AppStrings strings;

  @override
  State<EnergyTab> createState() => _EnergyTabState();
}

class _EnergyTabState extends State<EnergyTab> {
  _Range _range = _Range.day;

  Duration? get _rangeDuration {
    switch (_range) {
      case _Range.day:
        return const Duration(hours: 24);
      case _Range.week:
        return const Duration(days: 7);
      case _Range.month:
        return const Duration(days: 30);
      case _Range.all:
        return null;
    }
  }

  List<EnergyLogEntry> _filteredEntries() {
    final duration = _rangeDuration;
    if (duration == null) return widget.energyLog.entries;
    return widget.energyLog.since(duration);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.energyLog,
      builder: (context, _) => SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (!widget.energyLog.isLoaded) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.teal),
      );
    }

    final s = widget.strings;
    final entries = _filteredEntries();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.lg,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child:
                          Text(s.t('tab_energy'), style: AppTypography.displaySm),
                    ),
                    if (widget.energyLog.entries.isNotEmpty)
                      IconButton(
                        onPressed: () => _confirmClear(context),
                        tooltip: s.t('clear_energy_log'),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: AppColors.textTertiary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(s.t('energy_description'), style: AppTypography.bodyMd),
                const SizedBox(height: AppSpacing.lg),
                _RangeSelector(
                  range: _range,
                  strings: s,
                  onChanged: (r) => setState(() => _range = r),
                ),
                const SizedBox(height: AppSpacing.xxl),
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
                    const Icon(
                      Icons.show_chart_rounded,
                      size: 48,
                      color: AppColors.textTertiary,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      s.t('no_energy_data'),
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
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _StatsGrid(entries: entries, strings: s),
                const SizedBox(height: AppSpacing.lg),
                _ChartCard(
                  title: s.t('battery_trend'),
                  icon: Icons.battery_charging_full_rounded,
                  child: TimeSeriesChart(
                    height: 140,
                    valueLabel: (v) => '${v.round()}%',
                    timeLabel: _formatAxisTime,
                    minY: 0,
                    maxY: 100,
                    series: [
                      ChartSeries(
                        color: AppColors.teal,
                        fillGradient: true,
                        points: entries
                            .map((e) => ChartPoint(
                                e.timestamp.toLocal(), e.batteryLevel.toDouble()))
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _ChartCard(
                  title: s.t('power_flow'),
                  icon: Icons.bolt_rounded,
                  child: Column(
                    children: [
                      TimeSeriesChart(
                        height: 140,
                        valueLabel: (v) => '${v.round()}W',
                        timeLabel: _formatAxisTime,
                        series: [
                          ChartSeries(
                            color: AppColors.success,
                            points: entries
                                .map((e) => ChartPoint(
                                    e.timestamp.toLocal(), e.inputWatts.toDouble()))
                                .toList(),
                          ),
                          ChartSeries(
                            color: AppColors.error,
                            points: entries
                                .map((e) => ChartPoint(e.timestamp.toLocal(),
                                    e.outputWatts.toDouble()))
                                .toList(),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          _Legend(color: AppColors.success, label: s.t('charging')),
                          const SizedBox(width: AppSpacing.lg),
                          _Legend(color: AppColors.error, label: s.t('discharging')),
                        ],
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
      ],
    );
  }

  String _formatAxisTime(DateTime t) {
    final now = DateTime.now();
    final sameDay =
        t.year == now.year && t.month == now.month && t.day == now.day;
    if (sameDay) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmClear(BuildContext context) async {
    final s = widget.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBR),
        title: Text(s.t('clear_energy_log'), style: AppTypography.headingMd),
        content:
            Text(s.t('clear_energy_log_confirm'), style: AppTypography.bodyMd),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              s.t('cancel'),
              style:
                  AppTypography.headingSm.copyWith(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              s.t('clear_energy_log'),
              style: AppTypography.headingSm.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.energyLog.clear();
  }
}

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({
    required this.range,
    required this.strings,
    required this.onChanged,
  });

  final _Range range;
  final AppStrings strings;
  final ValueChanged<_Range> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = {
      _Range.day: strings.t('range_day'),
      _Range.week: strings.t('range_week'),
      _Range.month: strings.t('range_month'),
      _Range.all: strings.t('range_all'),
    };

    return Row(
      children: options.entries.map((entry) {
        final selected = entry.key == range;
        return Padding(
          padding: const EdgeInsets.only(right: AppSpacing.sm),
          child: GestureDetector(
            onTap: () => onChanged(entry.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? AppColors.tealSurface : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(
                  color: selected
                      ? AppColors.teal.withOpacity(0.4)
                      : AppColors.border,
                ),
              ),
              child: Text(
                entry.value,
                style: AppTypography.labelMd.copyWith(
                  color: selected ? AppColors.teal : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.lgBR,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.teal),
              const SizedBox(width: AppSpacing.sm),
              Text(title, style: AppTypography.headingSm),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: AppTypography.labelSm),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.entries, required this.strings});

  final List<EnergyLogEntry> entries;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final inputs = entries.map((e) => e.inputWatts);
    final outputs = entries.map((e) => e.outputWatts);

    final avgIn = inputs.isEmpty ? 0 : inputs.reduce((a, b) => a + b) / inputs.length;
    final avgOut =
        outputs.isEmpty ? 0 : outputs.reduce((a, b) => a + b) / outputs.length;
    final peakIn = inputs.isEmpty ? 0 : inputs.reduce((a, b) => a > b ? a : b);
    final peakOut = outputs.isEmpty ? 0 : outputs.reduce((a, b) => a > b ? a : b);

    return Row(
      children: [
        Expanded(
          child: MetricCard(
            icon: Icons.arrow_downward_rounded,
            iconColor: AppColors.success,
            title: strings.t('avg_input'),
            value: '${avgIn.round()} W',
            subtitle: '${strings.t('peak_input')}: $peakIn W',
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: MetricCard(
            icon: Icons.arrow_upward_rounded,
            iconColor: AppColors.error,
            title: strings.t('avg_output'),
            value: '${avgOut.round()} W',
            subtitle: '${strings.t('peak_output')}: $peakOut W',
          ),
        ),
      ],
    );
  }
}