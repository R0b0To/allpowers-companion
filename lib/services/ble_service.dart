import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../constants/ble_constants.dart';
import '../models/power_station_status.dart';
import '../repositories/ble_repository.dart';
import '../utils/logger.dart';

/// Owns the entire Bluetooth connection lifecycle: scanning, connecting,
/// reconnecting to a previously paired station, decoding status packets,
/// and sending outlet commands.
class BleService extends ChangeNotifier {
  BleService(this._repository);

  final BleRepository _repository;

  // ── Public state ───────────────────────────────────────────────────────────
  List<ScanResult> scanResults = [];
  bool isScanning = false;
  bool isConnected = false;
  bool isAutoConnecting = false;
  BluetoothDevice? connectedDevice;
  PowerStationStatus status = const PowerStationStatus();
  BluetoothAdapterState blueAdapterState = BluetoothAdapterState.unknown;
  String? lastError;

  /// Only called when [status] actually changes.
  void Function(PowerStationStatus status)? onStatus;

  // ── Private ────────────────────────────────────────────────────────────────
  BluetoothCharacteristic? _readCharacteristic;
  BluetoothCharacteristic? _writeCharacteristic;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<bool>? _isScanningSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  int _reconnectAttempts = 0;

  Timer? _watchdogTimer;
  Timer? _keepaliveTimer;

  /// Wall-clock time of the last valid packet received from the connected
  /// device (any packet with a valid protocol header, not just full status
  /// reports). Null while disconnected or before the first packet arrives
  /// after a (re)connect.
  DateTime? lastPacketTime;

  String? _savedDeviceId;
  BluetoothDevice? _pendingAutoConnectDevice;
  DateTime _lastManualCommandTime = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _inManualOverrideWindow =>
      DateTime.now().difference(_lastManualCommandTime) <
      BleConstants.manualOverrideWindow;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> init() async {
    _adapterSubscription = FlutterBluePlus.adapterState.listen(_onAdapterState);
    _savedDeviceId = await _repository.getSavedDeviceId();
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
    if (state == blueAdapterState) return;
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
    _pendingAutoConnectDevice = device;
    final connectedCompleter = Completer<void>();

    _watchConnectionState(device, onFirstConnect: () {
      if (!connectedCompleter.isCompleted) connectedCompleter.complete();
    });

    try {
      unawaited(device.connect(autoConnect: true, mtu: null));
      await connectedCompleter.future.timeout(BleConstants.autoConnectTimeout);
    } on TimeoutException {
      Log.w('BleService', 'Auto-connect timed out for $deviceId');
      await _cleanupAfterFailedConnect(device);
    } catch (e) {
      Log.e('BleService', 'Auto-connect failed', e);
      await _cleanupAfterFailedConnect(device);
    } finally {
      _pendingAutoConnectDevice = null;
    }
  }

  Future<void> _cleanupAfterFailedConnect(BluetoothDevice device) async {
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    try {
      await device.disconnect();
    } catch (_) {}
    isAutoConnecting = false;
    lastError = 'Connection timed out';
    notifyListeners();
    if (blueAdapterState == BluetoothAdapterState.on) startScan();
  }

  // ── Scanning ───────────────────────────────────────────────────────────────

  void startScan() {
    if (blueAdapterState != BluetoothAdapterState.on) return;
    if (isScanning) return;
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

  void stopScan() => FlutterBluePlus.stopScan();

  // ── Connecting ─────────────────────────────────────────────────────────────

  Future<void> connectToDevice(BluetoothDevice device) async {
    if (blueAdapterState != BluetoothAdapterState.on) return;
    stopScan();
    lastError = null;
    try {
      _watchConnectionState(device);
      await device.connect(mtu: null);
    } catch (e) {
      Log.e('BleService', 'Manual connect failed', e);
      lastError = 'Failed to connect';
      notifyListeners();
    }
  }

  void _watchConnectionState(BluetoothDevice device,
      {VoidCallback? onFirstConnect}) {
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

  void _handleDisconnect({required bool retry}) {
    _notifySubscription?.cancel();
    _notifySubscription = null;
    isConnected = false;
    _stopWatchdog();
    _stopKeepalive();
    isAutoConnecting = false;
    _readCharacteristic = null;
    _writeCharacteristic = null;
    notifyListeners();
    if (retry &&
        _savedDeviceId != null &&
        blueAdapterState == BluetoothAdapterState.on) {
      _reconnectAttempts++;
      final delay = _backoffDelay(_reconnectAttempts);
      Log.i('BleService', 'Unexpected disconnect — scheduling reconnect in '
          '${delay.inSeconds}s (attempt $_reconnectAttempts)');
      isAutoConnecting = true;
      notifyListeners();
      Future.delayed(delay, () {
        if (!isConnected && _savedDeviceId != null) {
          unawaited(_autoConnect(_savedDeviceId!));
        }
      });
    }
  }

Duration _backoffDelay(int attempt) {
    final scaled = BleConstants.reconnectBaseDelay * attempt;
    return scaled > BleConstants.reconnectMaxDelay
        ? BleConstants.reconnectMaxDelay
        : scaled;
  }
  // ── Post-connect setup ─────────────────────────────────────────────────────

  Future<void> _setupConnectedDevice(BluetoothDevice device) async {
    stopScan();
    connectedDevice = device;
    isConnected = true;
    isAutoConnecting = false;
    lastError = null;
    _reconnectAttempts = 0;
    notifyListeners();

    try {
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
        Log.e('BleService',
            'Required characteristics not found on ${device.platformName}');
        lastError = 'Device not supported — characteristics not found';
        notifyListeners();
        return;
      }
      _readCharacteristic = readChar;
      _writeCharacteristic = writeChar;
      _savedDeviceId = device.remoteId.toString();
      await _repository.setSavedDeviceId(_savedDeviceId!);
      await _readCharacteristic!.setNotifyValue(true);
      _notifySubscription =
          _readCharacteristic!.onValueReceived.listen(_parseStatusPacket);
      await _writeData(BleConstants.requestStatusCommand);
      _startWatchdog();
      _startKeepalive();
      Log.i('BleService',
          'Connected and subscribed to ${device.platformName}');
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
    _reconnectAttempts = 0;
    await _repository.clearSavedDeviceId();
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _stopWatchdog();
    _stopKeepalive();
    _notifySubscription?.cancel();
    _notifySubscription = null;
    final device = connectedDevice;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (e) {
        Log.w('BleService',
            'Disconnect on forget failed (ignoring): $e');
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
    // Minimum length check before anything else.
    if (bytes.length < BleConstants.minStatusPacketLength) return;

    // FIX: validate the protocol header bytes at offsets 0 and 1 FIRST.
    // Previously only bytes[5] (packet type) was checked. A spurious BLE
    // notification from another characteristic — or any 16+ byte payload that
    // happens to have 0x08 at offset 5 — would silently corrupt the displayed
    // station state. Checking the two-byte magic header prevents this.
    if (bytes[0] != BleConstants.header1 || bytes[1] != BleConstants.header2) {
      Log.d('BleService',
          'Ignoring packet with unknown header: '
          '0x${bytes[0].toRadixString(16)} 0x${bytes[1].toRadixString(16)}');
      return;
    }

    lastPacketTime = DateTime.now();

    final packetType = bytes[5];
    if (packetType != BleConstants.statusPacketType) return;

    final batteryLevel = bytes[BleConstants.batteryLevelOffset];
    final inputWatts = (bytes[BleConstants.inputWattsHighByteOffset] << 8) |
        bytes[BleConstants.inputWattsHighByteOffset + 1];
    final outputWatts = (bytes[BleConstants.outputWattsHighByteOffset] << 8) |
        bytes[BleConstants.outputWattsHighByteOffset + 1];
    final minutesRemaining =
        (bytes[BleConstants.minutesRemainingHighByteOffset] << 8) |
            bytes[BleConstants.minutesRemainingHighByteOffset + 1];

    final PowerStationStatus newStatus;
    if (_inManualOverrideWindow) {
      newStatus = status.copyWith(
        batteryLevel: batteryLevel,
        inputWatts: inputWatts,
        outputWatts: outputWatts,
        minutesRemaining: minutesRemaining,
      );
    } else {
      final socketMask = bytes[BleConstants.socketMaskOffset];
      newStatus = status.copyWith(
        batteryLevel: batteryLevel,
        inputWatts: inputWatts,
        outputWatts: outputWatts,
        minutesRemaining: minutesRemaining,
        isUsbOn: (socketMask & BleConstants.usbMask) != 0,
        isAcOn: (socketMask & BleConstants.acMask) != 0,
        isDcOn: (socketMask & BleConstants.dcMask) != 0,
      );
    }

    if (newStatus != status) {
      status = newStatus;
      notifyListeners();
      onStatus?.call(status);
    }
  }

  // ── Outlet commands ────────────────────────────────────────────────────────

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
      BleConstants.header1, BleConstants.header2, 0x00, 0xb1,
      0x01, 0x01, 0x00, stateByte,
    ];
    int checksum = 0;
    for (final byte in payload) checksum ^= byte;
    payload.add(checksum);
    await _writeData(payload);
  }

  Future<void> _writeData(List<int> payload) async {
    final char = _writeCharacteristic;
    if (char == null) {
      Log.w('BleService',
          'Write attempted with no characteristic — ignoring');
      return;
    }
    try {
      await char.write(payload,
          withoutResponse: char.properties.writeWithoutResponse);
    } catch (e) {
      Log.e('BleService', 'Write failed', e);
    }
  }


// ── Connection watchdog ─────────────────────────────────────────────────

  /// Periodically checks that packets are still arriving. Exists because
  /// `device.connectionState` can lag far behind reality on some OEMs —
  /// the OS reports "connected" while the GATT link is effectively dead.
  /// Without this, gateway mode silently goes stale with the screen off
  /// and nothing notices until the user opens the app.
  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(BleConstants.watchdogCheckInterval, (_) {
      if (!isConnected) return;
      final last = lastPacketTime;
      if (last == null) return; // No packet yet since (re)connect — give it time.

      final staleFor = DateTime.now().difference(last);
      if (staleFor > BleConstants.staleConnectionThreshold) {
        Log.w('BleService',
            'No packet in ${staleFor.inSeconds}s (threshold '
            '${BleConstants.staleConnectionThreshold.inSeconds}s) — '
            'connection appears stale. Forcing reconnect.');
        unawaited(_forceReconnect());
      }
    });
  }

  void _stopWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  // ── Keepalive ──────────────────────────────────────────────────────────

  /// Proactively re-requests a status broadcast on a fixed cadence while
  /// connected. This is a cheaper, faster recovery path than the watchdog's
  /// forced disconnect: a missed broadcast tick from the station resolves
  /// itself the moment this fires, without tearing down and re-establishing
  /// the GATT connection.
  void _startKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(BleConstants.keepaliveInterval, (_) {
      if (!isConnected) return;
      unawaited(_writeData(BleConstants.requestStatusCommand));
    });
  }

  void _stopKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
  }

  /// Disconnects the (apparently stuck) device. The existing
  /// `connectionState` listener already handles the resulting
  /// `disconnected` event via `_handleDisconnect(retry: true)`, which
  /// schedules a normal auto-reconnect — so this just kicks the OS into
  /// noticing what the watchdog already knows.
  Future<void> _forceReconnect() async {
    final device = connectedDevice;
    if (device == null) return;
    try {
      await device.disconnect();
    } catch (e) {
      Log.w('BleService', 'Watchdog force-disconnect failed: $e');
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
    _watchdogTimer?.cancel();
    _keepaliveTimer?.cancel();
    try {
      connectedDevice?.disconnect();
    } catch (_) {}
    super.dispose();
  }
}