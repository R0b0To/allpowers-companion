import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../models/power_station_status.dart';
import '../theme/app_theme.dart';
import 'metric_card.dart';

/// The "Charging In / Discharging Out" pair of [MetricCard]s shown on both
/// the local [ControlTab] and the remote [MqttClientTab].
///
/// `_MetricsRow` (control_tab.dart) and `_RemoteMetricsRow`
/// (mqtt_client_tab.dart) were identical in every respect — same icons,
/// same colors, same string keys — so unlike [StationBatteryRing] there was
/// no divergent behavior to preserve here; this is a straight merge.
class StationMetricsRow extends StatelessWidget {
  const StationMetricsRow({
    super.key,
    required this.status,
    required this.strings,
  });

  final PowerStationStatus status;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: MetricCard(
            icon: Icons.arrow_downward_rounded,
            iconColor: AppColors.success,
            title: strings.t('charging'),
            value: '${status.inputWatts} W',
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: MetricCard(
            icon: Icons.arrow_upward_rounded,
            iconColor: AppColors.error,
            title: strings.t('discharging'),
            value: '${status.outputWatts} W',
          ),
        ),
      ],
    );
  }
}