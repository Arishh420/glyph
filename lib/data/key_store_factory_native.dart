import 'key_store.dart';
import 'secure_key_store.dart';

/// Native key store: the platform keychain, so the key survives a restart.
KeyStore createKeyStore() => SecureKeyStore();

/// Whether this build remembers the key between launches.
const bool kKeyStorePersists = true;
