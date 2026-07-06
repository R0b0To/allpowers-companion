import 'package:flutter/material.dart';

/// Immutable bundle of automation settings.
///
/// Tapo device credentials and per-device on/off actions have moved to
/// [TapoDevice] / [TapoDeviceService] and per-flow [FlowAction]s. This model
/// now only holds the global battery thresholds and time window used by
/// the simple (non-flow) automation engine.
final class AutomationSettings {
  const AutomationSettings({
    this.enabled = false,
    this.lowThreshold = 10,
    this.highThreshold = 95,
    this.startTime = const TimeOfDay(hour: 21, minute: 0),
    this.endTime = const TimeOfDay(hour: 8, minute: 0),
  });

  factory AutomationSettings.validated({
    bool enabled = false,
    required int lowThreshold,
    required int highThreshold,
    TimeOfDay startTime = const TimeOfDay(hour: 21, minute: 0),
    TimeOfDay endTime = const TimeOfDay(hour: 8, minute: 0),
  }) {
    final low = lowThreshold.clamp(0, 99);
    final high = highThreshold.clamp(low + 1, 100);
    return AutomationSettings(
      enabled: enabled,
      lowThreshold: low,
      highThreshold: high,
      startTime: startTime,
      endTime: endTime,
    );
  }

  final bool enabled;
  final int lowThreshold;
  final int highThreshold;
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  AutomationSettings copyWith({
    bool? enabled,
    int? lowThreshold,
    int? highThreshold,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
  }) {
    return AutomationSettings.validated(
      enabled: enabled ?? this.enabled,
      lowThreshold: lowThreshold ?? this.lowThreshold,
      highThreshold: highThreshold ?? this.highThreshold,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }

  /// Returns true if [now] falls inside the configured automation window.
  bool isTimeInWindow(TimeOfDay now) {
    final startMin = startTime.hour * 60 + startTime.minute;
    final endMin = endTime.hour * 60 + endTime.minute;
    final nowMin = now.hour * 60 + now.minute;

    if (startMin <= endMin) {
      return nowMin >= startMin && nowMin <= endMin;
    }
    return nowMin >= startMin || nowMin <= endMin;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutomationSettings &&
          other.enabled == enabled &&
          other.lowThreshold == lowThreshold &&
          other.highThreshold == highThreshold &&
          other.startTime == startTime &&
          other.endTime == endTime;

  @override
  int get hashCode => Object.hash(
        enabled,
        lowThreshold,
        highThreshold,
        startTime,
        endTime,
      );
}

extension AutomationSettingsJson on AutomationSettings {
  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'lowThreshold': lowThreshold,
        'highThreshold': highThreshold,
        'startTime':
            '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
        'endTime':
            '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
      };

  static AutomationSettings fromJson(Map<String, dynamic> json) {
    TimeOfDay parseTime(String value) {
      final parts = value.split(':');
      return TimeOfDay(
        hour: int.parse(parts[0]).clamp(0, 23),
        minute: int.parse(parts[1]).clamp(0, 59),
      );
    }

    return AutomationSettings.validated(
      enabled: json['enabled'] as bool? ?? false,
      lowThreshold: (json['lowThreshold'] as num? ?? 10).toInt(),
      highThreshold: (json['highThreshold'] as num? ?? 95).toInt(),
      startTime: parseTime(json['startTime'] as String? ?? '21:00'),
      endTime: parseTime(json['endTime'] as String? ?? '08:00'),
    );
  }
}