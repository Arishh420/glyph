import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/core/envelope.dart';
import 'package:glyph/core/glyph_codec.dart';
import 'package:glyph/core/glyph_errors.dart';

void main() {
  late GlyphCodec codec;

  setUp(() => codec = InlineGlyphCodec());
  tearDown(() => codec.dispose());

  const key = 'shared-key-42';

  group('round trip returns the exact original', () {
    final cases = <String, String>{
      'plain ASCII': 'Meet me at the usual place at six.',
      'accented Latin': 'Rendez-vous à la gare, très tôt, s’il vous plaît.',
      'CJK': '明日の午後三時に駅で会いましょう。你好。안녕하세요.',
      'emoji': 'Bring 🍕 and 🍺 — the 👨‍👩‍👧‍👦 are coming 🇯🇵',
      'mixed RTL': 'He said مرحبا بالعالم and then שלום עולם, twice.',
      'newlines and tabs': 'line one\nline two\n\n\tindented\r\nwindows ending\n',
      'single character': 'x',
      'empty string': '',
      'whitespace only': '   \n  ',
    };

    cases.forEach((name, plaintext) {
      test(name, () async {
        final armoured = await codec.encrypt(key: key, plaintext: plaintext);
        expect(await codec.decrypt(key: key, armoured: armoured), plaintext);
      });
    });

    test('100,000 character body', () async {
      final plaintext = ('All work and no play. ' * 5000).substring(0, 100000);
      expect(plaintext.length, 100000);
      final armoured = await codec.encrypt(key: key, plaintext: plaintext);
      expect(await codec.decrypt(key: key, armoured: armoured), plaintext);
    });
  });

  test(
    'encrypting the same plaintext twice with the same key produces two '
    'different messages, and both decrypt back to the original',
    () async {
      const plaintext = 'The same message, sent twice.';

      final first = await codec.encrypt(key: key, plaintext: plaintext);
      final second = await codec.encrypt(key: key, plaintext: plaintext);

      // Fresh random salt and nonce per message, so the armoured text differs
      // even though the key and plaintext are identical. This is the property
      // that stops an observer spotting a repeated message.
      expect(first, isNot(second));
      expect(await codec.decrypt(key: key, armoured: first), plaintext);
      expect(await codec.decrypt(key: key, armoured: second), plaintext);
    },
  );

  test('a message line-wrapped every 40 characters still decrypts', () async {
    const plaintext =
        'Messaging apps and mail clients love to insert line breaks into a '
        'long unbroken string. That must not break decryption.';
    final armoured = await codec.encrypt(key: key, plaintext: plaintext);

    final wrapped = StringBuffer();
    for (var i = 0; i < armoured.length; i += 40) {
      wrapped.writeln(
        armoured.substring(i, i + 40 > armoured.length ? armoured.length : i + 40),
      );
    }

    expect(wrapped.toString(), contains('\n'));
    expect(
      await codec.decrypt(key: key, armoured: wrapped.toString()),
      plaintext,
    );
  });

  test('a message padded with exotic Unicode whitespace still decrypts',
      () async {
    const plaintext = 'Survives a hostile clipboard.';
    final armoured = await codec.encrypt(key: key, plaintext: plaintext);
    final middle = armoured.length ~/ 2;
    // Non-breaking space, ideographic space, zero-width space, BOM, newline.
    final mangled = '  \u00a0${armoured.substring(0, middle)}'
        '\u200b\u3000\n\ufeff\u2028${armoured.substring(middle)}   ';

    expect(await codec.decrypt(key: key, armoured: mangled), plaintext);
  });

  group('failure modes', () {
    test('the wrong key raises WrongKeyOrTampered', () async {
      final armoured = await codec.encrypt(key: key, plaintext: 'secret');
      expect(
        () => codec.decrypt(key: 'a-different-key', armoured: armoured),
        throwsA(isA<WrongKeyOrTampered>()),
      );
    });

    test('flipping one character mid-message raises WrongKeyOrTampered',
        () async {
      final armoured = await codec.encrypt(
        key: key,
        plaintext: 'A message long enough to span several Base62 blocks.',
      );
      final body = armoured.substring(Envelope.prefix.length);

      // Mutate the least significant character of a block in the middle of
      // the body. Least significant so the 64-bit block value shifts by less
      // than 62 and cannot overflow into a framing error, and mid-body so it
      // lands on ciphertext rather than the version byte.
      final blocks = body.length ~/ 11;
      final target = Envelope.prefix.length + (blocks ~/ 2) * 11 + 10;
      final original = armoured[target];
      final replacement = original == 'A' ? 'B' : 'A';
      final tampered = armoured.replaceRange(target, target + 1, replacement);

      expect(tampered, isNot(armoured));
      expect(
        () => codec.decrypt(key: key, armoured: tampered),
        throwsA(isA<WrongKeyOrTampered>()),
      );
    });

    test('truncating a valid message raises DamagedMessage', () async {
      final armoured = await codec.encrypt(
        key: key,
        plaintext: 'A message long enough to span several Base62 blocks.',
      );

      // Whole blocks removed: block alignment still holds, but the declared
      // payload length now runs past the end of the frame.
      final shortenedByBlock =
          armoured.substring(0, armoured.length - 22);
      expect(
        () => codec.decrypt(key: key, armoured: shortenedByBlock),
        throwsA(isA<DamagedMessage>()),
      );

      // A partial block: no longer a multiple of 11 characters.
      final shortenedByChars = armoured.substring(0, armoured.length - 5);
      expect(
        () => codec.decrypt(key: key, armoured: shortenedByChars),
        throwsA(isA<DamagedMessage>()),
      );
    });

    test('plain English input raises NotGlyphMessage', () async {
      expect(
        () => codec.decrypt(key: key, armoured: 'Hello, how are you today?'),
        throwsA(isA<NotGlyphMessage>()),
      );
    });

    test('the right prefix with a non-Base62 body raises NotGlyphMessage',
        () async {
      expect(
        () => codec.decrypt(key: key, armoured: 'GLY1 not-base62-at-all!!'),
        throwsA(isA<NotGlyphMessage>()),
      );
    });

    test('an unknown version byte raises UnsupportedVersion', () async {
      // Forge a frame whose version byte is 0x7f but which is otherwise
      // structurally valid, to prove the decoder dispatches on the byte.
      final forged = Envelope(
        version: 0x7f,
        salt: Uint8List(Envelope.saltLength),
        nonce: Uint8List(Envelope.nonceLength),
        body: Uint8List(Envelope.tagLength),
      ).armour();

      expect(
        () => codec.decrypt(key: key, armoured: forged),
        throwsA(isA<UnsupportedVersion>()),
      );
    });

    test('a key shorter than four characters is refused', () async {
      expect(
        () => codec.encrypt(key: 'abc', plaintext: 'hello'),
        throwsA(isA<KeyTooShort>()),
      );
    });

    test('no error message contains the key or the plaintext', () async {
      const secretKey = 'unmistakable-key-material';
      const secretText = 'unmistakable-plaintext';
      final armoured =
          await codec.encrypt(key: secretKey, plaintext: secretText);

      try {
        await codec.decrypt(key: 'wrong-key-entirely', armoured: armoured);
        fail('expected a failure');
      } on GlyphError catch (error) {
        expect(error.message, isNot(contains(secretKey)));
        expect(error.message, isNot(contains(secretText)));
        expect(error.toString(), isNot(contains('wrong-key-entirely')));
      }
    });
  });

  group('keys', () {
    test('a four character key is accepted', () async {
      final armoured = await codec.encrypt(key: 'abcd', plaintext: 'hi');
      expect(await codec.decrypt(key: 'abcd', armoured: armoured), 'hi');
    });

    test('an emoji key round-trips', () async {
      const emojiKey = '🔑🐙🍕👨‍👩‍👧‍👦';
      final armoured = await codec.encrypt(key: emojiKey, plaintext: 'hi');
      expect(await codec.decrypt(key: emojiKey, armoured: armoured), 'hi');
    });

    test('the same key composed as NFC decrypts a message made with NFD',
        () async {
      // 'caf\u00e9' precomposed, versus 'cafe' plus a combining acute
      // accent. Written as escapes because the two forms are visually
      // identical: an editor that normalised this file would otherwise
      // silently turn this into a test of nothing.
      const nfc = 'caf\u00e9';
      const nfd = 'cafe\u0301';
      expect(nfc, isNot(nfd));

      final armoured = await codec.encrypt(key: nfd, plaintext: 'hi');
      expect(await codec.decrypt(key: nfc, armoured: armoured), 'hi');

      final other = await codec.encrypt(key: nfc, plaintext: 'hi');
      expect(await codec.decrypt(key: nfd, armoured: other), 'hi');
    });

    test('surrounding whitespace in a key is ignored', () async {
      final armoured = await codec.encrypt(key: '  abcd \n', plaintext: 'hi');
      expect(await codec.decrypt(key: 'abcd', armoured: armoured), 'hi');
    });
  });

  test('armoured output is GLY1 followed only by 0-9 A-Z a-z', () async {
    final samples = <String>[
      '',
      'x',
      'Bring 🍕 and مرحبا and 明日\n\ttabs',
      'A' * 5000,
    ];

    for (final plaintext in samples) {
      final armoured = await codec.encrypt(key: key, plaintext: plaintext);
      expect(armoured.startsWith(Envelope.prefix), isTrue);
      final body = armoured.substring(Envelope.prefix.length);
      expect(body, matches(RegExp(r'^[0-9A-Za-z]+$')));
    }
  });
}
