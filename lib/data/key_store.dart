/// Persistence for the one shared key.
///
/// An interface for two reasons: the platform factory in
/// `key_store_factory.dart` picks an implementation per target, and widget
/// tests supply an in-memory one because the secure store talks to platform
/// channels that a plain widget test has no way to answer.
///
/// This file deliberately imports nothing. `flutter_secure_storage` lives in
/// `secure_key_store.dart` instead, so that a web build -- which must never
/// reach that package's endorsed web implementation, a thin wrapper over
/// localStorage -- does not pull it in through this interface.
abstract interface class KeyStore {
  /// The stored key, or null if none has been saved.
  Future<String?> read();

  /// Saves [key], replacing anything already stored.
  Future<void> write(String key);

  /// Wipes the stored key.
  Future<void> delete();
}

/// A [KeyStore] that keeps the key in memory only.
///
/// Used by widget tests, and -- deliberately -- by the web build. On web there
/// is no store worth writing to: every browser mechanism available
/// (localStorage, sessionStorage, IndexedDB) is readable by any script that
/// reaches the page, so a key written to one is a key handed to whoever
/// compromises the site. In a browser the key lives for the life of the tab and
/// is gone on refresh, and the interface says so out loud.
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
