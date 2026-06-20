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
/// Fixes vs original:
///  - Passes `mtu: null` to `device.connect()` to avoid the assertion crash
///    that occurs when `autoConnect: true` and MTU negotiation are combined.
///  - Guards all BLE operations behind an adapter-state check so the app
///    does not crash when Bluetooth is disabled.
///  - After an unexpected disconnect, automatically retries the saved device
///    instead of silently going idle.
///  - Exposes [blueAdapterState] so the UI can show a "please enable
///    Bluetooth" message instead of a blank scan list.
class BleService extends ChangeNotifier {
  BleService(this._storage);

  final StorageService _storage;

  // ── Public state ──────────────────────────────────────────────────────────
  List<ScanResult> scanResults = [];
  bool isScanning = false;
  bool isConnected = false;
  bool isAutoConnecting = false;
  BluetoothDevice? connectedDevice;
  PowerStationStatus status = const PowerStationStatus();
  BluetoothAdapterState blueAdapterState = BluetoothAdapterState.unknown;

  /// Called every time a full status packet is decoded, after [status] has
  /// already been updated.
  void Function(PowerStationStatus status)? onStatus;

  // ── Private ───────────────────────────────────────────────────────────────
  BluetoothCharacteristic? _readCharacteristic;
  BluetoothCharacteristic? _writeCharacteristic;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _isScanningSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;

  /// The device ID we are trying to (re-)connect to. Kept so that after an
  /// unexpected disconnect we can retry without touching SharedPreferences
  /// again.
  String? _savedDeviceId;

  /// Outlet toggles are applied locally for instant UI feedback. Status
  /// packets received within this window must not overwrite that optimistic
  /// state, since the station may keep reporting the old socket state for a
  /// few packets while the relay catches up.
  DateTime _lastManualCommandTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const _manualOverrideWindow = Duration(milliseconds: 1500);

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> init() async {
    // Watch adapter state first so we can react to BT being toggled.
    _adapterSubscription = FlutterBluePlus.adapterState.listen(_onAdapterState);

    _savedDeviceId = await _storage.getSavedDeviceId();
    if (_savedDeviceId != null) {
      isAutoConnecting = true;
      notifyListeners();
      // _onAdapterState will kick off the actual connect once BT is confirmed on.
      // If BT is already on, trigger immediately.
      final currentState = await FlutterBluePlus.adapterState.first;
      if (currentState == BluetoothAdapterState.on) {
        await _autoConnect(_savedDeviceId!);
      }
    }
  }

  void _onAdapterState(BluetoothAdapterState state) {
    blueAdapterState = state;
    notifyListeners();

    if (state == BluetoothAdapterState.on) {
      // BT just turned on: if we have a saved device and are not yet
      // connected, kick off auto-connect.
      if (_savedDeviceId != null && !isConnected && !isAutoConnecting) {
        isAutoConnecting = true;
        notifyListeners();
        _autoConnect(_savedDeviceId!);
      }
    } else {
      // BT turned off: clean up state but don't forget the saved device.
      _handleDisconnect(retry: false);
    }
  }

  Future<void> _autoConnect(String deviceId) async {
    final device = BluetoothDevice.fromId(deviceId);
    final connected = Completer<void>();

    _watchConnectionState(device, onFirstConnect: () {
      if (!connected.isCompleted) connected.complete();
    });

    try {
      // mtu: null is required when autoConnect: true — mixing them triggers
      // a failed assertion inside flutter_blue_plus on Android.
      unawaited(device.connect(autoConnect: true, mtu: null));
      await connected.future.timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('Auto-connect failed or timed out: $e');
      isAutoConnecting = false;
      notifyListeners();
      // Fall back to manual scan so the user can see what's around.
      if (blueAdapterState == BluetoothAdapterState.on) {
        startScan();
      }
    }
  }

  // ── Scanning ──────────────────────────────────────────────────────────────

  void startScan() {
    if (blueAdapterState != BluetoothAdapterState.on) return;

    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();
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

    // Track the real scanning flag from the plugin rather than a manual timer.
    _isScanningSubscription = FlutterBluePlus.isScanning.listen((scanning) {
      if (isScanning != scanning) {
        isScanning = scanning;
        notifyListeners();
      }
    });
  }

  // ── Connecting ────────────────────────────────────────────────────────────

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (blueAdapterState != BluetoothAdapterState.on) return;
    try {
      _watchConnectionState(device);
      // mtu: null avoids the autoConnect assertion; for a manual connect
      // autoConnect is false so the MTU restriction doesn't apply, but
      // passing null is harmless and consistent.
      await device.connect(mtu: null);
    } catch (e) {
      debugPrint('Connect failed: $e');
    }
  }

  void _watchConnectionState(
    BluetoothDevice device, {
    VoidCallback? onFirstConnect,
  }) {
    _connectionSubscription?.cancel();
    _connectionSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.connected) {
        onFirstConnect?.call();
        _setupConnectedDevice(device);
      } else if (state == BluetoothConnectionState.disconnected) {
        _handleDisconnect(retry: true);
      }
    });
  }

  /// Called on every disconnect (expected or unexpected).
  ///
  /// [retry] = true  → we lost the connection unexpectedly and should try to
  ///                    reconnect to the saved device automatically.
  /// [retry] = false → BT was disabled or the user explicitly forgot the
  ///                   device; don't attempt a reconnect.
  void _handleDisconnect({required bool retry}) {
    _notifySubscription?.cancel();
    isConnected = false;
    isAutoConnecting = false;
    _readCharacteristic = null;
    _writeCharacteristic = null;
    notifyListeners();

    if (retry && _savedDeviceId != null && blueAdapterState == BluetoothAdapterState.on) {
      debugPrint('BleService: unexpected disconnect – scheduling reconnect.');
      isAutoConnecting = true;
      notifyListeners();
      // Small delay to let the OS clean up the connection before we retry.
      Future.delayed(const Duration(seconds: 2), () {
        if (!isConnected && _savedDeviceId != null) {
          _autoConnect(_savedDeviceId!);
        }
      });
    }
  }

  // ── Setup after connect ───────────────────────────────────────────────────

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
      debugPrint('Required read/write characteristics not found.');
      return;
    }

    _readCharacteristic = readChar;
    _writeCharacteristic = writeChar;

    // Persist the device ID so we auto-connect next launch.
    _savedDeviceId = device.remoteId.toString();
    await _storage.setSavedDeviceId(_savedDeviceId!);

    await _readCharacteristic!.setNotifyValue(true);
    _notifySubscription =
        _readCharacteristic!.onValueReceived.listen(_parseStatusPacket);

    await _writeData(BleConstants.requestStatusCommand);
  }

  // ── Forget device ─────────────────────────────────────────────────────────

  Future<void> forgetDevice() async {
    _savedDeviceId = null;
    await _storage.clearSavedDeviceId();
    _connectionSubscription?.cancel();
    _notifySubscription?.cancel();
    if (connectedDevice != null) {
      try {
        await connectedDevice!.disconnect();
      } catch (_) {}
    }
    connectedDevice = null;
    isConnected = false;
    isAutoConnecting = false;
    _readCharacteristic = null;
    _writeCharacteristic = null;
    notifyListeners();
    startScan();
  }

  // ── Packet parsing ────────────────────────────────────────────────────────

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

  // ── Outlet commands ───────────────────────────────────────────────────────

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
      BleConstants.header1,
      BleConstants.header2,
      0x00,
      0xb1,
      0x01,
      0x01,
      0x00,
      stateByte,
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
    final withoutResponse =
        _writeCharacteristic!.properties.writeWithoutResponse;
    try {
      await _writeCharacteristic!.write(
        payload,
        withoutResponse: withoutResponse,
      );
    } catch (e) {
      debugPrint('Write failed: $e');
    }
  }

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _adapterSubscription?.cancel();
    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _notifySubscription?.cancel();
    _connectionSubscription?.cancel();
    try {
      connectedDevice?.disconnect();
    } catch (_) {}
    super.dispose();
  }
}