import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ap_companion/services/klap_crypto.dart';
import 'package:ap_companion/services/tapo_http_transport.dart';
import 'package:ap_companion/services/tapo_service.dart';

void main() {
  late FakeTapoHttpTransport transport;
  late TapoService service;

  setUp(() {
    transport = FakeTapoHttpTransport();
    service = TapoService(transport: transport);
  });

  tearDown(() {
    service.dispose();
  });

  group('successful KLAP round trip', () {
    test('getDeviceInfo returns the device state after a real handshake', () async {
      transport.registerDevice(
        ip: '192.168.1.50',
        email: 'user@example.com',
        password: 'secret',
        deviceOn: true,
        model: 'P110',
        nicknameBase64: base64.encode(utf8.encode('Garage Plug')),
      );

      final info = await service.getDeviceInfo(
        ip: '192.168.1.50',
        email: 'user@example.com',
        password: 'secret',
      );

      expect(info, isNotNull);
      expect(info!['device_on'], isTrue);
      expect(info['model'], 'P110');
      expect(transport.handshakeCountFor('192.168.1.50'), 1);
    });

    test('setOn(true) flips the fake device state and getDeviceInfo reflects it',
        () async {
      transport.registerDevice(
        ip: '192.168.1.51',
        email: 'user@example.com',
        password: 'secret',
        deviceOn: false,
      );

      final ok = await service.setOn(
        ip: '192.168.1.51',
        email: 'user@example.com',
        password: 'secret',
        on: true,
      );

      expect(ok, isTrue);
      final info = await service.getDeviceInfo(
        ip: '192.168.1.51',
        email: 'user@example.com',
        password: 'secret',
      );
      expect(info!['device_on'], isTrue);
    });

    test('test() reports a human-readable summary including model and state',
        () async {
      transport.registerDevice(
        ip: '192.168.1.52',
        email: 'user@example.com',
        password: 'secret',
        deviceOn: true,
        model: 'P100',
        nicknameBase64: base64.encode(utf8.encode('Office Lamp')),
      );

      final result = await service.test(
        ip: '192.168.1.52',
        email: 'user@example.com',
        password: 'secret',
      );

      expect(result, contains('P100'));
      expect(result, contains('Office Lamp'));
      expect(result, contains('ON'));
    });

    test('a repeated call to the same device reuses the session (single handshake)',
        () async {
      transport.registerDevice(
        ip: '192.168.1.53',
        email: 'user@example.com',
        password: 'secret',
      );

      await service.getDeviceInfo(
          ip: '192.168.1.53', email: 'user@example.com', password: 'secret');
      await service.getDeviceInfo(
          ip: '192.168.1.53', email: 'user@example.com', password: 'secret');
      await service.getDeviceInfo(
          ip: '192.168.1.53', email: 'user@example.com', password: 'secret');

      expect(transport.handshakeCountFor('192.168.1.53'), 1);
    });

    test('resetSession forces a fresh handshake on the next call', () async {
      transport.registerDevice(
        ip: '192.168.1.54',
        email: 'user@example.com',
        password: 'secret',
      );

      await service.getDeviceInfo(
          ip: '192.168.1.54', email: 'user@example.com', password: 'secret');
      service.resetSession(ip: '192.168.1.54', email: 'user@example.com');
      await service.getDeviceInfo(
          ip: '192.168.1.54', email: 'user@example.com', password: 'secret');

      expect(transport.handshakeCountFor('192.168.1.54'), 2);
    });

    test(
        'the factory-default credential fallback authenticates against an '
        'unconfigured device', () async {
      // Simulates a plug that hasn't been claimed yet — real credentials
      // don't match, but the device still accepts the well-known
      // kasa@tp-link.net / kasaSetup factory pair tried as a fallback.
      transport.registerDevice(
        ip: '192.168.1.55',
        email: 'kasa@tp-link.net',
        password: 'kasaSetup',
        deviceOn: false,
      );

      final info = await service.getDeviceInfo(
        ip: '192.168.1.55',
        email: 'whatever@example.com', // doesn't match the device
        password: 'wrongpassword',
      );

      expect(info, isNotNull);
    });
  });

  group('network failure handling', () {
    test('getDeviceInfo returns null and does not retry on failure', () async {
      transport.registerDevice(
        ip: '192.168.1.60',
        email: 'user@example.com',
        password: 'secret',
      );
      transport.failNextHandshakes('192.168.1.60', times: 5);

      final info = await service.getDeviceInfo(
        ip: '192.168.1.60',
        email: 'user@example.com',
        password: 'secret',
      );

      expect(info, isNull);
      // Exactly one handshake attempt — getDeviceInfo has no retry policy.
      expect(transport.handshakeAttemptCountFor('192.168.1.60'), 1);
    });

    test('isOn retries exactly once after a transient failure then succeeds',
        () async {
      transport.registerDevice(
        ip: '192.168.1.61',
        email: 'user@example.com',
        password: 'secret',
        deviceOn: true,
      );
      transport.failNextHandshakes('192.168.1.61', times: 1);

      final result = await service.isOn(
        ip: '192.168.1.61',
        email: 'user@example.com',
        password: 'secret',
      );

      expect(result, isTrue);
      expect(transport.handshakeAttemptCountFor('192.168.1.61'), 2);
    });

    test('isOn gives up and returns null after the retry also fails', () async {
      transport.registerDevice(
        ip: '192.168.1.62',
        email: 'user@example.com',
        password: 'secret',
      );
      transport.failNextHandshakes('192.168.1.62', times: 5);

      final result = await service.isOn(
        ip: '192.168.1.62',
        email: 'user@example.com',
        password: 'secret',
      );

      expect(result, isNull);
      // One initial attempt + exactly one retry — no more.
      expect(transport.handshakeAttemptCountFor('192.168.1.62'), 2);
    });

    test('setOn retries exactly once and eventually reports success', () async {
      transport.registerDevice(
        ip: '192.168.1.63',
        email: 'user@example.com',
        password: 'secret',
        deviceOn: false,
      );
      transport.failNextHandshakes('192.168.1.63', times: 1);

      final ok = await service.setOn(
        ip: '192.168.1.63',
        email: 'user@example.com',
        password: 'secret',
        on: true,
      );

      expect(ok, isTrue);
    });

    test('test() surfaces a friendly message for unreachable devices', () async {
      transport.registerDevice(
        ip: '192.168.1.64',
        email: 'user@example.com',
        password: 'secret',
      );
      transport.failNextHandshakes('192.168.1.64', times: 10);

      final result = await service.test(
        ip: '192.168.1.64',
        email: 'user@example.com',
        password: 'secret',
      );

      expect(result, startsWith('Connection failed:'));
    });
  });

  group('IP normalization', () {
    test('http:// prefix and trailing slash do not create a distinct session',
        () async {
      transport.registerDevice(
        ip: '192.168.1.70',
        email: 'user@example.com',
        password: 'secret',
      );

      await service.getDeviceInfo(
          ip: 'http://192.168.1.70/',
          email: 'user@example.com',
          password: 'secret');
      await service.getDeviceInfo(
          ip: '192.168.1.70', email: 'user@example.com', password: 'secret');

      expect(transport.handshakeCountFor('192.168.1.70'), 1);
    });
  });

  group('LRU session eviction', () {
    test('the 17th distinct device evicts the least-recently-used session',
        () async {
      // maxSessions is 16; register 17 distinct devices and touch each once
      // in order.
      for (var i = 0; i < 17; i++) {
        transport.registerDevice(
          ip: '10.0.0.$i',
          email: 'user@example.com',
          password: 'secret',
        );
      }

      for (var i = 0; i < 17; i++) {
        await service.getDeviceInfo(
            ip: '10.0.0.$i', email: 'user@example.com', password: 'secret');
      }

      // The very first device (LRU at the moment the 17th was added) should
      // have been evicted, forcing a second handshake when touched again...
      await service.getDeviceInfo(
          ip: '10.0.0.0', email: 'user@example.com', password: 'secret');
      expect(transport.handshakeCountFor('10.0.0.0'), 2);

      // ...while the most recently used device (10.0.0.16) is still cached.
      await service.getDeviceInfo(
          ip: '10.0.0.16', email: 'user@example.com', password: 'secret');
      expect(transport.handshakeCountFor('10.0.0.16'), 1);
    });
  });
}

// ── Fake device / transport ────────────────────────────────────────────────

class _FakeSession {
  _FakeSession({
    required this.localSeed,
    required this.remoteSeed,
    required this.authHash,
  });
  final Uint8List localSeed;
  final Uint8List remoteSeed;
  final Uint8List authHash;
}

class _FakeDevice {
  _FakeDevice({
    required this.email,
    required this.password,
    this.deviceOn = false,
    this.model = 'Unknown',
    required this.nicknameBase64,
  });

  final String email;
  final String password;
  bool deviceOn;
  final String model;
  final String nicknameBase64;

  int handshakeAttempts = 0;
  int successfulHandshakes = 0;
  int pendingFailures = 0;

  final Map<String, _FakeSession> sessions = {};
}

/// A fake "device" that speaks the real KLAP protocol using [KlapCrypto] —
/// the same functions the real client uses — so `TapoService` can be tested
/// against a symmetric peer instead of a mocked-out response.
///
/// Session continuity between `handshake1` → `handshake2` → `request` is
/// tracked via the `cookie` the real `_TapoSession` already sends/receives,
/// exactly like a real device would.
class FakeTapoHttpTransport implements TapoHttpTransport {
  final Map<String, _FakeDevice> _devicesByIp = {};
  int _cookieCounter = 0;

  void registerDevice({
    required String ip,
    required String email,
    required String password,
    bool deviceOn = false,
    String model = 'Unknown',
    String? nicknameBase64,
  }) {
    _devicesByIp[ip] = _FakeDevice(
      email: email,
      password: password,
      deviceOn: deviceOn,
      model: model,
      nicknameBase64:
          nicknameBase64 ?? base64.encode(utf8.encode('Test Plug')),
    );
  }

  void failNextHandshakes(String ip, {required int times}) {
    _devicesByIp[ip]!.pendingFailures += times;
  }

  int handshakeCountFor(String ip) =>
      _devicesByIp[ip]?.successfulHandshakes ?? 0;

  int handshakeAttemptCountFor(String ip) =>
      _devicesByIp[ip]?.handshakeAttempts ?? 0;

  @override
  Future<TapoHttpResponse> post(
    String ip,
    String path,
    Uint8List body, {
    Map<String, String>? queryParams,
    String? cookie,
  }) async {
    final device = _devicesByIp[ip];
    if (device == null) {
      throw const SocketException('Connection refused');
    }

    switch (path) {
      case 'handshake1':
        return _handshake1(device, body);
      case 'handshake2':
        return TapoHttpResponse(body: Uint8List.fromList(const []));
      case 'request':
        return _request(device, cookie!, body, queryParams!);
      default:
        throw StateError('Unexpected path: $path');
    }
  }

  TapoHttpResponse _handshake1(_FakeDevice device, Uint8List localSeed) {
    device.handshakeAttempts++;
    if (device.pendingFailures > 0) {
      device.pendingFailures--;
      throw const SocketException('Connection refused');
    }

    final remoteSeed = KlapCrypto.randomBytes(16);
    final authHash = KlapCrypto.calcAuthHash(device.email, device.password);
    final serverHash = KlapCrypto.sha256(
      Uint8List(localSeed.length + remoteSeed.length + authHash.length)
        ..setAll(0, localSeed)
        ..setAll(localSeed.length, remoteSeed)
        ..setAll(localSeed.length + remoteSeed.length, authHash),
    );

    final cookie = 'sess_${_cookieCounter++}';
    device.sessions[cookie] = _FakeSession(
      localSeed: localSeed,
      remoteSeed: remoteSeed,
      authHash: authHash,
    );
    device.successfulHandshakes++;

    final responseBody = Uint8List(48)
      ..setAll(0, remoteSeed)
      ..setAll(16, serverHash);

    return TapoHttpResponse(body: responseBody, setCookie: cookie);
  }

  TapoHttpResponse _request(
    _FakeDevice device,
    String cookie,
    Uint8List body,
    Map<String, String> queryParams,
  ) {
    final session = device.sessions[cookie]!;
    final key = KlapCrypto.deriveKey(
            'lsk', session.localSeed, session.remoteSeed, session.authHash)
        .sublist(0, 16);
    final ivSeq = KlapCrypto.deriveKey(
        'iv', session.localSeed, session.remoteSeed, session.authHash);
    final iv = ivSeq.sublist(0, 12);
    final sigPrefix = KlapCrypto.deriveKey(
            'ldk', session.localSeed, session.remoteSeed, session.authHash)
        .sublist(0, 28);

    final seq = int.parse(queryParams['seq']!);
    final seqBytes = KlapCrypto.toInt32BigEndian(seq);
    final aesIv = Uint8List(iv.length + seqBytes.length)
      ..setAll(0, iv)
      ..setAll(iv.length, seqBytes);

    final ciphertext = body.sublist(32);
    final plaintext =
        KlapCrypto.pkcs7Unpad(KlapCrypto.aesCbcDecrypt(key, aesIv, ciphertext));
    final requestJson = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;

    final method = requestJson['method'] as String;
    final params = requestJson['params'] as Map<String, dynamic>?;

    dynamic result;
    switch (method) {
      case 'get_device_info':
        result = {
          'device_on': device.deviceOn,
          'model': device.model,
          'nickname': device.nicknameBase64,
        };
      case 'set_device_info':
        device.deviceOn = params!['device_on'] as bool;
        result = <String, dynamic>{};
      default:
        throw StateError('Fake device: unhandled method "$method"');
    }

    final responseJson = jsonEncode({'error_code': 0, 'result': result});
    final responseCiphertext = KlapCrypto.aesCbcEncrypt(
      key,
      aesIv,
      KlapCrypto.pkcs7Pad(Uint8List.fromList(utf8.encode(responseJson)), 16),
    );
    final sig = KlapCrypto.sha256(
      Uint8List(sigPrefix.length + seqBytes.length + responseCiphertext.length)
        ..setAll(0, sigPrefix)
        ..setAll(sigPrefix.length, seqBytes)
        ..setAll(sigPrefix.length + seqBytes.length, responseCiphertext),
    );

    final responseBody = Uint8List(sig.length + responseCiphertext.length)
      ..setAll(0, sig)
      ..setAll(sig.length, responseCiphertext);

    return TapoHttpResponse(body: responseBody);
  }
}