import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/data/key_store.dart';
import 'package:glyph/data/key_store_factory.dart';
import 'package:glyph/data/secure_key_store.dart';

/// The key store factory picks an implementation per platform: the real
/// platform keychain on native, memory only on web.
///
/// These tests run on the Dart VM, so they assert the *native* branch. Their
/// job is to catch the conditional export resolving the wrong way. Both
/// directions are a real defect: web falling through to the native branch would
/// persist the shared key into localStorage, where any script on the page can
/// read it, and native falling through to the web branch would silently forget
/// the user's key on every launch.
void main() {
  test('a native build persists the key in the platform keychain', () {
    expect(kKeyStorePersists, isTrue);
    expect(createKeyStore(), isA<SecureKeyStore>());
  });

  test('the in-memory store a web build gets round-trips within a session', () async {
    // This is the implementation a browser gets, exercised here because a
    // browser cannot run this suite.
    final KeyStore store = InMemoryKeyStore();

    expect(await store.read(), isNull);
    await store.write('shared-key-42');
    expect(await store.read(), 'shared-key-42');
    await store.delete();
    expect(await store.read(), isNull);
  });

  test('an in-memory store starts empty, so a refresh cannot recover a key', () async {
    await InMemoryKeyStore().write('shared-key-42');
    // A new instance is what a page reload produces. Nothing carries over.
    expect(await InMemoryKeyStore().read(), isNull);
  });
}
