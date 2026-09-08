import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/core/envelope.dart';
import 'package:glyph/core/glyph_errors.dart';

Uint8List _filled(int length, int value) =>
    Uint8List(length)..fillRange(0, length, value);

Envelope _sample({int version = kVersionArgon2id, int bodyLength = 32}) =>
    Envelope(
      version: version,
      salt: _filled(Envelope.saltLength, 0xAB),
      nonce: _filled(Envelope.nonceLength, 0xCD),
      body: _filled(bodyLength, 0xEF),
    );

void main() {
  test('armour then parse returns the same fields', () {
    final original = _sample();
    final parsed = Envelope.parse(original.armour());

    expect(parsed.version, original.version);
    expect(parsed.salt, original.salt);
    expect(parsed.nonce, original.nonce);
    expect(parsed.body, original.body);
  });

  test('armoured text starts with the prefix and is otherwise alphanumeric', () {
    final armoured = _sample().armour();
    expect(armoured.startsWith('GLY1'), isTrue);
    expect(armoured.substring(4), matches(RegExp(r'^[0-9A-Za-z]+$')));
  });

  test('the frame is padded to a whole number of 8-byte blocks', () {
    for (var bodyLength = 16; bodyLength < 40; bodyLength++) {
      final armoured = _sample(bodyLength: bodyLength).armour();
      final encoded = armoured.substring(Envelope.prefix.length);
      expect(encoded.length % 11, 0, reason: 'body $bodyLength');
      expect(
        Envelope.parse(armoured).body.length,
        bodyLength,
        reason: 'padding must not leak into the body',
      );
    }
  });

  test('both known version bytes parse', () {
    for (final version in [kVersionPbkdf2, kVersionArgon2id]) {
      expect(Envelope.parse(_sample(version: version).armour()).version,
          version);
    }
  });

  test('an unknown version byte is UnsupportedVersion', () {
    for (final version in [0x00, 0x03, 0x7F, 0xFF]) {
      expect(
        () => Envelope.parse(_sample(version: version).armour()),
        throwsA(isA<UnsupportedVersion>()),
        reason: 'version $version',
      );
    }
  });

  test('UnsupportedVersion reports the byte it found', () {
    try {
      Envelope.parse(_sample(version: 0x42).armour());
      fail('expected UnsupportedVersion');
    } on UnsupportedVersion catch (error) {
      expect(error.version, 0x42);
    }
  });

  group('scrub', () {
    test('removes newlines, tabs and spaces', () {
      expect(Envelope.scrub('GLY 1\tab\ncd \r\n'), 'GLY1abcd');
    });

    test('removes non-breaking and exotic spaces', () {
      expect(
        Envelope.scrub('a\u00a0b\u3000c\u2007d\u205fe'),
        'abcde',
      );
    });

    test('removes zero-width characters and the byte-order mark', () {
      expect(
        Envelope.scrub('a\u200bb\u200cc\u200dd\u2060e\ufeff'),
        'abcde',
      );
    });

    test('removes line and paragraph separators', () {
      expect(Envelope.scrub('a\u2028b\u2029c'), 'abc');
    });

    test('leaves the Base62 alphabet untouched', () {
      const alphabet =
          '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
      expect(Envelope.scrub(alphabet), alphabet);
    });
  });

  group('malformed input', () {
    test('missing prefix is NotGlyphMessage', () {
      expect(() => Envelope.parse('hello there'),
          throwsA(isA<NotGlyphMessage>()));
      expect(() => Envelope.parse(''), throwsA(isA<NotGlyphMessage>()));
    });

    test('the prefix check is case-sensitive', () {
      final armoured = _sample().armour();
      expect(
        () => Envelope.parse(armoured.replaceFirst('GLY1', 'gly1')),
        throwsA(isA<NotGlyphMessage>()),
      );
    });

    test('the prefix alone is DamagedMessage', () {
      expect(() => Envelope.parse('GLY1'), throwsA(isA<DamagedMessage>()));
    });

    test('a payload length that overruns the frame is DamagedMessage', () {
      final armoured = _sample().armour();
      final truncated =
          armoured.substring(0, armoured.length - 11);
      expect(() => Envelope.parse(truncated),
          throwsA(isA<DamagedMessage>()));
    });

    test('a payload too short to hold the header fields is DamagedMessage', () {
      // A single zero block: declared payload length 0, which cannot even
      // hold a version byte, let alone a salt, nonce and tag.
      expect(
        () => Envelope.parse('GLY1${'0' * 11}'),
        throwsA(isA<DamagedMessage>()),
      );
    });
  });
}
