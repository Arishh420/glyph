import 'key_store.dart';

/// Web key store: memory only. The key is gone on refresh, by design.
///
/// `flutter_secure_storage` publishes an endorsed web implementation, and it
/// is a wrapper over `window.localStorage`. Everything a browser offers for
/// persistence -- localStorage, sessionStorage, IndexedDB -- is readable by any
/// script running on the page, so persisting the key there would mean that
/// anyone who could inject a script, or anyone who controls the site, could
/// read the one secret the whole app depends on. There is no browser equivalent
/// of the Keychain or the Android KeyStore to fall back to.
///
/// So this build does not persist at all, and `secure_key_store.dart` is not
/// imported here, which keeps `flutter_secure_storage` out of the bundle rather
/// than merely unused. The interface shows a permanent line saying the key is
/// not saved, driven by [kKeyStorePersists].
///
/// Note the plugin is still *registered* on web: `flutter_secure_storage_web`
/// is endorsed, so Flutter's generated `web_plugin_registrant.dart` wires it up
/// whether or not anything calls it. Registration alone writes nothing, and
/// that is verified empirically rather than assumed -- see PASS2-REPORT.md.
KeyStore createKeyStore() => InMemoryKeyStore();

/// Whether this build remembers the key between launches.
const bool kKeyStorePersists = false;
