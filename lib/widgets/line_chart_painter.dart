import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A single (time, value) sample for [TimeSeriesChart].
class ChartPoint {
  const ChartPoint(this.time, this.value);
  final DateTime time;
  final double value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChartPoint &&
          other.time == time &&
          other.value == value;

  @override
  int get hashCode => Object.hash(time, value);
}

/// One plotted line within a [TimeSeriesChart].

class ChartSeries {
  const ChartSeries({
    required this.points,
    required this.color,
    this.fillGradient = false,
  });

  final List<ChartPoint> points;
  final Color color;

  /// Whether to draw a soft gradient fill under the line.
  final bool fillGradient;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChartSeries &&
          other.color == color &&
          other.fillGradient == fillGradient &&
          listEquals(other.points, points);

  @override
  int get hashCode => Object.hash(color, fillGradient, Object.hashAll(points));
}

/// An interactive time-series line chart.
///
/// Tap or drag anywhere on the plot area to move a crosshair; the nearest
/// data-point time is reported via [onSelect]. Pass that value back via
/// [selectedTime] to keep two charts in sync (e.g. battery + power in the
/// Energy tab).
///
/// ## Axis labels
/// - Y: three labels (max, mid, min).
/// - X: four evenly-spaced timestamps.
///
/// ## Dots
/// Drawn at every real data point. Radius scales down automatically for
/// dense data so the line stays readable: ≤50 pts → 3.5 px, ≤150 → 2.5 px,
/// >150 → 1.5 px.
class TimeSeriesChart extends StatefulWidget {
  const TimeSeriesChart({
    super.key,
    required this.series,
    this.height = 160,
    this.minY,
    this.maxY,
    this.valueLabel,
    this.timeLabel,
    this.onSelect,
    this.selectedTime,
  });

  final List<ChartSeries> series;
  final double height;

  /// Fixed Y bounds. If null, auto-computed from data with 10 % padding.
  final double? minY;
  final double? maxY;

  /// Formats a Y value for the axis labels (e.g. '42 %', '120 W').
  final String Function(double value)? valueLabel;

  /// Formats a [DateTime] for the four X-axis tick labels.
  final String Function(DateTime time)? timeLabel;

  /// Called with the nearest data-point time on tap/drag.
  final ValueChanged<DateTime?>? onSelect;

  /// External crosshair; pass the last [onSelect] value back to this param
  /// to show a synchronised crosshair without holding state inside the chart.
  final DateTime? selectedTime;

  @override
  State<TimeSeriesChart> createState() => _TimeSeriesChartState();
}

class _TimeSeriesChartState extends State<TimeSeriesChart> {
  double _minX = 0;
  double _maxX = 1;

  void _handleTouch(double localX, double plotWidth) {
    if (plotWidth <= 0 || _maxX <= _minX) return;

    final fraction = (localX / plotWidth).clamp(0.0, 1.0);
    final ms = _minX + fraction * (_maxX - _minX);
    widget.onSelect?.call(DateTime.fromMillisecondsSinceEpoch(ms.round()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allPoints = widget.series.expand((s) => s.points).toList();
    if (allPoints.isEmpty) return SizedBox(height: widget.height);

    // ── X bounds ────────────────────────────────────────────────────────────
    final xMs = allPoints.map((p) => p.time.millisecondsSinceEpoch);
    _minX = xMs.reduce((a, b) => a < b ? a : b).toDouble();
    _maxX = xMs.reduce((a, b) => a > b ? a : b).toDouble();
    if (_maxX <= _minX) _maxX = _minX + 1;

    // ── Y bounds ────────────────────────────────────────────────────────────
    final vals = allPoints.map((p) => p.value);
    final rawMin = vals.reduce((a, b) => a < b ? a : b);
    final rawMax = vals.reduce((a, b) => a > b ? a : b);
    var loY = widget.minY ?? rawMin;
    var hiY = widget.maxY ?? rawMax;
    if (hiY <= loY) hiY = loY + 1;
    if (widget.minY == null || widget.maxY == null) {
      final pad = (hiY - loY) * 0.1;
      if (widget.maxY == null) hiY += pad;
      if (widget.minY == null) {
        loY -= pad;
        if (rawMin >= 0 && loY < 0) loY = 0;
      }
    }
    final midY = (loY + hiY) / 2;

    // ── X-axis ticks (4 evenly-spaced labels) ───────────────────────────────
    const tickCount = 4;
    final xTicks = List.generate(tickCount, (i) {
      final fraction = i / (tickCount - 1);
      return DateTime.fromMillisecondsSinceEpoch(
          (_minX + fraction * (_maxX - _minX)).round());
    });

    // ── Dot radius based on density ─────────────────────────────────────────
    final totalPoints = allPoints.length;
    final dotRadius = totalPoints <= 50
        ? 3.5
        : totalPoints <= 150
            ? 2.5
            : 1.5;

    final yLabelW = widget.valueLabel != null ? 44.0 : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Y-axis labels ───────────────────────────────────────────────
            if (widget.valueLabel != null)
              SizedBox(
                width: yLabelW,
                height: widget.height,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.valueLabel!(hiY),
                        style: AppTypography.labelSm),
                    Text(widget.valueLabel!(midY),
                        style: AppTypography.labelSm),
                    Text(widget.valueLabel!(loY),
                        style: AppTypography.labelSm),
                  ],
                ),
              ),

            // ── Plot area ───────────────────────────────────────────────────
            Expanded(
              child: LayoutBuilder(builder: (ctx, constraints) {
                final plotW = constraints.maxWidth;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) =>
                      _handleTouch(d.localPosition.dx, plotW),
                  onPanStart: (d) =>
                      _handleTouch(d.localPosition.dx, plotW),
                  onPanUpdate: (d) =>
                      _handleTouch(d.localPosition.dx, plotW),
                  child: SizedBox(
                    height: widget.height,
                    child: CustomPaint(
                      painter: _TimeSeriesPainter(
                        seriesList: widget.series,
                        minY: loY,
                        maxY: hiY,
                        minX: _minX,
                        maxX: _maxX,
                        selectedTime: widget.selectedTime,
                        dotRadius: dotRadius,
                        gridColor: theme.colorScheme.outlineVariant,
                        dotBgColor: theme.colorScheme.surfaceContainerLow,
                        crosshairColor: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha:0.35),
                      ),
                      size: Size(plotW, widget.height),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),

        // ── X-axis labels ───────────────────────────────────────────────────
        if (widget.timeLabel != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: EdgeInsets.only(left: yLabelW),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: xTicks
                  .map((t) => Text(widget.timeLabel!(t),
                      style: AppTypography.labelSm))
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Painter ───────────────────────────────────────────────────────────────────

class _TimeSeriesPainter extends CustomPainter {
  _TimeSeriesPainter({
    required this.seriesList,
    required this.minY,
    required this.maxY,
    required this.minX,
    required this.maxX,
    required this.gridColor,
    required this.dotBgColor,
    required this.crosshairColor,
    this.selectedTime,
    this.dotRadius = 2.5,
  });

  final List<ChartSeries> seriesList;
  final double minY;
  final double maxY;
  final double minX;
  final double maxX;
  final DateTime? selectedTime;
  final double dotRadius;

  final Color gridColor;
  final Color dotBgColor;
  final Color crosshairColor;

  Offset _toOffset(ChartPoint p, Size size) {
    final xFrac =
        ((p.time.millisecondsSinceEpoch - minX) / (maxX - minX))
            .clamp(0.0, 1.0);
    final yFrac = ((p.value - minY) / (maxY - minY)).clamp(0.0, 1.0);
    return Offset(xFrac * size.width, size.height - yFrac * size.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // ── Grid (5 horizontal lines) ────────────────────────────────────────
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // ── Fills ─────────────────────────────────────────────────────────────
    for (final s in seriesList) {
      if (!s.fillGradient || s.points.isEmpty) continue;
      final offsets = s.points.map((p) => _toOffset(p, size)).toList();
      final path = Path()..moveTo(offsets.first.dx, size.height);
      for (final o in offsets) path.lineTo(o.dx, o.dy);
      path
        ..lineTo(offsets.last.dx, size.height)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [s.color.withValues(alpha:0.2), Colors.transparent],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }

    // ── Lines ──────────────────────────────────────────────────────────────
    for (final s in seriesList) {
      if (s.points.isEmpty) continue;
      final offsets = s.points.map((p) => _toOffset(p, size)).toList();
      final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      for (final o in offsets.skip(1)) path.lineTo(o.dx, o.dy);
      canvas.drawPath(
        path,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // ── Data-point dots ────────────────────────────────────────────────────
    for (final s in seriesList) {
      if (s.points.isEmpty) continue;
      final offsets = s.points.map((p) => _toOffset(p, size)).toList();
      final bgPaint = Paint()
        ..color = dotBgColor
        ..style = PaintingStyle.fill;
      final dotPaint = Paint()
        ..color = s.color
        ..style = PaintingStyle.fill;
      for (final o in offsets) {
        canvas.drawCircle(o, dotRadius + 1.0, bgPaint);
        canvas.drawCircle(o, dotRadius, dotPaint);
      }
    }

    // ── Crosshair ──────────────────────────────────────────────────────────
    final sel = selectedTime;
    if (sel == null) return;

    final selMs = sel.millisecondsSinceEpoch.toDouble();
    final xFrac = ((selMs - minX) / (maxX - minX)).clamp(0.0, 1.0);
    final selX = xFrac * size.width;

    canvas.drawLine(
      Offset(selX, 0),
      Offset(selX, size.height),
      Paint()
        ..color = crosshairColor
        ..strokeWidth = 1,
    );

    for (final s in seriesList) {
      if (s.points.isEmpty) continue;
      ChartPoint? nearest;
      double? minDist;
      for (final pt in s.points) {
        final d = (pt.time.millisecondsSinceEpoch - selMs).abs().toDouble();
        if (minDist == null || d < minDist) {
          minDist = d;
          nearest = pt;
        }
      }
      if (nearest == null) continue;
      final o = _toOffset(nearest, size);
      canvas.drawCircle(
          o,
          9,
          Paint()
            ..color = s.color.withValues(alpha:0.18)
            ..style = PaintingStyle.fill);
      canvas.drawCircle(
          o,
          5.5,
          Paint()
            ..color = s.color.withValues(alpha:0.4)
            ..style = PaintingStyle.fill);
      canvas.drawCircle(
          o, 3.5, Paint()..color = s.color..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(covariant _TimeSeriesPainter old) {
    if (old.selectedTime != selectedTime ||
        old.minX != minX ||
        old.maxX != maxX ||
        old.minY != minY ||
        old.maxY != maxY ||
        old.dotRadius != dotRadius ||
        old.gridColor != gridColor ||
        old.dotBgColor != dotBgColor ||
        old.crosshairColor != crosshairColor) {
      return true;
    }

    return !listEquals(old.seriesList, seriesList);
  }
}