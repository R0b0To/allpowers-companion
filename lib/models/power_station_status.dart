/// Immutable snapshot of the power station's live status, decoded from a
/// BLE status packet.
///
/// All values are validated at construction:
/// - [batteryLevel] is clamped 0–100.
/// - [inputWatts] / [outputWatts] are clamped to non-negative values.
/// - [minutesRemaining] is clamped to legal 16-bit unsigned bounds.
final class PowerStationStatus {
  const PowerStationStatus({
    this.batteryLevel = 0,
    this.inputWatts = 0,
    this.outputWatts = 0,
    this.minutesRemaining = 0,
    this.isUsbOn = false,
    this.isAcOn = false,
    this.isDcOn = false,
  })  : assert(batteryLevel >= 0 && batteryLevel <= 100),
        assert(inputWatts >= 0),
        assert(outputWatts >= 0),
        assert(minutesRemaining >= 0);

  /// Constructs a validated instance, clamping values to legal ranges.
  factory PowerStationStatus.validated({
    required int batteryLevel,
    required int inputWatts,
    required int outputWatts,
    required int minutesRemaining,
    required bool isUsbOn,
    required bool isAcOn,
    required bool isDcOn,
  }) {
    return PowerStationStatus(
      batteryLevel: batteryLevel.clamp(0, 100),
      inputWatts: inputWatts.clamp(0, 9999),
      outputWatts: outputWatts.clamp(0, 9999),
      minutesRemaining: minutesRemaining.clamp(0, 65535),
      isUsbOn: isUsbOn,
      isAcOn: isAcOn,
      isDcOn: isDcOn,
    );
  }

  final int batteryLevel;
  final int inputWatts;
  final int outputWatts;
  final int minutesRemaining;
  final bool isUsbOn;
  final bool isAcOn;
  final bool isDcOn;

  /// True when the station appears to be receiving external power.
  bool get isCharging => inputWatts > 0;

  /// Net power flow (positive = charging, negative = discharging).
  int get netWatts => inputWatts - outputWatts;

  /// Whether any outlet is currently active.
  bool get hasActiveOutlet => isUsbOn || isAcOn || isDcOn;

  /// True if the duration is at its idle limit (0xFFFF / 65535), representing 
  /// an infinite, unknown, or no-load runtime status.
  bool get isRemainingTimeUnknown => minutesRemaining == 65535;

  /// Returns a human-readable duration (e.g. "2h 15m") or null if the 
  /// value is unknown or zero.
  String? get formattedRemainingTime {
    if (isRemainingTimeUnknown || minutesRemaining == 0) {
      return null;
    }
    final hours = minutesRemaining ~/ 60;
    final mins = minutesRemaining % 60;
    if (hours == 0) {
      return '${mins}m';
    }
    return '${hours}h ${mins}m';
  }

  PowerStationStatus copyWith({
    int? batteryLevel,
    int? inputWatts,
    int? outputWatts,
    int? minutesRemaining,
    bool? isUsbOn,
    bool? isAcOn,
    bool? isDcOn,
  }) {
    return PowerStationStatus.validated(
      batteryLevel: batteryLevel ?? this.batteryLevel,
      inputWatts: inputWatts ?? this.inputWatts,
      outputWatts: outputWatts ?? this.outputWatts,
      minutesRemaining: minutesRemaining ?? this.minutesRemaining,
      isUsbOn: isUsbOn ?? this.isUsbOn,
      isAcOn: isAcOn ?? this.isAcOn,
      isDcOn: isDcOn ?? this.isDcOn,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PowerStationStatus &&
          other.batteryLevel == batteryLevel &&
          other.inputWatts == inputWatts &&
          other.outputWatts == outputWatts &&
          other.minutesRemaining == minutesRemaining &&
          other.isUsbOn == isUsbOn &&
          other.isAcOn == isAcOn &&
          other.isDcOn == isDcOn;

  @override
  int get hashCode => Object.hash(
        batteryLevel,
        inputWatts,
        outputWatts,
        minutesRemaining,
        isUsbOn,
        isAcOn,
        isDcOn,
      );

  @override
  String toString() =>
      'PowerStationStatus(battery=$batteryLevel%, in=${inputWatts}W, '
      'out=${outputWatts}W, remaining=${minutesRemaining}m, usb=$isUsbOn, ac=$isAcOn, dc=$isDcOn)';
}