import 'dart:convert';
import 'dart:typed_data';

import '../utils/logger.dart';
import 'klap_crypto.dart';
import 'tapo_http_transport.dart';

/// Controls TP-Link Tapo smart plugs via the local KLAP protocol.
///
/// Sessions are keyed by `$ip:$email` and cached in memory so repeated
/// calls to the same plug reuse the negotiated encryption context.
///
/// ## Session cache eviction
/// [_sessions] is bounded at [_maxSessions] entries using LRU eviction.
/// Without a cap, a user who edits a device's IP repeatedly, or adds and
/// removes many plugs over time, accumulates session objects (each holding
/// AES key material and an open connection's keep-alive state) that are
/// never freed until [dispose] is called — which in practice means "never,
/// for the lifetime of the app process." [_getOrCreateSession] promotes a
/// key to most-recently-used on every access; insertion evicts the
/// least-recently-used entry once the cap is exceeded.
///
/// ## Retry policy
/// [isOn] and [setOn] both need the same "try once, wait 2s, retry once,
/// give up" shape — plug Wi-Fi is flaky enough that a bare single attempt
/// produces user-visible false failures. [_withRetry] centralizes that
/// shape so the policy (delay, attempt count) only needs to change in one
/// place. [getDeviceInfo] deliberately has no retry — it's the polling path
/// called every 30 seconds by [TapoDeviceService], so a transient failure
/// there just waits for the next poll rather than doubling network chatter.
///
/// ## Testability
/// The HTTP transport is abstracted behind [TapoHttpTransport] and the
/// handshake/encryption math behind [KlapCrypto], so
/// `test/services/tapo_service_test.dart` can exercise the full session
/// lifecycle — handshake, retries, session reset, LRU eviction — against a
/// fake in-memory "device" that speaks the real protocol, with no real
/// sockets involved.
final class TapoService {
  TapoService({TapoHttpTransport? transport})
      : _transport = transport ?? HttpClientTapoTransport();

  final TapoHttpTransport _transport;

  /// Insertion order is LRU order: oldest (least-recently-used) entries are
  /// at the front. [_getOrCreateSession] removes-and-reinserts a key to move
  /// it to the back (most-recently-used) on every access.
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
      transport: _transport,
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

  /// Runs [action] once; on failure, waits [retryDelay] and tries exactly
  /// once more. Returns the action's result, or `null` if both attempts
  /// failed. Logs a warning after the first failure and an error if the
  /// retry also fails, tagged with [label] so failures are traceable to the
  /// calling operation (e.g. `"isOn(192.168.1.75)"`, `"setOn ON (...)"`).
  Future<T?> _withRetry<T>(
    String label,
    Future<T> Function() action, {
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    try {
      return await action();
    } catch (e) {
      Log.w('TapoService',
          '$label attempt 1 failed, retrying in ${retryDelay.inSeconds}s — $e');
    }
    try {
      await Future<void>.delayed(retryDelay);
      final result = await action();
      Log.i('TapoService', '$label succeeded on retry');
      return result;
    } catch (e2) {
      Log.e('TapoService', '$label failed after retry', e2);
      return null;
    }
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
    final info = await _withRetry('isOn($ip)', session.getDeviceInfo);
    return info?['device_on'] as bool?;
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
    final ok = await _withRetry('setOn $action ($ip)', () async {
      await session.setDeviceStatus(on);
      return true;
    });
    if (ok == true) {
      Log.i('TapoService', 'Plug $ip set to $action');
    }
    return ok ?? false;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _sessions.clear();
    final transport = _transport;
    if (transport is HttpClientTapoTransport) {
      transport.close(force: true);
    }
    Log.i('TapoService', 'Disposed');
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
    required this.transport,
  });

  final String ip;
  final String email;
  final String password;
  final TapoHttpTransport transport;

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

  Future<Uint8List> _post(
    String path,
    Uint8List body, {
    Map<String, String>? queryParams,
  }) async {
    final response = await transport.post(
      ip,
      path,
      body,
      queryParams: queryParams,
      cookie: _cookie,
    );

    final setCookie = response.setCookie;
    if (setCookie != null) {
      final idx = setCookie.indexOf(';');
      _cookie = idx != -1 ? setCookie.substring(0, idx) : setCookie;
    }

    return response.body;
  }

  Future<void> _initialize() async {
    final localSeed = KlapCrypto.randomBytes(16);
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
      final ah = KlapCrypto.calcAuthHash(candidates[i][0], candidates[i][1]);
      final combined =
          Uint8List(localSeed.length + remoteSeed.length + ah.length)
            ..setAll(0, localSeed)
            ..setAll(localSeed.length, remoteSeed)
            ..setAll(localSeed.length + remoteSeed.length, ah);

      if (KlapCrypto.bytesEqual(KlapCrypto.sha256(combined), serverHash)) {
        authHash = ah;
        Log.i('TapoService', 'Handshake credential set #$i matched');
        break;
      }
    }

    if (authHash == null) {
      throw StateError(
          'Authentication failed — no credential set matched server hash');
    }

    final hs2Payload = KlapCrypto.sha256(
      Uint8List(remoteSeed.length + localSeed.length + authHash.length)
        ..setAll(0, remoteSeed)
        ..setAll(remoteSeed.length, localSeed)
        ..setAll(remoteSeed.length + localSeed.length, authHash),
    );
    await _post('handshake2', hs2Payload);

    _key = KlapCrypto.deriveKey('lsk', localSeed, remoteSeed, authHash)
        .sublist(0, 16);

    final ivSeq = KlapCrypto.deriveKey('iv', localSeed, remoteSeed, authHash);
    _iv = ivSeq.sublist(0, 12);
    _seq = KlapCrypto.int32BigEndian(ivSeq.sublist(ivSeq.length - 4));

    _sigPrefix = KlapCrypto.deriveKey('ldk', localSeed, remoteSeed, authHash)
        .sublist(0, 28);

    Log.i('TapoService', 'KLAP handshake complete for $ip');
  }

  Uint8List _encrypt(Uint8List plaintext) {
    _seq = (_seq + 1).toUnsigned(32);
    final seqBytes = KlapCrypto.toInt32BigEndian(_seq);
    final aesIv = Uint8List(_iv!.length + seqBytes.length)
      ..setAll(0, _iv!)
      ..setAll(_iv!.length, seqBytes);

    final ciphertext = KlapCrypto.aesCbcEncrypt(
        _key!, aesIv, KlapCrypto.pkcs7Pad(plaintext, 16));

    final sigInput = Uint8List(
        _sigPrefix!.length + seqBytes.length + ciphertext.length)
      ..setAll(0, _sigPrefix!)
      ..setAll(_sigPrefix!.length, seqBytes)
      ..setAll(_sigPrefix!.length + seqBytes.length, ciphertext);

    final sig = KlapCrypto.sha256(sigInput);

    return Uint8List(sig.length + ciphertext.length)
      ..setAll(0, sig)
      ..setAll(sig.length, ciphertext);
  }

  Uint8List _decrypt(Uint8List responseBytes) {
    if (responseBytes.length < 32) {
      throw StateError(
          'Response too short (${responseBytes.length} bytes, expected ≥ 32)');
    }
    final seqBytes = KlapCrypto.toInt32BigEndian(_seq);
    final aesIv = Uint8List(_iv!.length + seqBytes.length)
      ..setAll(0, _iv!)
      ..setAll(_iv!.length, seqBytes);

    return KlapCrypto.pkcs7Unpad(
      KlapCrypto.aesCbcDecrypt(_key!, aesIv, responseBytes.sublist(32)),
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