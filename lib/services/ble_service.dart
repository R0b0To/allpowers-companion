import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../constants/ble_constants.dart';
import '../models/power_station_status.dart';
import '../utils/logger.dart';
import 'storage_service.dart';

/// Owns the entire Bluetooth connection lifecycle: scanning, connecting,
/// reconnecting to a previously paired station, decoding status packets,
/// and sending outlet commands.
///
/// ## Design notes
///
/// **Optimistic UI**: Outlet toggle commands update [status] immediately for
/// instant feedback. Incoming status packets received within
/// [BleConstants.manualOverrideWindow] after a command do not overwrite the
/// socket fields, preventing visible flicker while the relay catches up.
///
/// **Auto-reconnect**: After an unexpected disconnect, the service schedules
/// one retry via [BleConstants.reconnectDelay]. If BT is turned off, state
/// is cleaned up but the saved device ID is preserved so auto-connect can
/// resume when BT comes back on.
///
/// **Adapter guard**: All BLE operations are gated on the adapter being `on`;
/// the adapter-state stream drives the connect/disconnect flow rather than
/// manual polling.
///
/// **Thread safety**: All stream callbacks execute on the Flutter event loop,
/// so there are no data races between callbacks. The [_sequenceLock] flag in
/// [AutomationEngine] is the cross-service guard for long async sequences.
class BleService extends ChangeNotifier {
  BleService(this._storage);

  final StorageService _storage;

  // ── Public state ───────────────────────────────────────────────────────────
  List<ScanResult> scanResults = [];
  bool isScanning = false;
  bool isConnected = false;
  bool isAutoConnecting = false;
  BluetoothDevice? connectedDevice;
  PowerStationStatus status = const PowerStationStatus();
  BluetoothAdapterState blueAdapterState = BluetoothAdapterState.unknown;
  String? lastError;

  /// Called each time a full status packet is decoded, after [status] has
  /// already been updated. Use this to trigger automation logic.
  void Function(PowerStationStatus status)? onStatus;

  // ── Private ────────────────────────────────────────────────────────────────
  BluetoothCharacteristic? _readCharacteristic;
  BluetoothCharacteristic? _writeCharacteristic;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _isScanningSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;

  /// The device ID we are trying to reconnect to. Retained in memory so
  /// reconnect after an unexpected disconnect does not require a
  /// SharedPreferences round-trip.
  String? _savedDeviceId;

  /// Tracks the last time a manual outlet command was sent, used to
  /// suppress socket-state updates from BLE packets during the override window.
  DateTime _lastManualCommandTime = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _inManualOverrideWindow =>
      DateTime.now().difference(_lastManualCommandTime) <
      BleConstants.manualOverrideWindow;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> init() async {
    _adapterSubscription =
        FlutterBluePlus.adapterState.listen(_onAdapterState);

    _savedDeviceId = await _storage.getSavedDeviceId();
    if (_savedDeviceId != null) {
      isAutoConnecting = true;
      notifyListeners();

      final currentState = await FlutterBluePlus.adapterState.first;
      if (currentState == BluetoothAdapterState.on) {
        await _autoConnect(_savedDeviceId!);
      }
    }
  }

  void _onAdapterState(BluetoothAdapterState state) {
    if (state == blueAdapterState) return; // De-duplicate identical states.
    blueAdapterState = state;
    notifyListeners();

    if (state == BluetoothAdapterState.on) {
      if (_savedDeviceId != null && !isConnected && !isAutoConnecting) {
        isAutoConnecting = true;
        notifyListeners();
        unawaited(_autoConnect(_savedDeviceId!));
      }
    } else {
      _handleDisconnect(retry: false);
    }
  }

  Future<void> _autoConnect(String deviceId) async {
    Log.i('BleService', 'Auto-connecting to $deviceId');
    final device = BluetoothDevice.fromId(deviceId);
    final connectedCompleter = Completer<void>();

    _watchConnectionState(device, onFirstConnect: () {
      if (!connectedCompleter.isCompleted) connectedCompleter.complete();
    });

    try {
      // mtu: null is required when autoConnect: true — combining them triggers
      // an assertion crash inside flutter_blue_plus on Android.
      unawaited(device.connect(autoConnect: true, mtu: null));
      await connectedCompleter.future
          .timeout(BleConstants.autoConnectTimeout);
    } on TimeoutException {
      Log.w('BleService', 'Auto-connect timed out for $deviceId');
      _cleanupAfterFailedConnect();
    } catch (e) {
      Log.e('BleService', 'Auto-connect failed', e);
      _cleanupAfterFailedConnect();
    }
  }

  void _cleanupAfterFailedConnect() {
    isAutoConnecting = false;
    lastError = 'Connection timed out';
    notifyListeners();
    if (blueAdapterState == BluetoothAdapterState.on) {
      startScan();
    }
  }

  // ── Scanning ───────────────────────────────────────────────────────────────

  void startScan() {
    if (blueAdapterState != BluetoothAdapterState.on) return;
    if (isScanning) return; // Guard against double-start.

    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();
    scanResults = [];
    isScanning = true;
    lastError = null;
    notifyListeners();

    FlutterBluePlus.startScan(timeout: BleConstants.scanDuration);

    _scanSubscription = FlutterBluePlus.scanResults.listen(
      (results) {
        scanResults = results;
        notifyListeners();
      },
      onError: (Object e) {
        Log.e('BleService', 'Scan error', e);
        lastError = 'Scan failed';
        notifyListeners();
      },
    );

    _isScanningSubscription = FlutterBluePlus.isScanning.listen((scanning) {
      if (isScanning != scanning) {
        isScanning = scanning;
        notifyListeners();
      }
    });
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
  }

  // ── Connecting ─────────────────────────────────────────────────────────────

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (blueAdapterState != BluetoothAdapterState.on) return;
    stopScan();
    lastError = null;

    try {
      _watchConnectionState(device);
      // mtu: null — see note in _autoConnect.
      await device.connect(mtu: null);
    } catch (e) {
      Log.e('BleService', 'Manual connect failed', e);
      lastError = 'Failed to connect';
      notifyListeners();
    }
  }

  void _watchConnectionState(
    BluetoothDevice device, {
    VoidCallback? onFirstConnect,
  }) {
    _connectionSubscription?.cancel();
    bool firstConnect = true;

    _connectionSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.connected) {
        if (firstConnect) {
          firstConnect = false;
          onFirstConnect?.call();
        }
        unawaited(_setupConnectedDevice(device));
      } else if (state == BluetoothConnectionState.disconnected) {
        _handleDisconnect(retry: true);
      }
    });
  }

  /// Cleans up state after a disconnect.
  ///
  /// [retry] = true  → unexpected disconnect; schedule reconnect.
  /// [retry] = false → intentional (user forgot device, BT turned off).
  void _handleDisconnect({required bool retry}) {
    _notifySubscription?.cancel();
    _notifySubscription = null;
    isConnected = false;
    isAutoConnecting = false;
    _readCharacteristic = null;
    _writeCharacteristic = null;
    notifyListeners();

    if (retry && _savedDeviceId != null &&
        blueAdapterState == BluetoothAdapterState.on) {
      Log.i('BleService', 'Unexpected disconnect — scheduling reconnect in '
          '${BleConstants.reconnectDelay.inSeconds}s');
      isAutoConnecting = true;
      notifyListeners();
      Future.delayed(BleConstants.reconnectDelay, () {
        if (!isConnected && _savedDeviceId != null) {
          unawaited(_autoConnect(_savedDeviceId!));
        }
      });
    }
  }

  // ── Post-connect setup ─────────────────────────────────────────────────────

  Future<void> _setupConnectedDevice(BluetoothDevice device) async {
    connectedDevice = device;
    isConnected = true;
    isAutoConnecting = false;
    lastError = null;
    notifyListeners();

    try {
      final services = await device.discoverServices();
      BluetoothCharacteristic? readChar;
      BluetoothCharacteristic? writeChar;

      for (final service in services) {
        for (final char in service.characteristics) {
          final uuid = char.uuid.toString().toLowerCase();
          // Take the last matching characteristic — later services are
          // typically the application-level ones on Allpowers hardware.
          if (BleConstants.readCharacteristicHints.any(uuid.contains)) {
            readChar = char;
          }
          if (BleConstants.writeCharacteristicHints.any(uuid.contains)) {
            writeChar = char;
          }
        }
      }

      if (readChar == null || writeChar == null) {
        Log.e('BleService', 'Required characteristics not found on ${device.platformName}');
        lastError = 'Device not supported — characteristics not found';
        notifyListeners();
        return;
      }

      _readCharacteristic = readChar;
      _writeCharacteristic = writeChar;

      // Persist device ID so we auto-connect on next app launch.
      _savedDeviceId = device.remoteId.toString();
      await _storage.setSavedDeviceId(_savedDeviceId!);

      await _readCharacteristic!.setNotifyValue(true);
      _notifySubscription =
          _readCharacteristic!.onValueReceived.listen(_parseStatusPacket);

      await _writeData(BleConstants.requestStatusCommand);
      Log.i('BleService', 'Connected and subscribed to ${device.platformName}');
    } catch (e) {
      Log.e('BleService', 'Setup failed after connect', e);
      lastError = 'Setup failed';
      notifyListeners();
    }
  }

  // ── Forget device ──────────────────────────────────────────────────────────

  Future<void> forgetDevice() async {
    Log.i('BleService', 'Forgetting device');
    _savedDeviceId = null;
    await _storage.clearSavedDeviceId();

    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _notifySubscription?.cancel();
    _notifySubscription = null;

    final device = connectedDevice;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (e) {
        Log.w('BleService', 'Disconnect on forget failed (ignoring): $e');
      }
    }

    connectedDevice = null;
    isConnected = false;
    isAutoConnecting = false;
    _readCharacteristic = null;
    _writeCharacteristic = null;
    lastError = null;
    notifyListeners();

    startScan();
  }

  // ── Packet parsing ─────────────────────────────────────────────────────────

  void _parseStatusPacket(List<int> bytes) {
    if (bytes.length < 6) return;

    final packetType = bytes[5];
    if (packetType != BleConstants.statusPacketType ||
        bytes.length < BleConstants.minStatusPacketLength) {
      return;
    }

    final batteryLevel = bytes[BleConstants.batteryLevelOffset];
    final inputWatts =
        (bytes[BleConstants.inputWattsHighByteOffset] << 8) |
        bytes[BleConstants.inputWattsHighByteOffset + 1];
    final outputWatts =
        (bytes[BleConstants.outputWattsHighByteOffset] << 8) |
        bytes[BleConstants.outputWattsHighByteOffset + 1];
        
    // Extract the minutes remaining (16-bit big-endian integer)
    final minutesRemaining =
        (bytes[BleConstants.minutesRemainingHighByteOffset] << 8) |
        bytes[BleConstants.minutesRemainingHighByteOffset + 1];

    final newStatus = _inManualOverrideWindow
        ? status.copyWith(
            batteryLevel: batteryLevel,
            inputWatts: inputWatts,
            outputWatts: outputWatts,
            minutesRemaining: minutesRemaining, // Include in manual override window
            // Socket fields preserved — relay may not have caught up yet.
          )
        : (() {
            final socketMask = bytes[BleConstants.socketMaskOffset];
            return status.copyWith(
              batteryLevel: batteryLevel,
              inputWatts: inputWatts,
              outputWatts: outputWatts,
              minutesRemaining: minutesRemaining, // Include in normal status update
              isUsbOn: (socketMask & BleConstants.usbMask) != 0,
              isAcOn: (socketMask & BleConstants.acMask) != 0,
              isDcOn: (socketMask & BleConstants.dcMask) != 0,
            );
          })();

    // Only notify if something actually changed.
    if (newStatus != status) {
      status = newStatus;
      notifyListeners();
    }

    onStatus?.call(status);
  }

  // ── Outlet commands ────────────────────────────────────────────────────────

  Future<void> setUsb(bool enable) => _setSocket(usb: enable);
  Future<void> setAc(bool enable) => _setSocket(ac: enable);
  Future<void> setDc(bool enable) => _setSocket(dc: enable);

  Future<void> _setSocket({bool? usb, bool? ac, bool? dc}) async {
    // Optimistic update — mark override window before updating status so
    // any in-flight BLE callback also sees it.
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

    // XOR checksum over all preceding bytes.
    int checksum = 0;
    for (final byte in payload) {
      checksum ^= byte;
    }
    payload.add(checksum);

    await _writeData(payload);
  }

  Future<void> _writeData(List<int> payload) async {
    final char = _writeCharacteristic;
    if (char == null) {
      Log.w('BleService', 'Write attempted with no characteristic — ignoring');
      return;
    }

    try {
      await char.write(
        payload,
        withoutResponse: char.properties.writeWithoutResponse,
      );
    } catch (e) {
      Log.e('BleService', 'Write failed', e);
    }
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

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