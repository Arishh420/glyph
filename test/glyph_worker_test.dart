import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/core/glyph_errors.dart';
import 'package:glyph/core/glyph_worker.dart';

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
  });

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
  });

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
  });

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
  });

  test('re-decrypting the same message is served from the derived-key cache',
      () async {
    final armoured = await codec.encrypt(key: key, plaintext: 'cache me');

    final cold = Stopwatch()..start();
    await codec.decrypt(key: key, armoured: armoured);
    cold.stop();

    final warm = Stopwatch()..start();
    await codec.decrypt(key: key, armoured: armoured);
    warm.stop();

    // Argon2id dominates a cold decrypt, so a cached one is far cheaper.
    // Compared loosely: this asserts the cache exists, not a specific speed.
    expect(warm.elapsedMicroseconds, lessThan(cold.elapsedMicroseconds));
    printOnFailure(
      'cold ${cold.elapsedMicroseconds}us, warm ${warm.elapsedMicroseconds}us',
    );
  });

  test('clearing the cache does not break subsequent decrypts', () async {
    final armoured = await codec.encrypt(key: key, plaintext: 'still fine');
    await codec.decrypt(key: key, armoured: armoured);
    await codec.clearCache();
    expect(await codec.decrypt(key: key, armoured: armoured), 'still fine');
  });

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
  });
}
