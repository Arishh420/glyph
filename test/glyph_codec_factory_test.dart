import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/core/glyph_codec.dart';
import 'package:glyph/core/glyph_codec_factory.dart';
import 'package:glyph/core/glyph_worker.dart';

/// The codec factory picks an implementation per platform: a worker isolate on
/// native, inline on web where `dart:isolate` only throws.
///
/// These tests run on the Dart VM, so they assert the *native* branch. Their
/// job is to catch the conditional export resolving the wrong way and quietly
/// moving key stretching onto the UI thread on a phone -- a regression that
/// would show up as jank rather than as a failure.
void main() {
  test('a native build stretches keys on a worker isolate', () {
    expect(kCodecUsesIsolate, isTrue);
    final codec = createGlyphCodec();
    addTearDown(codec.dispose);
    expect(codec, isA<IsolateGlyphCodec>());
  });

  test('the factory codec round-trips', () async {
    final codec = createGlyphCodec();
    addTearDown(codec.dispose);

    final armoured =
        await codec.encrypt(key: 'factory-test-key', plaintext: 'hello there');
    expect(
      await codec.decrypt(key: 'factory-test-key', armoured: armoured),
      'hello there',
    );
  });

  test('the inline codec is a usable GlyphCodec in its own right', () async {
    // This is the implementation a web build gets, exercised here because a
    // browser cannot run this suite.
    final GlyphCodec codec = InlineGlyphCodec();
    addTearDown(codec.dispose);

    final armoured =
        await codec.encrypt(key: 'inline-test-key', plaintext: 'no isolate');
    expect(
      await codec.decrypt(key: 'inline-test-key', armoured: armoured),
      'no isolate',
    );
  });
}
