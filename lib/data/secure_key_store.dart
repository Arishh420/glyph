import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'key_store.dart';

/// Keychain on Apple platforms, KeyStore-backed encrypted preferences on
/// Android.
///
/// Kept in its own file so that `key_store.dart` stays import-free and the web
/// factory can reach the interface without dragging `flutter_secure_storage`
/// into a browser bundle.
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
