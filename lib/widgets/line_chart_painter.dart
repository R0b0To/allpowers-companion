import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A single (time, value) sample for [TimeSeriesChart].
class ChartPoint {
  const ChartPoint(this.time, this.value);
  final DateTime time;
  final double value;
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

  /// Whether to draw a soft gradient fill under the line (use for at most
  /// one series per chart — stacking fills gets visually noisy).
  final bool fillGradient;
}

/// A lightweight line chart for time-series data, styled to match the app's
/// dark/teal design system.
///
/// Deliberately hand-rolled with [CustomPainter] rather than a charting
/// package — the app only needs simple line plots, and avoiding a dependency
/// keeps rendering fully under our control and avoids a pubspec bump.
class TimeSeriesChart extends StatelessWidget {
  const TimeSeriesChart({
    super.key,
    required this.series,
    this.height = 160,
    this.minY,
    this.maxY,
    this.valueLabel,
    this.timeLabel,
  });

  final List<ChartSeries> series;
  final double height;

  /// Fixed Y bounds. If null, auto-computed from the data with padding.
  final double? minY;
  final double? maxY;

  /// Formats a Y-axis value for display (e.g. '42%', '120W').
  final String Function(double value)? valueLabel;

  /// Formats a [DateTime] for the X-axis end labels.
  final String Function(DateTime time)? timeLabel;

  @override
  Widget build(BuildContext context) {
    final allPoints = series.expand((s) => s.points).toList();
    if (allPoints.isEmpty) {
      return SizedBox(height: height);
    }

    final times = allPoints.map((p) => p.time.millisecondsSinceEpoch);
    final minX = times.reduce((a, b) => a < b ? a : b).toDouble();
    final maxX = times.reduce((a, b) => a > b ? a : b).toDouble();

    final values = allPoints.map((p) => p.value);
    final rawMinY = values.reduce((a, b) => a < b ? a : b);
    final rawMaxY = values.reduce((a, b) => a > b ? a : b);
    var loY = minY ?? rawMinY;
    var hiY = maxY ?? rawMaxY;
    if (hiY <= loY) hiY = loY + 1;
    if (minY == null || maxY == null) {
      final pad = (hiY - loY) * 0.1;
      if (maxY == null) hiY += pad;
      if (minY == null) {
        loY -= pad;
        // Don't let a naturally non-negative series (watts, percent) dip
        // below zero just because of padding.
        if (rawMinY >= 0 && loY < 0) loY = 0;
      }
    }

    final firstTime =
        allPoints.map((p) => p.time).reduce((a, b) => a.isBefore(b) ? a : b);
    final lastTime =
        allPoints.map((p) => p.time).reduce((a, b) => a.isAfter(b) ? a : b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (valueLabel != null)
              SizedBox(
                width: 40,
                height: height,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(valueLabel!(hiY), style: AppTypography.labelSm),
                    Text(valueLabel!(loY), style: AppTypography.labelSm),
                  ],
                ),
              ),
            Expanded(
              child: SizedBox(
                height: height,
                child: CustomPaint(
                  painter: _TimeSeriesPainter(
                    seriesList: series,
                    minY: loY,
                    maxY: hiY,
                    minX: minX,
                    maxX: maxX,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (timeLabel != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(timeLabel!(firstTime), style: AppTypography.labelSm),
                Text(timeLabel!(lastTime), style: AppTypography.labelSm),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TimeSeriesPainter extends CustomPainter {
  _TimeSeriesPainter({
    required this.seriesList,
    required this.minY,
    required this.maxY,
    required this.minX,
    required this.maxX,
  });

  final List<ChartSeries> seriesList;
  final double minY;
  final double maxY;
  final double minX;
  final double maxX;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final xRange = (maxX - minX) <= 0 ? 1.0 : (maxX - minX);
    final yRange = (maxY - minY) <= 0 ? 1.0 : (maxY - minY);

    Offset toOffset(ChartPoint p) {
      final xFrac = (p.time.millisecondsSinceEpoch - minX) / xRange;
      final yFrac = (p.value - minY) / yRange;
      return Offset(
        xFrac.clamp(0.0, 1.0) * size.width,
        size.height - yFrac.clamp(0.0, 1.0) * size.height,
      );
    }

    for (final s in seriesList) {
      if (s.points.isEmpty) continue;
      final offsets = s.points.map(toOffset).toList();

      if (s.fillGradient) {
        final fillPath = Path()..moveTo(offsets.first.dx, size.height);
        for (final o in offsets) {
          fillPath.lineTo(o.dx, o.dy);
        }
        fillPath
          ..lineTo(offsets.last.dx, size.height)
          ..close();
        final fillPaint = Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [s.color.withOpacity(0.22), s.color.withOpacity(0.0)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
        canvas.drawPath(fillPath, fillPaint);
      }

      final linePath = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      for (final o in offsets.skip(1)) {
        linePath.lineTo(o.dx, o.dy);
      }
      final linePaint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(linePath, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimeSeriesPainter oldDelegate) {
    return oldDelegate.seriesList != seriesList ||
        oldDelegate.minY != minY ||
        oldDelegate.maxY != maxY ||
        oldDelegate.minX != minX ||
        oldDelegate.maxX != maxX;
  }
}