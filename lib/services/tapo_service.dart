import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

class TapoService {
  // Use native HttpClient instead of package:http to control header case sensitivity
  final HttpClient _client = HttpClient();
  final Map<String, _TapoSession> _sessions = {};

  _TapoSession _getSession(String ip, String email, String password) {
    String cleanIp = ip.trim();
    if (cleanIp.startsWith('http://')) {
      cleanIp = cleanIp.substring(7);
    } else if (cleanIp.startsWith('https://')) {
      cleanIp = cleanIp.substring(8);
    }
    if (cleanIp.endsWith('/')) {
      cleanIp = cleanIp.substring(0, cleanIp.length - 1);
    }

    final sessionKey = '$cleanIp:$email';
    if (!_sessions.containsKey(sessionKey)) {
      _sessions[sessionKey] = _TapoSession(
        ip: cleanIp,
        email: email,
        password: password,
        client: _client,
      );
    }
    return _sessions[sessionKey]!;
  }

  /// Establishes/validates the connection to the Tapo plug and returns details.
  Future<String> test({
    required String ip,
    required String email,
    required String password,
  }) async {
    debugPrint('[TapoService] Starting connection test to $ip');
    try {
      final session = _getSession(ip, email, password);
      session.reset(); // Force a fresh handshake for the test

      final info = await session.getDeviceInfo();

      String nickname = 'Unknown';
      if (info['nickname'] != null) {
        try {
          nickname = utf8.decode(base64.decode(info['nickname'] as String));
        } catch (_) {
          nickname = info['nickname'] as String;
        }
      }
      final model = info['model'] ?? 'Unknown';
      final isOn = info['device_on'] ?? false;

      final successMsg = 'Connected successfully to Tapo $model ($nickname). State: ${isOn ? 'ON' : 'OFF'}.';
      debugPrint('[TapoService] Test completed successfully.');
      return successMsg;
    } catch (e, stack) {
      debugPrint('[TapoService] Test failed: $e');
      debugPrint('$stack');
      return 'Failed to connect: $e';
    }
  }

  /// Sets the state (on/off) of the smart plug.
  Future<bool> setOn({
    required String ip,
    required String email,
    required String password,
    required bool on,
  }) async {
    debugPrint('[TapoService] Setting state to: ${on ? 'ON' : 'OFF'}');
    try {
      final session = _getSession(ip, email, password);
      await session.setDeviceStatus(on);
      debugPrint('[TapoService] State set successful.');
      return true;
    } catch (e, stack) {
      debugPrint('[TapoService] setOn failed: $e');
      debugPrint('$stack');
      return false;
    }
  }
}

class _TapoSession {
  final String ip;
  final String email;
  final String password;
  final HttpClient client;

  Uint8List? key;
  Uint8List? iv;
  int seq = 0;
  Uint8List? sigPrefix;
  String? _cookie;

  _TapoSession({
    required this.ip,
    required this.email,
    required this.password,
    required this.client,
  });

  void reset() {
    key = null;
    iv = null;
    seq = 0;
    sigPrefix = null;
    _cookie = null;
  }

  // --- Cryptographic and Hashing Helpers ---

  Uint8List _sha1(List<int> bytes) {
    return Uint8List.fromList(crypto.sha1.convert(bytes).bytes);
  }

  Uint8List _sha256(List<int> bytes) {
    return Uint8List.fromList(crypto.sha256.convert(bytes).bytes);
  }

  Uint8List _calcAuthHash(String username, String password) {
    final uSha1 = _sha1(utf8.encode(username));
    final pSha1 = _sha1(utf8.encode(password));
    final combined = Uint8List(uSha1.length + pSha1.length);
    combined.setAll(0, uSha1);
    combined.setAll(uSha1.length, pSha1);
    return _sha256(combined);
  }

  Uint8List _getRandomBytes(int count) {
    final random = Random.secure();
    final list = Uint8List(count);
    for (int i = 0; i < count; i++) {
      list[i] = random.nextInt(256);
    }
    return list;
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  int _getInt32BigEndian(Uint8List bytes) {
    int value = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    return value.toSigned(32);
  }

  Uint8List _int32ToBytesBigEndian(int value) {
    final bytes = Uint8List(4);
    bytes[0] = (value >> 24) & 0xFF;
    bytes[1] = (value >> 16) & 0xFF;
    bytes[2] = (value >> 8) & 0xFF;
    bytes[3] = value & 0xFF;
    return bytes;
  }

  Uint8List _pad(Uint8List data, int blockSize) {
    final padLength = blockSize - (data.length % blockSize);
    final padded = Uint8List(data.length + padLength);
    padded.setAll(0, data);
    padded.fillRange(data.length, padded.length, padLength);
    return padded;
  }

  Uint8List _unpad(Uint8List data) {
    if (data.isEmpty) return data;
    final padLength = data.last;
    if (padLength < 1 || padLength > 16) {
      throw Exception('Invalid PKCS7 padding: $padLength');
    }
    return data.sublist(0, data.length - padLength);
  }

  Uint8List _aesCbcEncrypt(Uint8List keyBytes, Uint8List ivBytes, Uint8List paddedPlaintext) {
    final cbc = CBCBlockCipher(AESEngine())
      ..init(true, ParametersWithIV<KeyParameter>(KeyParameter(keyBytes), ivBytes));
    final cipherText = Uint8List(paddedPlaintext.length);
    var offset = 0;
    while (offset < paddedPlaintext.length) {
      offset += cbc.processBlock(paddedPlaintext, offset, cipherText, offset);
    }
    return cipherText;
  }

  Uint8List _aesCbcDecrypt(Uint8List keyBytes, Uint8List ivBytes, Uint8List cipherText) {
    final cbc = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV<KeyParameter>(KeyParameter(keyBytes), ivBytes));
    final plainText = Uint8List(cipherText.length);
    var offset = 0;
    while (offset < cipherText.length) {
      offset += cbc.processBlock(cipherText, offset, plainText, offset);
    }
    return plainText;
  }

  // --- Case-Preserved HTTP Client ---

  Future<Uint8List> _postRaw(String path, Uint8List data, {Map<String, String>? queryParams}) async {
    var url = 'http://$ip/app/$path';
    if (queryParams != null && queryParams.isNotEmpty) {
      final queryStr = Uri(queryParameters: queryParams).query;
      url += '?$queryStr';
    }
    final uri = Uri.parse(url);

    try {
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 4));

      // Force case preservation on all request headers (some Tapo firmware
      // is strict about header casing).
      request.headers.add('Host', uri.host, preserveHeaderCase: true);
      request.headers.add('User-Agent', 'python-requests/2.28.1', preserveHeaderCase: true);
      request.headers.add('Accept', '*/*', preserveHeaderCase: true);
      request.headers.add('Accept-Encoding', 'gzip, deflate', preserveHeaderCase: true);
      request.headers.add('Connection', 'keep-alive', preserveHeaderCase: true);
      request.headers.add('Content-Length', data.length.toString(), preserveHeaderCase: true);

      if (_cookie != null) {
        request.headers.add('Cookie', _cookie!, preserveHeaderCase: true);
      }

      request.add(data);
      final response = await request.close();

      if (response.statusCode != 200) {
        debugPrint('[Tapo HTTP] $path returned HTTP ${response.statusCode}.');
        // Drain the body (with its own timeout) so the connection is left
        // in a clean, reusable state instead of being abandoned mid-read.
        await response.drain<List<int>>().timeout(const Duration(seconds: 6));
        throw Exception('HTTP Error: ${response.statusCode} - ${response.reasonPhrase}');
      }

      // The connection-setup timeout above doesn't cover the body read: a
      // plug that accepts the connection but never finishes sending data
      // would otherwise hang this call indefinitely.
      final responseBytes =
          await _collectResponseBytes(response).timeout(const Duration(seconds: 6));

      // Read Set-Cookie case-insensitively. Deliberately not logged: it's a
      // live session credential, and dumping it to device logs would let
      // anyone with log access hijack this session.
      final setCookieHeader = response.headers.value('set-cookie');
      if (setCookieHeader != null) {
        final index = setCookieHeader.indexOf(';');
        _cookie = index != -1 ? setCookieHeader.substring(0, index) : setCookieHeader;
      }

      return responseBytes;
    } catch (e) {
      debugPrint('[Tapo HTTP] Request to $path failed: $e');
      rethrow;
    }
  }

  Future<Uint8List> _collectResponseBytes(HttpClientResponse response) async {
    final builder = BytesBuilder();
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  // --- Handshake Sequence ---

  Future<void> initialize() async {
    debugPrint('[Tapo] Starting handshake.');
    final localSeed = _getRandomBytes(16);
    final response = await _postRaw('handshake1', localSeed);

    if (response.length < 48) {
      throw Exception('Handshake1 response payload too short (${response.length} bytes, expected >= 48).');
    }

    final remoteSeed = response.sublist(0, 16);
    final serverHash = response.sublist(16, 48);

    Uint8List? authHash;
    final credentialsToTry = [
      [email, password],
      ['', ''],
      ['kasa@tp-link.net', 'kasaSetup']
    ];

    for (int i = 0; i < credentialsToTry.length; i++) {
      final creds = credentialsToTry[i];
      final ah = _calcAuthHash(creds[0], creds[1]);

      final combined = Uint8List(localSeed.length + remoteSeed.length + ah.length);
      combined.setAll(0, localSeed);
      combined.setAll(localSeed.length, remoteSeed);
      combined.setAll(localSeed.length + remoteSeed.length, ah);

      final localSeedAuthHash = _sha256(combined);

      if (_listEquals(localSeedAuthHash, serverHash)) {
        authHash = ah;
        // Index only: never log the account e-mail/password, even on a
        // successful match.
        debugPrint('[Tapo] Handshake credentials matched (set #$i).');
        break;
      }
    }

    if (authHash == null) {
      throw Exception('Failed to authenticate against the Tapo plug.');
    }

    final combinedHandshake2 = Uint8List(remoteSeed.length + localSeed.length + authHash.length);
    combinedHandshake2.setAll(0, remoteSeed);
    combinedHandshake2.setAll(remoteSeed.length, localSeed);
    combinedHandshake2.setAll(remoteSeed.length + localSeed.length, authHash);

    final handshake2Payload = _sha256(combinedHandshake2);
    await _postRaw('handshake2', handshake2Payload);
    debugPrint('[Tapo] Handshake complete.');

    // key = sha256(b"lsk" + local_seed + remote_seed + auth_hash)[:16]
    final lsk = utf8.encode('lsk');
    final combinedKey = Uint8List(lsk.length + localSeed.length + remoteSeed.length + authHash.length);
    combinedKey.setAll(0, lsk);
    combinedKey.setAll(lsk.length, localSeed);
    combinedKey.setAll(lsk.length + localSeed.length, remoteSeed);
    combinedKey.setAll(lsk.length + localSeed.length + remoteSeed.length, authHash);
    key = _sha256(combinedKey).sublist(0, 16);

    // ivseq = sha256(b"iv" + local_seed + remote_seed + auth_hash)
    final ivPrefix = utf8.encode('iv');
    final combinedIv = Uint8List(ivPrefix.length + localSeed.length + remoteSeed.length + authHash.length);
    combinedIv.setAll(0, ivPrefix);
    combinedIv.setAll(ivPrefix.length, localSeed);
    combinedIv.setAll(ivPrefix.length + localSeed.length, remoteSeed);
    combinedIv.setAll(ivPrefix.length + localSeed.length + remoteSeed.length, authHash);
    final ivseq = _sha256(combinedIv);
    iv = ivseq.sublist(0, 12);

    final last4 = ivseq.sublist(ivseq.length - 4);
    seq = _getInt32BigEndian(last4);

    // sigPrefix = sha256(b"ldk" + local_seed + remote_seed + auth_hash)[:28]
    final ldk = utf8.encode('ldk');
    final combinedSig = Uint8List(ldk.length + localSeed.length + remoteSeed.length + authHash.length);
    combinedSig.setAll(0, ldk);
    combinedSig.setAll(ldk.length, localSeed);
    combinedSig.setAll(ldk.length + localSeed.length, remoteSeed);
    combinedSig.setAll(ldk.length + localSeed.length + remoteSeed.length, authHash);
    sigPrefix = _sha256(combinedSig).sublist(0, 28);

    // Note: key / iv / sigPrefix are intentionally never logged anywhere in
    // this file. They're this session's live encryption material — dumping
    // them to device logs would let anyone with log access decrypt this
    // session's traffic.
  }

  Uint8List _encryptPayload(Uint8List data) {
    seq += 1;
    final seqBytes = _int32ToBytesBigEndian(seq);
    final paddedData = _pad(data, 16);

    final aesIv = Uint8List(iv!.length + seqBytes.length);
    aesIv.setAll(0, iv!);
    aesIv.setAll(iv!.length, seqBytes);

    final ciphertext = _aesCbcEncrypt(key!, aesIv, paddedData);

    final combinedSig = Uint8List(sigPrefix!.length + seqBytes.length + ciphertext.length);
    combinedSig.setAll(0, sigPrefix!);
    combinedSig.setAll(sigPrefix!.length, seqBytes);
    combinedSig.setAll(sigPrefix!.length + seqBytes.length, ciphertext);

    final sig = _sha256(combinedSig);

    final result = Uint8List(sig.length + ciphertext.length);
    result.setAll(0, sig);
    result.setAll(sig.length, ciphertext);
    return result;
  }

  Uint8List _decryptPayload(Uint8List responseBytes) {
    final seqBytes = _int32ToBytesBigEndian(seq);

    final aesIv = Uint8List(iv!.length + seqBytes.length);
    aesIv.setAll(0, iv!);
    aesIv.setAll(iv!.length, seqBytes);

    final ciphertext = responseBytes.sublist(32);
    final decryptedPadded = _aesCbcDecrypt(key!, aesIv, ciphertext);
    return _unpad(decryptedPadded);
  }

  Future<dynamic> request(String method, [Map<String, dynamic>? params]) async {
    if (key == null) {
      await initialize();
    }

    final Map<String, dynamic> payload = {
      'method': method,
    };
    if (params != null) {
      payload['params'] = params;
    }

    try {
      final jsonStr = json.encode(payload);
      final encrypted = _encryptPayload(Uint8List.fromList(utf8.encode(jsonStr)));

      final responseBytes = await _postRaw('request', encrypted, queryParams: {
        'seq': seq.toString(),
      });

      final decryptedBytes = _decryptPayload(responseBytes);
      final decryptedStr = utf8.decode(decryptedBytes);
      // Deliberately not logging jsonStr/decryptedStr: command/response
      // payloads shouldn't be dumped to device logs on every automation
      // cycle. Only the method name and any error code are logged below.
      final data = json.decode(decryptedStr);

      if (data['error_code'] != 0) {
        debugPrint('[Tapo] "$method" returned error_code ${data['error_code']}.');
        reset(); // Wipe session to force re-handshake on next attempt
        throw Exception('Device returned error code: ${data['error_code']}');
      }

      return data['result'];
    } catch (e) {
      reset(); // Ensure handshake is retried next time
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getDeviceInfo() async {
    final result = await request('get_device_info');
    return result as Map<String, dynamic>;
  }

  Future<void> setDeviceStatus(bool on) async {
    await request('set_device_info', {
      'device_on': on,
    });
  }
}