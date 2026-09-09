import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/core/envelope.dart';
import 'package:glyph/core/glyph_cipher.dart';
import 'package:glyph/core/glyph_codec.dart';

/// Golden vectors pinning what each envelope version byte *means*.
///
/// The envelope carries the salt and nonce but not the key-derivation cost
/// parameters, so a version byte is a contract: 0x02 is not "Argon2id", it is
/// "Argon2id with m=32768, t=3, p=1, 32-byte tag". Nothing in the format
/// records that, which makes it exactly the sort of thing that gets tuned by
/// someone with good intentions and breaks every message ever sent.
///
/// These messages were generated once, with the parameters documented at the
/// top of envelope.dart, by `dart run tool/make_test_vectors.dart`. They are
/// decrypted here with a hard-coded key and compared against a hard-coded
/// plaintext.
///
/// **If a test in this file fails, a cost parameter changed.** Do not
/// regenerate the vector to make it pass -- that hides the breakage and ships
/// it. Either put the parameter back, or allocate a new version byte, leave
/// the old one readable, and add a vector for the new one alongside these.
void main() {
  late GlyphCodec codec;

  setUp(() => codec = InlineGlyphCodec());
  tearDown(() => codec.dispose());

  const key = 'the-frozen-test-key';
  const plaintext = 'Frozen parameters, frozen output.';

  /// Version 0x01: PBKDF2-HMAC-SHA256, 210,000 iterations, 32-byte output.
  const pbkdf2Vector =
      'GLY100005th1msd0LOZbhr9R991297iBZC8RiGyiUlZmicTWGIKbgopsdNA0NBnNFzP'
      'ZxYIZhYX3sUV3eLOgYUzbsScGKt3NZy2Xku96rj6EPJHP8jERStTVoetgu';

  /// Version 0x02: Argon2id, m=32768 (32 MiB), t=3, p=1, 32-byte tag.
  const argon2idVector =
      'GLY100005tiABOt0LOZbhr9R991297iBZC8RiGyiUlZmicTWGEK9MMH9enMDy49mBmP'
      'qbhIRYi90mcRoLA3I9dQH4V1995PG6ZsmrpXIM9k907NajzAttNhVWAQ6K';

  test(
    'version 0x01 still means PBKDF2-HMAC-SHA256 at 210,000 iterations',
    () async {
      expect(Envelope.parse(pbkdf2Vector).version, kVersionPbkdf2);
      expect(await codec.decrypt(key: key, armoured: pbkdf2Vector), plaintext);
    },
  );

  test('version 0x02 still means Argon2id at m=32768, t=3, p=1', () async {
    expect(Envelope.parse(argon2idVector).version, kVersionArgon2id);
    expect(await codec.decrypt(key: key, armoured: argon2idVector), plaintext);
  });

  test('this build writes version 0x01, the shipping default', () async {
    // PBKDF2 is the shipping default: one format on every platform, because
    // Argon2id has no Web Crypto equivalent and costs ~2 s in a browser.
    expect(GlyphCipher.currentVersion, kVersionPbkdf2);
    final fresh = await codec.encrypt(key: key, plaintext: plaintext);
    expect(Envelope.parse(fresh).version, kVersionPbkdf2);
  });

  test('nothing this build writes is version 0x02 any more', () async {
    // 0x02 is legacy-readable, never written. Several messages, since the
    // version byte is not randomised but this guards a careless default.
    for (var i = 0; i < 3; i++) {
      final fresh = await codec.encrypt(key: key, plaintext: 'message $i');
      expect(Envelope.parse(fresh).version, isNot(kVersionArgon2id));
    }
  });

  test(
    'both versions decrypt under one key, so old messages keep working',
    () async {
      // The point of dispatching on the version byte: a mailbox containing both
      // formats is readable without the user knowing formats exist.
      expect(await codec.decrypt(key: key, armoured: pbkdf2Vector), plaintext);
      expect(
        await codec.decrypt(key: key, armoured: argon2idVector),
        plaintext,
      );
    },
  );

  test('the vectors are genuinely different messages', () async {
    // Same key, same plaintext, same salt and nonce -- but a different KDF, so
    // a different derived key and therefore different ciphertext. If these
    // ever matched, the generator would be writing the same format twice and
    // the 0x01 path would be untested.
    expect(pbkdf2Vector, isNot(argon2idVector));
  });
}
