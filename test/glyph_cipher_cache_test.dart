import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/core/glyph_cipher.dart';

/// The derived-key cache, asserted on its contents rather than on the clock.
///
/// An earlier version of this compared elapsed microseconds between a cold
/// and a warm decrypt. It was flaky under parallel test load, and it could
/// only ever show that something was faster, not that the cache was the
/// reason. Counting entries is both stable and more specific.
void main() {
  late GlyphCipher cipher;

  setUp(() => cipher = GlyphCipher());

  const keyA = 'first-shared-key';
  const keyB = 'second-shared-key';

  test('encrypting caches exactly one derived key', () async {
    expect(cipher.cacheSize, 0);
    await cipher.encrypt(key: keyA, plaintext: 'hello');
    expect(cipher.cacheSize, 1);
  });

  test('re-decrypting the same message adds no new entry', () async {
    final armoured = await cipher.encrypt(key: keyA, plaintext: 'hello');
    expect(cipher.cacheSize, 1);

    // Same key and same salt, so this must hit the existing entry.
    await cipher.decrypt(key: keyA, armoured: armoured);
    expect(cipher.cacheSize, 1);
    await cipher.decrypt(key: keyA, armoured: armoured);
    expect(cipher.cacheSize, 1);
  });

  test('each message caches separately, because each carries its own salt',
      () async {
    await cipher.encrypt(key: keyA, plaintext: 'one');
    await cipher.encrypt(key: keyA, plaintext: 'two');
    // A fresh random salt per message is the whole point, so two messages
    // under one key are two derivations.
    expect(cipher.cacheSize, 2);
  });

  test('a different key against the same message caches separately', () async {
    final armoured = await cipher.encrypt(key: keyA, plaintext: 'hello');
    expect(cipher.cacheSize, 1);

    await expectLater(
      cipher.decrypt(key: keyB, armoured: armoured),
      throwsA(anything),
    );
    expect(cipher.cacheSize, 2);
  });

  test('clearing empties the cache and decrypting still works', () async {
    final armoured = await cipher.encrypt(key: keyA, plaintext: 'hello');
    expect(cipher.cacheSize, 1);

    cipher.clearCache();
    expect(cipher.cacheSize, 0);

    expect(await cipher.decrypt(key: keyA, armoured: armoured), 'hello');
    expect(cipher.cacheSize, 1);
  });

  test('the cache is capped so a long backlog cannot grow it without limit',
      () async {
    // 40 distinct messages, so 40 distinct salts, against a cap of 32.
    for (var i = 0; i < 40; i++) {
      await cipher.encrypt(key: keyA, plaintext: 'message $i');
    }
    expect(cipher.cacheSize, lessThanOrEqualTo(32));
  });
}
