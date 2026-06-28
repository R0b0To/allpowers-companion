import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/energy_log_entry.dart';
import '../services/energy_log_service.dart';
import '../theme/app_theme.dart';
import '../widgets/line_chart_painter.dart';
import '../widgets/metric_card.dart';

enum _Range { threeHours, sixHours, day, week, month, all }

// ── Aggregated stats — computed once per filtered entry list ──────────────────

/// Holds pre-computed aggregate values for [_StatsGrid].
///
/// Previously this computation ran inside `build()` on every frame, which
/// meant O(n) work on every chart drag gesture, range change, and
/// AnimatedBuilder rebuild. By computing it once from [filteredEntries] and
/// passing it down as an immutable value object, [_StatsGrid.build] becomes
/// O(1) — it just formats numbers into strings.
class _AggregateStats {
  const _AggregateStats({
    required this.avgIn,
    required this.avgOut,
    required this.peakIn,
    required this.peakOut,
  });

  final int avgIn;
  final int avgOut;
  final int peakIn;
  final int peakOut;

  static _AggregateStats compute(List<EnergyLogEntry> entries) {
    if (entries.isEmpty) {
      return const _AggregateStats(avgIn: 0, avgOut: 0, peakIn: 0, peakOut: 0);
    }
    int sumIn = 0, sumOut = 0, peakIn = 0, peakOut = 0;
    for (final e in entries) {
      sumIn += e.inputWatts;
      sumOut += e.outputWatts;
      if (e.inputWatts > peakIn) peakIn = e.inputWatts;
      if (e.outputWatts > peakOut) peakOut = e.outputWatts;
    }
    return _AggregateStats(
      avgIn: sumIn ~/ entries.length,
      avgOut: sumOut ~/ entries.length,
      peakIn: peakIn,
      peakOut: peakOut,
    );
  }
}

/// Displays battery and power trend graphs derived from [EnergyLogService]'s
/// periodically-sampled history.
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
  DateTime? _selectedTime;

  // Cache the last filtered list and its stats so we don't recompute on
  // every chart crosshair drag (which calls setState but doesn't change
  // the underlying data).
  List<EnergyLogEntry>? _cachedEntries;
  _AggregateStats? _cachedStats;

  Duration? get _rangeDuration => switch (_range) {
        _Range.threeHours => const Duration(hours: 3),
        _Range.sixHours => const Duration(hours: 6),
        _Range.day => const Duration(hours: 24),
        _Range.week => const Duration(days: 7),
        _Range.month => const Duration(days: 30),
        _Range.all => null,
      };

  List<EnergyLogEntry> _filteredEntries() {
    final d = _rangeDuration;
    return d == null ? widget.energyLog.entries : widget.energyLog.since(d);
  }

  /// Returns filtered entries and recomputes aggregate stats only when the
  /// underlying list reference changes. A crosshair drag calls setState but
  /// does not change [_filteredEntries()], so [_cachedStats] is reused.
  (List<EnergyLogEntry>, _AggregateStats) _entriesAndStats() {
    final entries = _filteredEntries();
    // List equality by identity is sufficient here: EnergyLogService returns
    // the same list reference until a new sample is appended.
    if (!identical(entries, _cachedEntries)) {
      _cachedEntries = entries;
      _cachedStats = _AggregateStats.compute(entries);
    }
    return (entries, _cachedStats!);
  }

  EnergyLogEntry? _nearestEntry(DateTime time, List<EnergyLogEntry> entries) {
    if (entries.isEmpty) return null;
    final ms = time.millisecondsSinceEpoch;
    EnergyLogEntry? nearest;
    double? minDist;
    for (final e in entries) {
      final d = (e.timestamp.millisecondsSinceEpoch - ms).abs().toDouble();
      if (minDist == null || d < minDist) {
        minDist = d;
        nearest = e;
      }
    }
    return nearest;
  }

  void _onSelect(DateTime? t) => setState(() => _selectedTime = t);
  void _clearSelection() => setState(() => _selectedTime = null);

  void _stepSelection(int offset, List<EnergyLogEntry> entries) {
    if (entries.isEmpty) return;
    final selectedEntry =
        _selectedTime != null ? _nearestEntry(_selectedTime!, entries) : null;
    if (selectedEntry == null) {
      setState(() {
        _selectedTime =
            offset > 0 ? entries.first.timestamp : entries.last.timestamp;
      });
      return;
    }
    final currentIndex = entries.indexOf(selectedEntry);
    if (currentIndex == -1) return;
    final newIndex = (currentIndex + offset).clamp(0, entries.length - 1);
    setState(() => _selectedTime = entries[newIndex].timestamp);
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
    final (entries, stats) = _entriesAndStats();

    final selectedEntry =
        _selectedTime != null ? _nearestEntry(_selectedTime!, entries) : null;
    final int selectedIndex =
        selectedEntry != null ? entries.indexOf(selectedEntry) : -1;
    final bool hasPrevious = selectedIndex > 0;
    final bool hasNext =
        selectedIndex != -1 && selectedIndex < entries.length - 1;

    return CustomScrollView(
      slivers: [
        // ── Header ──────────────────────────────────────────────────────────
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
                      child: Text(s.t('tab_energy'),
                          style: AppTypography.displaySm),
                    ),
                    if (widget.energyLog.entries.isNotEmpty)
                      IconButton(
                        onPressed: () => _confirmClear(context),
                        tooltip: s.t('clear_energy_log'),
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: AppColors.textTertiary),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(s.t('energy_description'), style: AppTypography.bodyMd),
                const SizedBox(height: AppSpacing.lg),
                _RangeSelector(
                  range: _range,
                  strings: s,
                  onChanged: (r) => setState(() {
                    _range = r;
                    // Invalidate the cache when the range changes so stats
                    // are recomputed for the new filtered set.
                    _cachedEntries = null;
                    _clearSelection();
                  }),
                ),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),

        // ── Content ──────────────────────────────────────────────────────────
        if (entries.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxxl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.show_chart_rounded,
                        size: 48, color: AppColors.textTertiary),
                    const SizedBox(height: AppSpacing.lg),
                    Text(s.t('no_energy_data'),
                        style: AppTypography.bodyMd,
                        textAlign: TextAlign.center),
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
                // Pass pre-computed stats — build() is now O(1).
                _StatsGrid(stats: stats, strings: s),
                const SizedBox(height: AppSpacing.lg),

                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: selectedEntry != null
                      ? Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppSpacing.lg),
                          child: _DetailCard(
                            entry: selectedEntry,
                            strings: s,
                            onDismiss: _clearSelection,
                            onPrevious: hasPrevious
                                ? () => _stepSelection(-1, entries)
                                : null,
                            onNext: hasNext
                                ? () => _stepSelection(1, entries)
                                : null,
                          ),
                        )
                      : Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: Row(
                            children: [
                              const Icon(Icons.touch_app_outlined,
                                  size: 13,
                                  color: AppColors.textTertiary),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                'Tap on chart or use step buttons to inspect',
                                style: AppTypography.labelSm,
                              ),
                            ],
                          ),
                        ),
                ),

                // ── Battery trend chart ──────────────────────────────────────
                _ChartCard(
                  title: s.t('battery_trend'),
                  icon: Icons.battery_charging_full_rounded,
                  child: TimeSeriesChart(
                    height: 160,
                    valueLabel: (v) => '${v.round()}%',
                    timeLabel: _formatAxisTime,
                    minY: 0,
                    maxY: 100,
                    onSelect: _onSelect,
                    selectedTime: _selectedTime,
                    series: [
                      ChartSeries(
                        color: AppColors.teal,
                        fillGradient: true,
                        points: entries
                            .map((e) => ChartPoint(
                                e.timestamp.toLocal(),
                                e.batteryLevel.toDouble()))
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Power flow chart ─────────────────────────────────────────
                _ChartCard(
                  title: s.t('power_flow'),
                  icon: Icons.bolt_rounded,
                  child: Column(
                    children: [
                      TimeSeriesChart(
                        height: 160,
                        valueLabel: (v) => '${v.round()}W',
                        timeLabel: _formatAxisTime,
                        onSelect: _onSelect,
                        selectedTime: _selectedTime,
                        series: [
                          ChartSeries(
                            color: AppColors.success,
                            points: entries
                                .map((e) => ChartPoint(
                                    e.timestamp.toLocal(),
                                    e.inputWatts.toDouble()))
                                .toList(),
                          ),
                          ChartSeries(
                            color: AppColors.error,
                            points: entries
                                .map((e) => ChartPoint(
                                    e.timestamp.toLocal(),
                                    e.outputWatts.toDouble()))
                                .toList(),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          _Legend(
                              color: AppColors.success,
                              label: s.t('charging')),
                          const SizedBox(width: AppSpacing.lg),
                          _Legend(
                              color: AppColors.error,
                              label: s.t('discharging')),
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
    return sameDay
        ? '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
        : '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmClear(BuildContext context) async {
    final s = widget.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBR),
        title:
            Text(s.t('clear_energy_log'), style: AppTypography.headingMd),
        content: Text(s.t('clear_energy_log_confirm'),
            style: AppTypography.bodyMd),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.t('cancel'),
                style: AppTypography.headingSm
                    .copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.t('clear_energy_log'),
                style: AppTypography.headingSm
                    .copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _clearSelection();
      _cachedEntries = null;
      await widget.energyLog.clear();
    }
  }
}

// ── Detail inspection card ────────────────────────────────────────────────────

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.entry,
    required this.strings,
    required this.onDismiss,
    required this.onPrevious,
    required this.onNext,
  });

  final EnergyLogEntry entry;
  final AppStrings strings;
  final VoidCallback onDismiss;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  String _formatDate(DateTime t) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return 'Today';
    }
    return '${days[t.weekday - 1]} ${t.day} ${months[t.month - 1]}';
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final local = entry.timestamp.toLocal();
    final battColor = AppColors.batteryColor(entry.batteryLevel);

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: AppRadius.mdBR,
        border: Border.all(color: AppColors.teal.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            onPressed: onPrevious,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.chevron_left_rounded,
                color: onPrevious != null
                    ? AppColors.teal
                    : AppColors.textDisabled),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_formatDate(local), style: AppTypography.labelSm),
              Text(_formatTime(local),
                  style:
                      AppTypography.headingMd.copyWith(color: AppColors.teal)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Container(width: 1, height: 32, color: AppColors.border),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _DetailMetric(
                    icon: Icons.battery_std_rounded,
                    color: battColor,
                    label: 'Battery',
                    value: '${entry.batteryLevel}%'),
                _DetailMetric(
                    icon: Icons.arrow_downward_rounded,
                    color: AppColors.success,
                    label: strings.t('charging'),
                    value: '${entry.inputWatts} W'),
                _DetailMetric(
                    icon: Icons.arrow_upward_rounded,
                    color: AppColors.error,
                    label: strings.t('discharging'),
                    value: '${entry.outputWatts} W'),
                _OutletStateColumn(entry: entry),
              ],
            ),
          ),
          IconButton(
            onPressed: onNext,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.chevron_right_rounded,
                color:
                    onNext != null ? AppColors.teal : AppColors.textDisabled),
          ),
          const SizedBox(width: AppSpacing.xs),
          GestureDetector(
            onTap: onDismiss,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: Icon(Icons.close_rounded,
                  size: 16, color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailMetric extends StatelessWidget {
  const _DetailMetric({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
            Text(label, style: AppTypography.labelSm),
          ],
        ),
        const SizedBox(height: 2),
        Text(value,
            style: AppTypography.headingSm.copyWith(color: color)),
      ],
    );
  }
}

class _OutletStateColumn extends StatelessWidget {
  const _OutletStateColumn({required this.entry});
  final EnergyLogEntry entry;

  @override
  Widget build(BuildContext context) {
    Widget pill(String label, bool active) {
      final color = active ? AppColors.teal : AppColors.textDisabled;
      return Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: active ? 0.12 : 0.06),
          borderRadius: AppRadius.xsBR,
        ),
        child: Text(label,
            style: AppTypography.labelSm
                .copyWith(color: color, fontSize: 8, letterSpacing: 0.3)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        pill('USB', entry.isUsbOn),
        pill('AC', entry.isAcOn),
        pill('DC', entry.isDcOn),
      ],
    );
  }
}

// ── Range selector ────────────────────────────────────────────────────────────

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
      _Range.threeHours: '3h',
      _Range.sixHours: '6h',
      _Range.day: strings.t('range_day'),
      _Range.week: strings.t('range_week'),
      _Range.month: strings.t('range_month'),
      _Range.all: strings.t('range_all'),
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: options.entries.map((entry) {
          final selected = entry.key == range;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: GestureDetector(
              onTap: () => onChanged(entry.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? AppColors.tealSurface : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                    color: selected
                        ? AppColors.teal.withValues(alpha: 0.4)
                        : AppColors.border,
                  ),
                ),
                child: Text(
                  entry.value,
                  style: AppTypography.labelMd.copyWith(
                    color: selected
                        ? AppColors.teal
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Chart card wrapper ────────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  const _ChartCard(
      {required this.title, required this.icon, required this.child});

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

// ── Legend dot + label ────────────────────────────────────────────────────────

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
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: AppTypography.labelSm),
      ],
    );
  }
}

// ── Aggregate stats row ───────────────────────────────────────────────────────

/// Receives pre-computed [_AggregateStats] rather than the raw entry list.
///
/// FIX: `build()` is now O(1) — the previous O(n) loop has been moved to
/// [_AggregateStats.compute], called once per filtered list change.
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats, required this.strings});

  final _AggregateStats stats;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: MetricCard(
            icon: Icons.arrow_downward_rounded,
            iconColor: AppColors.success,
            title: strings.t('avg_input'),
            value: '${stats.avgIn} W',
            subtitle: '${strings.t('peak_input')}: ${stats.peakIn} W',
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: MetricCard(
            icon: Icons.arrow_upward_rounded,
            iconColor: AppColors.error,
            title: strings.t('avg_output'),
            value: '${stats.avgOut} W',
            subtitle: '${strings.t('peak_output')}: ${stats.peakOut} W',
          ),
        ),
      ],
    );
  }
}