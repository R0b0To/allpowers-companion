/// Immutable snapshot of the power station's live status, decoded from a
/// BLE status packet.
class PowerStationStatus {
  const PowerStationStatus({
    this.batteryLevel = 0,
    this.inputWatts = 0,
    this.outputWatts = 0,
    this.isUsbOn = false,
    this.isAcOn = false,
    this.isDcOn = false,
  });

  final int batteryLevel;
  final int inputWatts;
  final int outputWatts;
  final bool isUsbOn;
  final bool isAcOn;
  final bool isDcOn;

  PowerStationStatus copyWith({
    int? batteryLevel,
    int? inputWatts,
    int? outputWatts,
    bool? isUsbOn,
    bool? isAcOn,
    bool? isDcOn,
  }) {
    return PowerStationStatus(
      batteryLevel: batteryLevel ?? this.batteryLevel,
      inputWatts: inputWatts ?? this.inputWatts,
      outputWatts: outputWatts ?? this.outputWatts,
      isUsbOn: isUsbOn ?? this.isUsbOn,
      isAcOn: isAcOn ?? this.isAcOn,
      isDcOn: isDcOn ?? this.isDcOn,
    );
  }
}