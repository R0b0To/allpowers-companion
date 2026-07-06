import 'package:flutter/material.dart';

import '../models/power_station_status.dart';
import '../theme/app_theme.dart';

/// The large circular battery indicator shown at the top of both the local
/// [ControlTab] and the remote [MqttClientTab].
///
/// Extracted because `_BatteryRing` (control_tab.dart) and
/// `_RemoteBatteryRing` (mqtt_client_tab.dart) were byte-for-byte identical
/// except for the accessibility label text — any visual change (ring
/// thickness, colors, "charging" pill, remaining-time formatting) had to be
/// made twice, and it's easy to update one and forget the other.
class StationBatteryRing extends StatelessWidget {
  const StationBatteryRing({
    super.key,
    required this.status,
    this.semanticsLabelPrefix = 'Battery level',
  });

  final PowerStationStatus status;

  /// Prefix for the accessibility label, e.g. "Battery level" (local) or
  /// "Remote battery level" (MQTT client) — the only thing that ever
  /// differed between the two call sites.
  final String semanticsLabelPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = status.batteryLevel;
    final color = AppColors.batteryColor(level);
    final remainingTime = status.formattedRemainingTime;

    return Semantics(
      label: '$semanticsLabelPrefix: $level percent',
      child: Center(
        child: SizedBox(
          width: 160,
          height: 160,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Track ring (uses tone-based surfaceContainer)
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: 1,
                  strokeWidth: 12,
                  color: theme.colorScheme.surfaceContainer,
                ),
              ),
              // Value ring
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: level / 100,
                  strokeWidth: 12,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              // Centre content
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$level%',
                    style: AppTypography.monoLg.copyWith(color: color),
                  ),
                  if (status.isCharging) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.bolt_rounded,
                          size: 12,
                          color: AppColors.success,
                        ),
                        Text(
                          'Charging',
                          style: AppTypography.labelSm.copyWith(
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ],
                  // Remaining time indicator
                  if (remainingTime != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      status.isCharging
                          ? '$remainingTime to full'
                          : '$remainingTime left',
                      style: AppTypography.labelSm.copyWith(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}