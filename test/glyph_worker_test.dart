import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/core/glyph_errors.dart';
import 'package:glyph/core/glyph_worker.dart';

/// Every test that actually drives the isolate is tagged `vm-only`: on the web
/// `dart:isolate` compiles but each call throws `UnsupportedError`, so these
/// are excluded from `flutter test --platform chrome`. See dart_test.yaml.
void main() {
  late IsolateGlyphCodec codec;

  setUp(() => codec = IsolateGlyphCodec());
  tearDown(() => codec.dispose());

  const key = 'worker-isolate-key';

  test('round-trips through the background isolate', () async {
    const plaintext = 'Sent across an isolate boundary and back.';
    final armoured = await codec.encrypt(key: key, plaintext: plaintext);
    expect(armoured.startsWith('GLY1'), isTrue);
    expect(await codec.decrypt(key: key, armoured: armoured), plaintext);
  }, tags: 'vm-only');

  test('typed errors survive the isolate boundary', () async {
    final armoured = await codec.encrypt(key: key, plaintext: 'secret');

    await expectLater(
      codec.decrypt(key: 'a-completely-different-key', armoured: armoured),
      throwsA(isA<WrongKeyOrTampered>()),
    );
    await expectLater(
      codec.decrypt(key: key, armoured: 'just some prose'),
      throwsA(isA<NotGlyphMessage>()),
    );
    await expectLater(
      codec.encrypt(key: 'ab', plaintext: 'x'),
      throwsA(isA<KeyTooShort>()),
    );
  }, tags: 'vm-only');

  test('the error message and detail carry no secrets', () async {
    final armoured = await codec.encrypt(key: key, plaintext: 'the-plaintext');
    try {
      await codec.decrypt(key: 'the-wrong-key', armoured: armoured);
      fail('expected a failure');
    } on GlyphError catch (error) {
      expect(error.message, isNot(contains('the-plaintext')));
      expect(error.message, isNot(contains('the-wrong-key')));
      expect(error.message, isNot(contains(key)));
    }
  }, tags: 'vm-only');

  test('concurrent requests all resolve to the right answers', () async {
    // Several operations in flight at once must not have their replies
    // crossed: each carries its own request id.
    final futures = <Future<String>>[
      for (var i = 0; i < 8; i++) codec.encrypt(key: key, plaintext: 'body $i'),
    ];
    final armoured = await Future.wait(futures);

    for (var i = 0; i < armoured.length; i++) {
      expect(await codec.decrypt(key: key, armoured: armoured[i]), 'body $i');
    }
  }, tags: 'vm-only');

  test('re-decrypting the same message returns the same plaintext', () async {
    // Whether the derived-key cache was used is asserted deterministically in
    // glyph_cipher_cache_test.dart. Comparing wall-clock timings here was
    // flaky: under the load of the full suite running in parallel, the second
    // (cached) call could measure slower than the first.
    final armoured = await codec.encrypt(key: key, plaintext: 'cache me');

    expect(await codec.decrypt(key: key, armoured: armoured), 'cache me');
    expect(await codec.decrypt(key: key, armoured: armoured), 'cache me');
    expect(await codec.decrypt(key: key, armoured: armoured), 'cache me');
  }, tags: 'vm-only');

  test('clearing the cache does not break subsequent decrypts', () async {
    final armoured = await codec.encrypt(key: key, plaintext: 'still fine');
    await codec.decrypt(key: key, armoured: armoured);
    await codec.clearCache();
    expect(await codec.decrypt(key: key, armoured: armoured), 'still fine');
  }, tags: 'vm-only');

  // Deliberately NOT tagged: this one never spawns an isolate, so it passes in
  // a browser too and there is no reason to stop running it there.
  test('clearing the cache before first use is harmless', () async {
    final fresh = IsolateGlyphCodec();
    await fresh.clearCache();
    await fresh.dispose();
  });

  test('using a disposed codec fails cleanly rather than hanging', () async {
    final fresh = IsolateGlyphCodec();
    await fresh.encrypt(key: key, plaintext: 'x');
    await fresh.dispose();
    await expectLater(
      fresh.encrypt(key: key, plaintext: 'y'),
      throwsA(isA<GlyphInternalError>()),
    );
  }, tags: 'vm-only');
}
