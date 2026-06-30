import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Single access point for [FlutterSecureStorage], shared across repositories
/// that handle sensitive credentials (Tapo device passwords, MQTT broker
/// password).
///
/// ## Why a source class?
/// Mirrors the rationale for [SharedPreferencesSource]: a single instance
/// avoids recreating the plugin object on every repository call and makes
/// repositories independently unit-testable by injecting a fake.
///
/// ## Platform security
/// - **Android**: uses [AndroidOptions.encryptedSharedPreferences] — keys are
///   wrapped with AES-256-GCM and stored inside the Android Keystore, which
///   hardware-backs them on supported devices.
/// - **iOS / macOS**: backed by Keychain Services with
///   `kSecAttrAccessibleAfterFirstUnlock`, so secrets survive reboots without
///   requiring the user to unlock again.
///
/// ## Migration from plaintext
/// Repositories that previously stored passwords in SharedPreferences perform
/// a one-time migration on first load: if the secure-storage key is absent
/// but the SharedPreferences JSON contains a plaintext password, the value is
/// copied to secure storage and the plaintext is cleared. Users do not need to
/// re-enter credentials after upgrading.
final class SecureStorageSource {
  const SecureStorageSource();

  static const _storage = FlutterSecureStorage();

  FlutterSecureStorage get storage => _storage;
}