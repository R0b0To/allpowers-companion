/// Immutable snapshot of the power station's live status, decoded from a
/// BLE status packet.
///
/// All values are validated at construction:
/// - [batteryLevel] is clamped 0–100.
/// - [inputWatts] / [outputWatts] are clamped to non-negative values.
final class PowerStationStatus {
  const PowerStationStatus({
    this.batteryLevel = 0,
    this.inputWatts = 0,
    this.outputWatts = 0,
    this.isUsbOn = false,
    this.isAcOn = false,
    this.isDcOn = false,
  })  : assert(batteryLevel >= 0 && batteryLevel <= 100),
        assert(inputWatts >= 0),
        assert(outputWatts >= 0);

  /// Constructs a validated instance, clamping values to legal ranges.
  factory PowerStationStatus.validated({
    required int batteryLevel,
    required int inputWatts,
    required int outputWatts,
    required bool isUsbOn,
    required bool isAcOn,
    required bool isDcOn,
  }) {
    return PowerStationStatus(
      batteryLevel: batteryLevel.clamp(0, 100),
      inputWatts: inputWatts.clamp(0, 9999),
      outputWatts: outputWatts.clamp(0, 9999),
      isUsbOn: isUsbOn,
      isAcOn: isAcOn,
      isDcOn: isDcOn,
    );
  }

  final int batteryLevel;
  final int inputWatts;
  final int outputWatts;
  final bool isUsbOn;
  final bool isAcOn;
  final bool isDcOn;

  /// True when the station appears to be receiving external power.
  bool get isCharging => inputWatts > 0;

  /// Net power flow (positive = charging, negative = discharging).
  int get netWatts => inputWatts - outputWatts;

  /// Whether any outlet is currently active.
  bool get hasActiveOutlet => isUsbOn || isAcOn || isDcOn;

  PowerStationStatus copyWith({
    int? batteryLevel,
    int? inputWatts,
    int? outputWatts,
    bool? isUsbOn,
    bool? isAcOn,
    bool? isDcOn,
  }) {
    return PowerStationStatus.validated(
      batteryLevel: batteryLevel ?? this.batteryLevel,
      inputWatts: inputWatts ?? this.inputWatts,
      outputWatts: outputWatts ?? this.outputWatts,
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
          other.isUsbOn == isUsbOn &&
          other.isAcOn == isAcOn &&
          other.isDcOn == isDcOn;

  @override
  int get hashCode => Object.hash(
        batteryLevel,
        inputWatts,
        outputWatts,
        isUsbOn,
        isAcOn,
        isDcOn,
      );

  @override
  String toString() =>
      'PowerStationStatus(battery=$batteryLevel%, in=${inputWatts}W, '
      'out=${outputWatts}W, usb=$isUsbOn, ac=$isAcOn, dc=$isDcOn)';
}