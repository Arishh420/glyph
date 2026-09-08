import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persistence for the one shared key.
///
/// An interface so that widget tests can supply an in-memory implementation:
/// [SecureKeyStore] talks to platform channels, which are not available in a
/// plain widget test.
abstract interface class KeyStore {
  /// The stored key, or null if none has been saved.
  Future<String?> read();

  /// Saves [key], replacing anything already stored.
  Future<void> write(String key);

  /// Wipes the stored key.
  Future<void> delete();
}

/// Keychain on Apple platforms, KeyStore-backed encrypted preferences on
/// Android.
class SecureKeyStore implements KeyStore {
  SecureKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // The default Android options encrypt values with AES-GCM under
              // a key wrapped by RSA-OAEP in the Android KeyStore. This
              // replaces the Jetpack EncryptedSharedPreferences path that
              // earlier versions of the plugin used, which upstream removed
              // after Google deprecated it.
              aOptions: AndroidOptions(),
              // `first_unlock` rather than the default `unlocked`: the key
              // must be readable when the app is relaunched in the background
              // after a reboot, but never before the device is first unlocked.
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
              mOptions: MacOsOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _storage;

  /// Storage slot for the shared key.
  static const String _slot = 'glyph.shared_key.v1';

  @override
  Future<String?> read() => _storage.read(key: _slot);

  @override
  Future<void> write(String key) => _storage.write(key: _slot, value: key);

  @override
  Future<void> delete() => _storage.delete(key: _slot);
}

/// A [KeyStore] that keeps the key in memory only. Used by widget tests.
class InMemoryKeyStore implements KeyStore {
  InMemoryKeyStore([this._value]);

  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String key) async => _value = key;

  @override
  Future<void> delete() async => _value = null;
}
