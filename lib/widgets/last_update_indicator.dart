// lib/widgets/last_update_indicator.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Small pill showing "Updated Xs ago", recoloring as data goes stale.
/// Ticks every second on its own so the age advances even when no new
/// data arrives — which is exactly the case this exists to surface.
class LastUpdateIndicator extends StatefulWidget {
  const LastUpdateIndicator({
    super.key,
    required this.lastUpdate,
    this.warnAfter = const Duration(seconds: 20),
    this.staleAfter = const Duration(seconds: 45),
  });

  final DateTime? lastUpdate;
  final Duration warnAfter;
  final Duration staleAfter;

  @override
  State<LastUpdateIndicator> createState() => _LastUpdateIndicatorState();
}

class _LastUpdateIndicatorState extends State<LastUpdateIndicator> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final last = widget.lastUpdate;
    if (last == null) {
      return _pill('No data yet', AppColors.textTertiary, Icons.help_outline_rounded);
    }
    final age = DateTime.now().difference(last);
    final (color, icon) = age > widget.staleAfter
        ? (AppColors.error, Icons.warning_amber_rounded)
        : age > widget.warnAfter
            ? (AppColors.warning, Icons.schedule_rounded)
            : (AppColors.success, Icons.check_circle_outline_rounded);

    return _pill('Updated ${_formatAge(age)} ago', color, icon);
  }

  String _formatAge(Duration age) {
    if (age.inSeconds < 60) return '${age.inSeconds}s';
    if (age.inMinutes < 60) return '${age.inMinutes}m';
    return '${age.inHours}h';
  }

  Widget _pill(String text, Color color, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: AppRadius.xsBR,
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
            Text(text, style: AppTypography.labelSm.copyWith(color: color)),
          ],
        ),
      );
}