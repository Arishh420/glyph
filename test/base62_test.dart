import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/core/base62.dart';
import 'package:glyph/core/glyph_errors.dart';

void main() {
  test('the alphabet is exactly 0-9 A-Z a-z, in that order', () {
    expect(Base62.alphabet.length, 62);
    expect(Base62.alphabet, matches(RegExp(r'^[0-9A-Za-z]+$')));
    expect(Base62.alphabet.substring(0, 10), '0123456789');
    expect(Base62.alphabet.substring(10, 36), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ');
    expect(Base62.alphabet.substring(36), 'abcdefghijklmnopqrstuvwxyz');
    // No duplicates.
    expect(Base62.alphabet.split('').toSet().length, 62);
  });

  test('every 8-byte block becomes exactly 11 characters', () {
    for (final blocks in [1, 2, 5, 100]) {
      final bytes = Uint8List(blocks * 8);
      expect(Base62.encode(bytes).length, blocks * 11);
    }
  });

  test('all-zero and all-ones blocks round-trip', () {
    final zeros = Uint8List(16);
    expect(Base62.decode(Base62.encode(zeros)), zeros);
    // 0xFF... is the largest 64-bit value, the case that would break naive
    // signed-integer arithmetic.
    final ones = Uint8List(16)..fillRange(0, 16, 0xFF);
    expect(Base62.decode(Base62.encode(ones)), ones);
    expect(Base62.encode(zeros), '0' * 22);
  });

  test('random byte blocks round-trip', () {
    final random = Random(20260908);
    for (var trial = 0; trial < 500; trial++) {
      final blocks = 1 + random.nextInt(8);
      final bytes = Uint8List(blocks * 8);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = random.nextInt(256);
      }
      final encoded = Base62.encode(bytes);
      expect(encoded, matches(RegExp(r'^[0-9A-Za-z]+$')));
      expect(Base62.decode(encoded), bytes, reason: 'trial $trial');
    }
  });

  test('encoding rejects input that is not a whole number of blocks', () {
    expect(() => Base62.encode(Uint8List(7)), throwsArgumentError);
    expect(() => Base62.encode(Uint8List(9)), throwsArgumentError);
  });

  test('a character outside the alphabet is NotGlyphMessage', () {
    expect(() => Base62.decode('0000000000!'), throwsA(isA<NotGlyphMessage>()));
    expect(() => Base62.decode('00000-00000'), throwsA(isA<NotGlyphMessage>()));
    // Non-Latin digits are not Base62 either.
    expect(() => Base62.decode('0000000000٤'), throwsA(isA<NotGlyphMessage>()));
  });

  test('a partial block is DamagedMessage', () {
    expect(() => Base62.decode('0'), throwsA(isA<DamagedMessage>()));
    expect(() => Base62.decode('0' * 12), throwsA(isA<DamagedMessage>()));
  });

  test('a block too large for 64 bits is DamagedMessage', () {
    // 'zzzzzzzzzzz' is 62^11 - 1, comfortably above 2^64 - 1.
    expect(() => Base62.decode('z' * 11), throwsA(isA<DamagedMessage>()));
  });

  test('encoding 100,000 characters takes well under two seconds', () {
    // The property under test is that this is linear, not quadratic. An
    // arbitrary-precision implementation would not finish.
    final bytes = Uint8List(100000 + (8 - 100000 % 8) % 8);
    final random = Random(1);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }

    final stopwatch = Stopwatch()..start();
    final encoded = Base62.encode(bytes);
    stopwatch.stop();

    final decodeWatch = Stopwatch()..start();
    final decoded = Base62.decode(encoded);
    decodeWatch.stop();

    expect(decoded, bytes);
    expect(
      stopwatch.elapsedMilliseconds,
      lessThan(2000),
      reason: 'encode took ${stopwatch.elapsedMilliseconds} ms',
    );
    expect(
      decodeWatch.elapsedMilliseconds,
      lessThan(2000),
      reason: 'decode took ${decodeWatch.elapsedMilliseconds} ms',
    );
    printOnFailure(
      'encode ${stopwatch.elapsedMilliseconds} ms, '
      'decode ${decodeWatch.elapsedMilliseconds} ms',
    );
  });
}
