import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ap_companion/services/klap_crypto.dart';

void main() {
  group('KlapCrypto.pkcs7Pad / pkcs7Unpad', () {
    test('round-trips data shorter than one block', () {
      final data = Uint8List.fromList([1, 2, 3]);
      final padded = KlapCrypto.pkcs7Pad(data, 16);
      expect(padded.length, 16);
      expect(KlapCrypto.pkcs7Unpad(padded), data);
    });

    test('round-trips data that is an exact multiple of the block size '
        '(a full extra padding block is added)', () {
      final data = Uint8List(16); // exactly one block
      final padded = KlapCrypto.pkcs7Pad(data, 16);
      expect(padded.length, 32); // full extra block of padding
      expect(padded.sublist(16), List.filled(16, 16));
      expect(KlapCrypto.pkcs7Unpad(padded), data);
    });

    test('round-trips empty data', () {
      final padded = KlapCrypto.pkcs7Pad(Uint8List(0), 16);
      expect(padded.length, 16);
      expect(KlapCrypto.pkcs7Unpad(padded), Uint8List(0));
    });

    test('unpad throws on empty input', () {
      expect(() => KlapCrypto.pkcs7Unpad(Uint8List(0)), throwsStateError);
    });

    test('unpad throws when the padding byte value is 0', () {
      final bad = Uint8List.fromList([1, 2, 3, 0]);
      expect(() => KlapCrypto.pkcs7Unpad(bad), throwsStateError);
    });

    test('unpad throws when the padding byte value exceeds the data length', () {
      final bad = Uint8List.fromList([1, 2, 200]);
      expect(() => KlapCrypto.pkcs7Unpad(bad), throwsStateError);
    });

    test('unpad throws when the padding bytes are inconsistent', () {
      // Last byte claims 3 bytes of padding, but they don't all match.
      final bad = Uint8List.fromList([1, 2, 9, 3]);
      expect(() => KlapCrypto.pkcs7Unpad(bad), throwsStateError);
    });
  });

  group('KlapCrypto.aesCbcEncrypt / aesCbcDecrypt', () {
    test('round-trips arbitrary padded plaintext', () {
      final key = KlapCrypto.randomBytes(16);
      final iv = KlapCrypto.randomBytes(16);
      final plaintext =
          KlapCrypto.pkcs7Pad(Uint8List.fromList('hello world'.codeUnits), 16);

      final ciphertext = KlapCrypto.aesCbcEncrypt(key, iv, plaintext);
      final decrypted = KlapCrypto.aesCbcDecrypt(key, iv, ciphertext);

      expect(decrypted, plaintext);
    });

    test('a different key produces different ciphertext for the same plaintext',
        () {
      final iv = KlapCrypto.randomBytes(16);
      final plaintext = KlapCrypto.pkcs7Pad(Uint8List(16), 16);

      final c1 =
          KlapCrypto.aesCbcEncrypt(KlapCrypto.randomBytes(16), iv, plaintext);
      final c2 =
          KlapCrypto.aesCbcEncrypt(KlapCrypto.randomBytes(16), iv, plaintext);

      expect(c1, isNot(equals(c2)));
    });
  });

  group('KlapCrypto.calcAuthHash', () {
    test('is deterministic for the same credentials', () {
      final a = KlapCrypto.calcAuthHash('user@example.com', 'password');
      final b = KlapCrypto.calcAuthHash('user@example.com', 'password');
      expect(a, b);
    });

    test('differs when the password changes', () {
      final a = KlapCrypto.calcAuthHash('user@example.com', 'password1');
      final b = KlapCrypto.calcAuthHash('user@example.com', 'password2');
      expect(a, isNot(equals(b)));
    });

    test('differs when the username changes', () {
      final a = KlapCrypto.calcAuthHash('alice@example.com', 'password');
      final b = KlapCrypto.calcAuthHash('bob@example.com', 'password');
      expect(a, isNot(equals(b)));
    });

    test('produces a 32-byte SHA-256 digest', () {
      expect(KlapCrypto.calcAuthHash('a', 'b').length, 32);
    });
  });

  group('KlapCrypto.deriveKey', () {
    final local = KlapCrypto.randomBytes(16);
    final remote = KlapCrypto.randomBytes(16);
    final auth = KlapCrypto.randomBytes(32);

    test('different prefixes derive different keys from the same seeds', () {
      final lsk = KlapCrypto.deriveKey('lsk', local, remote, auth);
      final iv = KlapCrypto.deriveKey('iv', local, remote, auth);
      final ldk = KlapCrypto.deriveKey('ldk', local, remote, auth);

      expect(lsk, isNot(equals(iv)));
      expect(iv, isNot(equals(ldk)));
      expect(lsk, isNot(equals(ldk)));
    });

    test('is deterministic given identical inputs', () {
      final a = KlapCrypto.deriveKey('lsk', local, remote, auth);
      final b = KlapCrypto.deriveKey('lsk', local, remote, auth);
      expect(a, b);
    });

    test('a different remote seed changes the derived key (both sides must '
        'agree on both seeds)', () {
      final a = KlapCrypto.deriveKey('lsk', local, remote, auth);
      final b = KlapCrypto.deriveKey(
          'lsk', local, KlapCrypto.randomBytes(16), auth);
      expect(a, isNot(equals(b)));
    });
  });

  group('KlapCrypto.int32BigEndian / toInt32BigEndian', () {
    test('round-trips zero', () {
      expect(KlapCrypto.int32BigEndian(KlapCrypto.toInt32BigEndian(0)), 0);
    });

    test('round-trips the maximum unsigned 32-bit value', () {
      const maxU32 = 0xFFFFFFFF;
      expect(
          KlapCrypto.int32BigEndian(KlapCrypto.toInt32BigEndian(maxU32)),
          maxU32);
    });

    test('encodes in big-endian byte order', () {
      final bytes = KlapCrypto.toInt32BigEndian(0x01020304);
      expect(bytes, [0x01, 0x02, 0x03, 0x04]);
    });

    test('round-trips an arbitrary mid-range value', () {
      const value = 123456789;
      expect(
          KlapCrypto.int32BigEndian(KlapCrypto.toInt32BigEndian(value)), value);
    });
  });

  group('KlapCrypto.bytesEqual', () {
    test('true for identical byte lists', () {
      expect(KlapCrypto.bytesEqual([1, 2, 3], [1, 2, 3]), isTrue);
    });

    test('false for different lengths', () {
      expect(KlapCrypto.bytesEqual([1, 2, 3], [1, 2]), isFalse);
    });

    test('false for same length but different content', () {
      expect(KlapCrypto.bytesEqual([1, 2, 3], [1, 2, 4]), isFalse);
    });

    test('true for two empty lists', () {
      expect(KlapCrypto.bytesEqual(<int>[], <int>[]), isTrue);
    });
  });
}