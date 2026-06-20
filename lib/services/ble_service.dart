import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../constants/ble_constants.dart';
import '../models/power_station_status.dart';
import 'storage_service.dart';

/// Owns the entire Bluetooth connection lifecycle: scanning, connecting,
/// reconnecting to a previously paired station, decoding status packets,
/// and sending outlet commands.
///
/// UI code should only read the exposed state and call the public methods
/// -- it should never touch `flutter_blue_plus` directly. This also fixes
/// a few issues from the original implementation:
///  - Connection setup is now driven by the device's `connectionState`
///    stream rather than by awaiting `connect()` directly, so an
///    unexpected disconnect is always detected (the original code had no
///    way to notice a mid-session disconnect at all).
///  - Auto-connect no longer mixes `autoConnect: true` with a hard
///    `connect()` timeout, which could throw spuriously before Android's
///    background reconnect had a chance to work.
///  - Scanning cancels any previous subscription before starting a new
///    scan, avoiding a subscription leak if "Scan" is tapped repeatedly.
class BleService extends ChangeNotifier {
  BleService(this._storage);

  final StorageService _storage;

  List<ScanResult> scanResults = [];
  bool isScanning = false;
  bool isConnected = false;
  bool isAutoConnecting = false;
  BluetoothDevice? connectedDevice;
  PowerStationStatus status = const PowerStationStatus();

  /// Called every time a full status packet is decoded, after [status] has
  /// already been updated. Used by the screen to drive notifications and
  /// the automation engine.
  void Function(PowerStationStatus status)? onStatus;

  BluetoothCharacteristic? _readCharacteristic;
  BluetoothCharacteristic? _writeCharacteristic;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  /// Outlet toggles are applied locally for instant UI feedback. Status
  /// packets received within this window must not overwrite that
  /// optimistic state, since the station may keep reporting the old socket
  /// state for a few packets while the relay catches up.
  DateTime _lastManualCommandTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const _manualOverrideWindow = Duration(milliseconds: 1500);

  Future<void> init() async {
    final savedId = await _storage.getSavedDeviceId();
    if (savedId != null) {
      isAutoConnecting = true;
      notifyListeners();
      await _autoConnect(savedId);
    }
  }

  Future<void> _autoConnect(String savedId) async {
    final device = BluetoothDevice.fromId(savedId);
    final connected = Completer<void>();

    _watchConnectionState(device, onFirstConnect: () {
      if (!connected.isCompleted) connected.complete();
    });

    try {
      // autoConnect lets the OS keep retrying in the background even if
      // the station isn't immediately in range. We deliberately don't put
      // a timeout on the connect() call itself -- combining the two
      // causes spurious TimeoutExceptions -- and instead race the
      // connection-state stream against our own grace period below.
      unawaited(device.connect(autoConnect: true));
      await connected.future.timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('Auto-connect failed: $e');
      isAutoConnecting = false;
      notifyListeners();
      startScan();
    }
  }

  void startScan() {
    _scanSubscription?.cancel();
    scanResults = [];
    isScanning = true;
    notifyListeners();

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 60));
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      scanResults = results;
      notifyListeners();
    }, onError: (e) {
      debugPrint('Scan error: $e');
    });

    Future.delayed(const Duration(seconds: 60), () {
      isScanning = false;
      notifyListeners();
    });
  }

  Future<void> connectToDevice(BluetoothDevice device) async {
    try {
      _watchConnectionState(device);
      await device.connect();
    } catch (e) {
      debugPrint('Connect failed: $e');
    }
  }

  void _watchConnectionState(BluetoothDevice device, {VoidCallback? onFirstConnect}) {
    _connectionSubscription?.cancel();
    _connectionSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.connected) {
        onFirstConnect?.call();
        _setupConnectedDevice(device);
      } else if (state == BluetoothConnectionState.disconnected) {
        _handleDisconnect();
      }
    });
  }

  void _handleDisconnect() {
    _notifySubscription?.cancel();
    isConnected = false;
    isAutoConnecting = false;
    _readCharacteristic = null;
    _writeCharacteristic = null;
    notifyListeners();
  }

  Future<void> _setupConnectedDevice(BluetoothDevice device) async {
    connectedDevice = device;
    isConnected = true;
    isAutoConnecting = false;
    notifyListeners();

    final services = await device.discoverServices();
    BluetoothCharacteristic? readChar;
    BluetoothCharacteristic? writeChar;

    for (final service in services) {
      for (final char in service.characteristics) {
        final uuid = char.uuid.toString().toLowerCase();
        if (BleConstants.readCharacteristicHints.any(uuid.contains)) {
          readChar = char;
        }
        if (BleConstants.writeCharacteristicHints.any(uuid.contains)) {
          writeChar = char;
        }
      }
    }

    if (readChar == null || writeChar == null) {
      debugPrint('Required read/write characteristics not found on device.');
      return;
    }

    _readCharacteristic = readChar;
    _writeCharacteristic = writeChar;

    await _storage.setSavedDeviceId(device.remoteId.toString());

    await _readCharacteristic!.setNotifyValue(true);
    _notifySubscription = _readCharacteristic!.onValueReceived.listen(_parseStatusPacket);

    await _writeData(BleConstants.requestStatusCommand);
  }

  Future<void> forgetDevice() async {
    await _storage.clearSavedDeviceId();
    await _connectionSubscription?.cancel();
    await _notifySubscription?.cancel();
    if (connectedDevice != null) {
      await connectedDevice!.disconnect();
    }
    connectedDevice = null;
    isConnected = false;
    isAutoConnecting = false;
    _readCharacteristic = null;
    _writeCharacteristic = null;
    notifyListeners();
    startScan();
  }

  void _parseStatusPacket(List<int> bytes) {
    if (bytes.length < 6) return;
    final packetType = bytes[5];
    if (packetType != BleConstants.statusPacketType ||
        bytes.length < BleConstants.minStatusPacketLength) {
      return;
    }

    final batteryLevel = bytes[BleConstants.batteryLevelOffset];
    final inputWatts = (bytes[BleConstants.inputWattsHighByteOffset] << 8) |
        bytes[BleConstants.inputWattsHighByteOffset + 1];
    final outputWatts = (bytes[BleConstants.outputWattsHighByteOffset] << 8) |
        bytes[BleConstants.outputWattsHighByteOffset + 1];

    final withinManualWindow =
        DateTime.now().difference(_lastManualCommandTime) < _manualOverrideWindow;

    if (withinManualWindow) {
      status = status.copyWith(
        batteryLevel: batteryLevel,
        inputWatts: inputWatts,
        outputWatts: outputWatts,
      );
    } else {
      final socketMask = bytes[BleConstants.socketMaskOffset];
      status = status.copyWith(
        batteryLevel: batteryLevel,
        inputWatts: inputWatts,
        outputWatts: outputWatts,
        isUsbOn: (socketMask & BleConstants.usbMask) != 0,
        isAcOn: (socketMask & BleConstants.acMask) != 0,
        isDcOn: (socketMask & BleConstants.dcMask) != 0,
      );
    }

    notifyListeners();
    onStatus?.call(status);
  }

  Future<void> setUsb(bool enable) => _setSocket(usb: enable);
  Future<void> setAc(bool enable) => _setSocket(ac: enable);
  Future<void> setDc(bool enable) => _setSocket(dc: enable);

  Future<void> _setSocket({bool? usb, bool? ac, bool? dc}) async {
    _lastManualCommandTime = DateTime.now();
    status = status.copyWith(isUsbOn: usb, isAcOn: ac, isDcOn: dc);
    notifyListeners();

    int stateByte = 0;
    if (status.isUsbOn) stateByte |= BleConstants.usbMask;
    if (status.isAcOn) stateByte |= BleConstants.acMask;
    if (status.isDcOn) stateByte |= BleConstants.dcMask;

    final payload = [
      BleConstants.header1, BleConstants.header2, 0x00, 0xb1, 0x01, 0x01, 0x00, stateByte,
    ];
    int checksum = 0;
    for (final byte in payload) {
      checksum ^= byte;
    }
    payload.add(checksum);

    await _writeData(payload);
  }

  Future<void> _writeData(List<int> payload) async {
    if (_writeCharacteristic == null) return;
    final withoutResponse = _writeCharacteristic!.properties.writeWithoutResponse;
    try {
      await _writeCharacteristic!.write(payload, withoutResponse: withoutResponse);
    } catch (e) {
      debugPrint('Write failed: $e');
    }
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _notifySubscription?.cancel();
    _connectionSubscription?.cancel();
    connectedDevice?.disconnect();
    super.dispose();
  }
}