import 'package:flutter/material.dart';

/// Immutable bundle of all "smart charging" automation settings.
class AutomationSettings {
  const AutomationSettings({
    this.enabled = false,
    this.tapoOnUrl = '',
    this.tapoOffUrl = '',
    this.lowThreshold = 10,
    this.highThreshold = 95,
    this.startTime = const TimeOfDay(hour: 21, minute: 0),
    this.endTime = const TimeOfDay(hour: 8, minute: 0),
  });

  final bool enabled;
  final String tapoOnUrl;
  final String tapoOffUrl;
  final int lowThreshold;
  final int highThreshold;
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  AutomationSettings copyWith({
    bool? enabled,
    String? tapoOnUrl,
    String? tapoOffUrl,
    int? lowThreshold,
    int? highThreshold,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
  }) {
    return AutomationSettings(
      enabled: enabled ?? this.enabled,
      tapoOnUrl: tapoOnUrl ?? this.tapoOnUrl,
      tapoOffUrl: tapoOffUrl ?? this.tapoOffUrl,
      lowThreshold: lowThreshold ?? this.lowThreshold,
      highThreshold: highThreshold ?? this.highThreshold,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }

  /// True if [now] falls inside the configured automation window, correctly
  /// handling windows that cross midnight (e.g. 21:00 -> 08:00).
  bool isTimeInWindow(TimeOfDay now) {
    final startMin = startTime.hour * 60 + startTime.minute;
    final endMin = endTime.hour * 60 + endTime.minute;
    final nowMin = now.hour * 60 + now.minute;

    if (startMin <= endMin) {
      return nowMin >= startMin && nowMin <= endMin;
    }
    return nowMin >= startMin || nowMin <= endMin;
  }
}