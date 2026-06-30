import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';

import '../utils/logger.dart';

/// Controls TP-Link Tapo smart plugs via the local KLAP protocol.
///
/// Sessions are keyed by `$ip:$email` and cached in memory so repeated
/// calls to the same plug reuse the negotiated encryption context.
///
/// ## Session cache eviction
/// [_sessions] is bounded at [_maxSessions] entries using LRU eviction.
/// Without a cap, a user who edits a device's IP repeatedly, or adds and
/// removes many plugs over time, accumulates session objects (each holding
/// AES key material and an open `HttpClient` keep-alive state) that are
/// never freed until [dispose] is called — which in practice means "never,
/// for the lifetime of the app process." [_touch] promotes a key to
/// most-recently-used on every access; insertion evicts the least-recently
/// used entry once the cap is exceeded.
final class TapoService {
  final HttpClient _httpClient = HttpClient();

  /// Insertion order is LRU order: oldest (least-recently-used) entries are
  /// at the front. [_touch] removes-and-reinserts a key to move it to the
  /// back (most-recently-used) on every access.
  final Map<String, _TapoSession> _sessions = {};

  /// Maximum number of concurrent sessions kept in memory. Generous enough
  /// that typical households (a handful of plugs) never evict a session
  /// they're actively using, but bounded so editing/re-adding devices over
  /// months doesn't leak memory indefinitely.
  static const int _maxSessions = 16;

  bool _disposed = false;

  _TapoSession _getOrCreateSession(String ip, String email, String password) {
    _assertNotDisposed();
    final cleanIp = _normalizeIp(ip);
    final key = '$cleanIp:$email';

    final existing = _sessions.remove(key);
    if (existing != null) {
      // Re-insert at the back to mark as most-recently-used.
      _sessions[key] = existing;
      return existing;
    }

    final session = _TapoSession(
      ip: cleanIp,
      email: email,
      password: password,
      client: _httpClient,
    );
    _sessions[key] = session;
    _evictIfNeeded();
    return session;
  }

  /// Evicts the least-recently-used session(s) once [_sessions] exceeds
  /// [_maxSessions]. Because [Map] in Dart preserves insertion order and
  /// [_getOrCreateSession] always re-inserts accessed keys at the back,
  /// the first key in iteration order is always the least-recently-used.
  void _evictIfNeeded() {
    while (_sessions.length > _maxSessions) {
      final lruKey = _sessions.keys.first;
      _sessions.remove(lruKey);
      Log.d('TapoService', 'Evicted LRU session: $lruKey');
    }
  }

  static String _normalizeIp(String ip) {
    var clean = ip.trim();
    if (clean.startsWith('https://')) clean = clean.substring(8);
    if (clean.startsWith('http://')) clean = clean.substring(7);
    if (clean.endsWith('/')) clean = clean.substring(0, clean.length - 1);
    return clean;
  }

  void resetSession({required String ip, required String email}) {
    _sessions.remove('${_normalizeIp(ip)}:$email');
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns raw device info map, or null on failure. Used by [TapoDeviceService]
  /// to poll live state across multiple plugs.
  Future<Map<String, dynamic>?> getDeviceInfo({
    required String ip,
    required String email,
    required String password,
  }) async {
    _assertNotDisposed();
    final session = _getOrCreateSession(ip, email, password);
    try {
      return await session.getDeviceInfo();
    } catch (e) {
      Log.w('TapoService', 'getDeviceInfo failed for $ip: $e');
      session.reset();
      return null;
    }
  }

  Future<String> test({
    required String ip,
    required String email,
    required String password,
  }) async {
    _assertNotDisposed();
    final session = _getOrCreateSession(ip, email, password);
    session.reset();

    try {
      final info = await session.getDeviceInfo();
      if (info == null) return 'No response from device';
      final nickname = _decodeNickname(info['nickname']);
      final model = info['model'] as String? ?? 'Unknown';
      final isOn = info['device_on'] as bool? ?? false;
      return 'Connected to Tapo $model ($nickname) — ${isOn ? 'ON' : 'OFF'}';
    } catch (e) {
      Log.e('TapoService', 'Connection test failed', e);
      return 'Connection failed: ${_friendlyError(e)}';
    }
  }

  Future<bool?> isOn({
    required String ip,
    required String email,
    required String password,
  }) async {
    _assertNotDisposed();
    final session = _getOrCreateSession(ip, email, password);
    try {
      final info = await session.getDeviceInfo();
      return info?['device_on'] as bool?;
    } catch (e) {
      Log.w('TapoService', 'isOn attempt 1 failed, retrying in 2 s — $e');
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        final info = await session.getDeviceInfo();
        return info?['device_on'] as bool?;
      } catch (e2) {
        Log.e('TapoService', 'isOn failed after retry', e2);
        return null;
      }
    }
  }

  Future<bool> setOn({
    required String ip,
    required String email,
    required String password,
    required bool on,
  }) async {
    _assertNotDisposed();
    final session = _getOrCreateSession(ip, email, password);
    final action = on ? 'ON' : 'OFF';
    try {
      await session.setDeviceStatus(on);
      Log.i('TapoService', 'Plug $ip set to $action');
      return true;
    } catch (e) {
      Log.w('TapoService', 'setOn $action attempt 1 failed, retrying in 2 s — $e');
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        await session.setDeviceStatus(on);
        Log.i('TapoService', 'Plug $ip set to $action (retry succeeded)');
        return true;
      } catch (e2) {
        Log.e('TapoService', 'setOn $action failed after retry', e2);
        return false;
      }
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _sessions.clear();
    _httpClient.close(force: true);
    Log.i('TapoService', 'Disposed — HttpClient closed');
  }

  void _assertNotDisposed() {
    if (_disposed) {
      throw StateError(
          'TapoService has been disposed and cannot be used further.');
    }
  }

  String _decodeNickname(dynamic raw) {
    if (raw == null) return 'Unknown';
    try {
      return utf8.decode(base64.decode(raw as String));
    } catch (_) {
      return raw.toString();
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('Connection refused') ||
        msg.contains('Failed host lookup')) {
      return 'Plug not reachable — check the IP address';
    }
    if (msg.contains('authenticate')) {
      return 'Authentication failed — check your credentials';
    }
    if (msg.contains('TimeoutException') || msg.contains('timed out')) {
      return 'Request timed out — plug may be offline or unreachable';
    }
    return msg.length > 80 ? '${msg.substring(0, 80)}…' : msg;
  }
}

// ── Internal session implementation ───────────────────────────────────────────

final class _TapoSession {
  _TapoSession({
    required this.ip,
    required this.email,
    required this.password,
    required this.client,
  });

  final String ip;
  final String email;
  final String password;
  final HttpClient client;

  Uint8List? _key;
  Uint8List? _iv;
  int _seq = 0;
  Uint8List? _sigPrefix;
  String? _cookie;

  void reset() {
    _key = null;
    _iv = null;
    _seq = 0;
    _sigPrefix = null;
    _cookie = null;
  }

  bool get _isInitialized => _key != null;

  Uint8List _sha1(List<int> bytes) =>
      Uint8List.fromList(crypto.sha1.convert(bytes).bytes);

  Uint8List _sha256(List<int> bytes) =>
      Uint8List.fromList(crypto.sha256.convert(bytes).bytes);

  Uint8List _calcAuthHash(String username, String pw) {
    final uHash = _sha1(utf8.encode(username));
    final pHash = _sha1(utf8.encode(pw));
    final combined = Uint8List(uHash.length + pHash.length)
      ..setAll(0, uHash)
      ..setAll(uHash.length, pHash);
    return _sha256(combined);
  }

  Uint8List _randomBytes(int count) {
    final rng = Random.secure();
    return Uint8List.fromList(
        List.generate(count, (_) => rng.nextInt(256)));
  }

  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  int _int32BigEndian(Uint8List bytes) {
    return ((bytes[0] << 24) |
            (bytes[1] << 16) |
            (bytes[2] << 8) |
            bytes[3])
        .toUnsigned(32);
  }

  Uint8List _toInt32BigEndian(int value) => Uint8List(4)
    ..[0] = (value >> 24) & 0xFF
    ..[1] = (value >> 16) & 0xFF
    ..[2] = (value >> 8) & 0xFF
    ..[3] = value & 0xFF;

  Uint8List _pkcs7Pad(Uint8List data, int blockSize) {
    final padLen = blockSize - (data.length % blockSize);
    return Uint8List(data.length + padLen)
      ..setAll(0, data)
      ..fillRange(data.length, data.length + padLen, padLen);
  }

  Uint8List _pkcs7Unpad(Uint8List data) {
    if (data.isEmpty) throw StateError('Cannot unpad empty data');
    final padLen = data.last;
    if (padLen < 1 || padLen > 16 || padLen > data.length) {
      throw StateError('Invalid PKCS#7 padding byte length: $padLen');
    }
    for (var i = data.length - padLen; i < data.length; i++) {
      if (data[i] != padLen) {
        throw StateError('PKCS#7 padding values mismatch');
      }
    }
    return data.sublist(0, data.length - padLen);
  }

  Uint8List _aesCbcEncrypt(Uint8List key, Uint8List iv, Uint8List padded) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(true, ParametersWithIV(KeyParameter(key), iv));
    final out = Uint8List(padded.length);
    var offset = 0;
    while (offset < padded.length) {
      offset += cipher.processBlock(padded, offset, out, offset);
    }
    return out;
  }

  Uint8List _aesCbcDecrypt(Uint8List key, Uint8List iv, Uint8List ciphertext) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV(KeyParameter(key), iv));
    final out = Uint8List(ciphertext.length);
    var offset = 0;
    while (offset < ciphertext.length) {
      offset += cipher.processBlock(ciphertext, offset, out, offset);
    }
    return out;
  }

  Future<Uint8List> _post(
    String path,
    Uint8List body, {
    Map<String, String>? queryParams,
  }) async {
    var url = 'http://$ip/app/$path';
    if (queryParams != null && queryParams.isNotEmpty) {
      url += '?${Uri(queryParameters: queryParams).query}';
    }
    final uri = Uri.parse(url);

    final request =
        await client.postUrl(uri).timeout(const Duration(seconds: 6));

    request.headers
      ..add('Host', uri.host, preserveHeaderCase: true)
      ..add('User-Agent', 'python-requests/2.28.1', preserveHeaderCase: true)
      ..add('Accept', '*/*', preserveHeaderCase: true)
      ..add('Accept-Encoding', 'gzip, deflate', preserveHeaderCase: true)
      ..add('Connection', 'keep-alive', preserveHeaderCase: true)
      ..add('Content-Length', body.length.toString(),
          preserveHeaderCase: true);

    if (_cookie != null) {
      request.headers.add('Cookie', _cookie!, preserveHeaderCase: true);
    }

    request.add(body);
    final response = await request.close();

    if (response.statusCode != 200) {
      await response.drain<List<int>>().timeout(const Duration(seconds: 4));
      throw HttpException(
        'HTTP ${response.statusCode} ${response.reasonPhrase}',
        uri: uri,
      );
    }

    final responseBytes =
        await _readResponse(response).timeout(const Duration(seconds: 8));

    final setCookie = response.headers.value('set-cookie');
    if (setCookie != null) {
      final idx = setCookie.indexOf(';');
      _cookie = idx != -1 ? setCookie.substring(0, idx) : setCookie;
    }

    return responseBytes;
  }

  Future<Uint8List> _readResponse(HttpClientResponse response) async {
    final builder = BytesBuilder();
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<void> _initialize() async {
    final localSeed = _randomBytes(16);
    final hs1Response = await _post('handshake1', localSeed);

    if (hs1Response.length < 48) {
      throw StateError(
          'Handshake1 response too short (${hs1Response.length} bytes, expected ≥ 48)');
    }

    final remoteSeed = hs1Response.sublist(0, 16);
    final serverHash = hs1Response.sublist(16, 48);

    final candidates = [
      [email, password],
      ['', ''],
      ['kasa@tp-link.net', 'kasaSetup'],
    ];

    Uint8List? authHash;
    for (var i = 0; i < candidates.length; i++) {
      final ah = _calcAuthHash(candidates[i][0], candidates[i][1]);
      final combined =
          Uint8List(localSeed.length + remoteSeed.length + ah.length)
            ..setAll(0, localSeed)
            ..setAll(localSeed.length, remoteSeed)
            ..setAll(localSeed.length + remoteSeed.length, ah);

      if (_bytesEqual(_sha256(combined), serverHash)) {
        authHash = ah;
        Log.i('TapoService', 'Handshake credential set #$i matched');
        break;
      }
    }

    if (authHash == null) {
      throw StateError(
          'Authentication failed — no credential set matched server hash');
    }

    final hs2Payload = _sha256(
      Uint8List(remoteSeed.length + localSeed.length + authHash.length)
        ..setAll(0, remoteSeed)
        ..setAll(remoteSeed.length, localSeed)
        ..setAll(remoteSeed.length + localSeed.length, authHash),
    );
    await _post('handshake2', hs2Payload);

    _key = _deriveKey('lsk', localSeed, remoteSeed, authHash).sublist(0, 16);

    final ivSeq = _deriveKey('iv', localSeed, remoteSeed, authHash);
    _iv = ivSeq.sublist(0, 12);
    _seq = _int32BigEndian(ivSeq.sublist(ivSeq.length - 4));

    _sigPrefix =
        _deriveKey('ldk', localSeed, remoteSeed, authHash).sublist(0, 28);

    Log.i('TapoService', 'KLAP handshake complete for $ip');
  }

  Uint8List _deriveKey(
      String prefix, Uint8List local, Uint8List remote, Uint8List auth) {
    final p = utf8.encode(prefix);
    return _sha256(
      Uint8List(p.length + local.length + remote.length + auth.length)
        ..setAll(0, p)
        ..setAll(p.length, local)
        ..setAll(p.length + local.length, remote)
        ..setAll(p.length + local.length + remote.length, auth),
    );
  }

  Uint8List _encrypt(Uint8List plaintext) {
    _seq = (_seq + 1).toUnsigned(32);
    final seqBytes = _toInt32BigEndian(_seq);
    final aesIv = Uint8List(_iv!.length + seqBytes.length)
      ..setAll(0, _iv!)
      ..setAll(_iv!.length, seqBytes);

    final ciphertext =
        _aesCbcEncrypt(_key!, aesIv, _pkcs7Pad(plaintext, 16));

    final sigInput = Uint8List(
        _sigPrefix!.length + seqBytes.length + ciphertext.length)
      ..setAll(0, _sigPrefix!)
      ..setAll(_sigPrefix!.length, seqBytes)
      ..setAll(_sigPrefix!.length + seqBytes.length, ciphertext);

    final sig = _sha256(sigInput);

    return Uint8List(sig.length + ciphertext.length)
      ..setAll(0, sig)
      ..setAll(sig.length, ciphertext);
  }

  Uint8List _decrypt(Uint8List responseBytes) {
    if (responseBytes.length < 32) {
      throw StateError(
          'Response too short (${responseBytes.length} bytes, expected ≥ 32)');
    }
    final seqBytes = _toInt32BigEndian(_seq);
    final aesIv = Uint8List(_iv!.length + seqBytes.length)
      ..setAll(0, _iv!)
      ..setAll(_iv!.length, seqBytes);

    return _pkcs7Unpad(
      _aesCbcDecrypt(_key!, aesIv, responseBytes.sublist(32)),
    );
  }

  Future<dynamic> _request(String method,
      [Map<String, dynamic>? params]) async {
    if (!_isInitialized) await _initialize();

    final payload = <String, dynamic>{'method': method};
    if (params != null) payload['params'] = params;

    try {
      final encrypted = _encrypt(
        Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      );
      final responseBytes = await _post(
        'request',
        encrypted,
        queryParams: {'seq': _seq.toString()},
      );

      final decrypted =
          jsonDecode(utf8.decode(_decrypt(responseBytes)))
              as Map<String, dynamic>;

      final errorCode = decrypted['error_code'] as int? ?? -1;
      if (errorCode != 0) {
        reset();
        throw StateError(
            'Device returned error_code $errorCode for "$method"');
      }

      return decrypted['result'];
    } catch (e) {
      reset();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getDeviceInfo() async {
    final result = await _request('get_device_info');
    return result as Map<String, dynamic>;
  }

  Future<void> setDeviceStatus(bool on) async {
    await _request('set_device_info', {'device_on': on});
  }
}