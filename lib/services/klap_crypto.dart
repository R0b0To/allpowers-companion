import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

/// Pure cryptographic primitives for the Tapo "KLAP" local-control protocol.
///
/// Extracted from `_TapoSession` (tapo_service.dart) so the handshake key
/// derivation, AES-CBC encrypt/decrypt, and PKCS#7 padding can be unit
/// tested directly — with plain byte arrays and no HTTP, no sockets, and no
/// real plug. `TapoService`/`_TapoSession` still own the protocol
/// *orchestration* (which requests to send in what order, session/cookie
/// lifecycle, retry policy); this module only answers "given these bytes,
/// what comes out."
///
/// Both a real client and a symmetric fake "device" (as used in
/// `test/services/tapo_service_test.dart`) call these same functions, since
/// KLAP derives identical keys on both ends from the same seeds.
abstract final class KlapCrypto {
  static Uint8List sha1(List<int> bytes) =>
      Uint8List.fromList(crypto.sha1.convert(bytes).bytes);

  static Uint8List sha256(List<int> bytes) =>
      Uint8List.fromList(crypto.sha256.convert(bytes).bytes);

  /// `sha256(sha1(username) ++ sha1(password))` — the KLAP auth hash used
  /// both to prove local-account credentials during the handshake and (via
  /// the `kasa@tp-link.net` / `kasaSetup` factory-default candidate, tried
  /// alongside the real credentials and an empty-credentials fallback in
  /// `_TapoSession._initialize`) to support unconfigured devices.
  static Uint8List calcAuthHash(String username, String password) {
    final uHash = sha1(utf8.encode(username));
    final pHash = sha1(utf8.encode(password));
    final combined = Uint8List(uHash.length + pHash.length)
      ..setAll(0, uHash)
      ..setAll(uHash.length, pHash);
    return sha256(combined);
  }

  static Uint8List randomBytes(int count) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(count, (_) => rng.nextInt(256)));
  }

  static bool bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static int int32BigEndian(Uint8List bytes) {
    return ((bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3])
        .toUnsigned(32);
  }

  static Uint8List toInt32BigEndian(int value) => Uint8List(4)
    ..[0] = (value >> 24) & 0xFF
    ..[1] = (value >> 16) & 0xFF
    ..[2] = (value >> 8) & 0xFF
    ..[3] = value & 0xFF;

  static Uint8List pkcs7Pad(Uint8List data, int blockSize) {
    final padLen = blockSize - (data.length % blockSize);
    return Uint8List(data.length + padLen)
      ..setAll(0, data)
      ..fillRange(data.length, data.length + padLen, padLen);
  }

  static Uint8List pkcs7Unpad(Uint8List data) {
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

  static Uint8List aesCbcEncrypt(Uint8List key, Uint8List iv, Uint8List padded) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(true, ParametersWithIV(KeyParameter(key), iv));
    final out = Uint8List(padded.length);
    var offset = 0;
    while (offset < padded.length) {
      offset += cipher.processBlock(padded, offset, out, offset);
    }
    return out;
  }

  static Uint8List aesCbcDecrypt(Uint8List key, Uint8List iv, Uint8List ciphertext) {
    final cipher = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV(KeyParameter(key), iv));
    final out = Uint8List(ciphertext.length);
    var offset = 0;
    while (offset < ciphertext.length) {
      offset += cipher.processBlock(ciphertext, offset, out, offset);
    }
    return out;
  }

  /// `sha256(prefix ++ local ++ remote ++ auth)` — used with three
  /// different [prefix] values (`'lsk'`, `'iv'`, `'ldk'`) to derive the
  /// AES key, IV+initial-sequence, and HMAC-signing prefix respectively
  /// from the same handshake material, per the KLAP spec.
  static Uint8List deriveKey(
      String prefix, Uint8List local, Uint8List remote, Uint8List auth) {
    final p = utf8.encode(prefix);
    return sha256(
      Uint8List(p.length + local.length + remote.length + auth.length)
        ..setAll(0, p)
        ..setAll(p.length, local)
        ..setAll(p.length + local.length, remote)
        ..setAll(p.length + local.length + remote.length, auth),
    );
  }
}