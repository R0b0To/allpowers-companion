import 'package:flutter/material.dart';

/// Immutable bundle of all "smart charging" automation settings.
///
/// Invariants enforced via [AutomationSettings.validated]:
/// - [lowThreshold] is in 0–100.
/// - [highThreshold] is in 0–100 and strictly greater than [lowThreshold].
final class AutomationSettings {
  const AutomationSettings({
    this.enabled = false,
    this.tapoOnUrl = '',
    this.tapoOffUrl = '',
    this.lowThreshold = 10,
    this.highThreshold = 95,
    this.startTime = const TimeOfDay(hour: 21, minute: 0),
    this.endTime = const TimeOfDay(hour: 8, minute: 0),
    this.useLocalTapo = false,
    this.tapoIp = '',
    this.tapoEmail = '',
    this.tapoPassword = '',
  });

  /// Constructs a settings object with validated threshold values.
  factory AutomationSettings.validated({
    bool enabled = false,
    String tapoOnUrl = '',
    String tapoOffUrl = '',
    required int lowThreshold,
    required int highThreshold,
    TimeOfDay startTime = const TimeOfDay(hour: 21, minute: 0),
    TimeOfDay endTime = const TimeOfDay(hour: 8, minute: 0),
    bool useLocalTapo = false,
    String tapoIp = '',
    String tapoEmail = '',
    String tapoPassword = '',
  }) {
    final low = lowThreshold.clamp(0, 99);
    final high = highThreshold.clamp(low + 1, 100);
    return AutomationSettings(
      enabled: enabled,
      tapoOnUrl: tapoOnUrl.trim(),
      tapoOffUrl: tapoOffUrl.trim(),
      lowThreshold: low,
      highThreshold: high,
      startTime: startTime,
      endTime: endTime,
      useLocalTapo: useLocalTapo,
      tapoIp: tapoIp.trim(),
      tapoEmail: tapoEmail.trim(),
      tapoPassword: tapoPassword,
    );
  }

  final bool enabled;
  final String tapoOnUrl;
  final String tapoOffUrl;
  final int lowThreshold;
  final int highThreshold;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final bool useLocalTapo;
  final String tapoIp;
  final String tapoEmail;
  final String tapoPassword;

  /// Whether local Tapo credentials are fully configured.
  bool get hasLocalTapoCredentials =>
      useLocalTapo && tapoIp.isNotEmpty && tapoEmail.isNotEmpty && tapoPassword.isNotEmpty;

  /// Whether at least one action (local or webhook) is configured for ON.
  bool get hasOnAction => hasLocalTapoCredentials || tapoOnUrl.isNotEmpty;

  /// Whether at least one action (local or webhook) is configured for OFF.
  bool get hasOffAction => hasLocalTapoCredentials || tapoOffUrl.isNotEmpty;

  AutomationSettings copyWith({
    bool? enabled,
    String? tapoOnUrl,
    String? tapoOffUrl,
    int? lowThreshold,
    int? highThreshold,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    bool? useLocalTapo,
    String? tapoIp,
    String? tapoEmail,
    String? tapoPassword,
  }) {
    return AutomationSettings.validated(
      enabled: enabled ?? this.enabled,
      tapoOnUrl: tapoOnUrl ?? this.tapoOnUrl,
      tapoOffUrl: tapoOffUrl ?? this.tapoOffUrl,
      lowThreshold: lowThreshold ?? this.lowThreshold,
      highThreshold: highThreshold ?? this.highThreshold,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      useLocalTapo: useLocalTapo ?? this.useLocalTapo,
      tapoIp: tapoIp ?? this.tapoIp,
      tapoEmail: tapoEmail ?? this.tapoEmail,
      tapoPassword: tapoPassword ?? this.tapoPassword,
    );
  }

  /// Returns true if [now] falls inside the configured automation window.
  ///
  /// Correctly handles windows that cross midnight, e.g. 21:00 → 08:00.
  bool isTimeInWindow(TimeOfDay now) {
    final startMin = startTime.hour * 60 + startTime.minute;
    final endMin = endTime.hour * 60 + endTime.minute;
    final nowMin = now.hour * 60 + now.minute;

    // Same-day window (e.g. 09:00–17:00).
    if (startMin <= endMin) {
      return nowMin >= startMin && nowMin <= endMin;
    }
    // Cross-midnight window (e.g. 21:00–08:00).
    return nowMin >= startMin || nowMin <= endMin;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AutomationSettings &&
          other.enabled == enabled &&
          other.tapoOnUrl == tapoOnUrl &&
          other.tapoOffUrl == tapoOffUrl &&
          other.lowThreshold == lowThreshold &&
          other.highThreshold == highThreshold &&
          other.startTime == startTime &&
          other.endTime == endTime &&
          other.useLocalTapo == useLocalTapo &&
          other.tapoIp == tapoIp &&
          other.tapoEmail == tapoEmail &&
          other.tapoPassword == tapoPassword;

  @override
  int get hashCode => Object.hash(
        enabled,
        tapoOnUrl,
        tapoOffUrl,
        lowThreshold,
        highThreshold,
        startTime,
        endTime,
        useLocalTapo,
        tapoIp,
        tapoEmail,
        tapoPassword,
      );
}

// ── JSON Serialization Extension ─────────────────────────────────────────────

extension AutomationSettingsJson on AutomationSettings {
  /// Packs configuration data into a map suitable for JSON transmission over MQTT.
  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'tapoOnUrl': tapoOnUrl,
      'tapoOffUrl': tapoOffUrl,
      'lowThreshold': lowThreshold,
      'highThreshold': highThreshold,
      'startTime': '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
      'endTime': '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
      'useLocalTapo': useLocalTapo,
      'tapoIp': tapoIp,
      'tapoEmail': tapoEmail,
      'tapoPassword': tapoPassword,
    };
  }

  /// Restores settings using your factory .validated constructor.
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
      tapoOnUrl: json['tapoOnUrl'] as String? ?? '',
      tapoOffUrl: json['tapoOffUrl'] as String? ?? '',
      lowThreshold: (json['lowThreshold'] as num? ?? 10).toInt(),
      highThreshold: (json['highThreshold'] as num? ?? 95).toInt(),
      startTime: parseTime(json['startTime'] as String? ?? '21:00'),
      endTime: parseTime(json['endTime'] as String? ?? '08:00'),
      useLocalTapo: json['useLocalTapo'] as bool? ?? false,
      tapoIp: json['tapoIp'] as String? ?? '',
      tapoEmail: json['tapoEmail'] as String? ?? '',
      tapoPassword: json['tapoPassword'] as String? ?? '',
    );
  }
}