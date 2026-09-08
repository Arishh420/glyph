import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/core/key_rules.dart';

void main() {
  group('length', () {
    test('a three character key is rejected, four is accepted', () {
      expect(KeyRules.isValid('abc'), isFalse);
      expect(KeyRules.isValid('abcd'), isTrue);
    });

    test('length is measured after trimming', () {
      expect(KeyRules.isValid('  abc  '), isFalse);
      expect(KeyRules.isValid('  abcd  '), isTrue);
      expect(KeyRules.length('  abcd \n'), 4);
    });

    test('an empty key is rejected', () {
      expect(KeyRules.isValid(''), isFalse);
      expect(KeyRules.isValid('     '), isFalse);
    });

    test('length is counted in grapheme clusters', () {
      // A family emoji is one grapheme but eleven UTF-16 code units.
      const family = '\u{1F468}\u200d\u{1F469}\u200d\u{1F467}\u200d\u{1F466}';
      expect(family.length, greaterThan(4));
      expect(KeyRules.length(family), 1);
      expect(KeyRules.isValid(family), isFalse);

      // A flag is one grapheme built from two regional indicators.
      const flag = '\u{1F1EF}\u{1F1F5}';
      expect(KeyRules.length(flag), 1);
      expect(KeyRules.length('$family$flag$family$flag'), 4);
      expect(KeyRules.isValid('$family$flag$family$flag'), isTrue);
    });

    test('a combining accent does not add to the count', () {
      // 'cafe' plus a combining acute accent is four graphemes, and NFC folds
      // it to four code units as well.
      expect(KeyRules.length('cafe\u0301'), 4);
      expect(KeyRules.normalise('cafe\u0301'), 'caf\u00e9');
      expect(KeyRules.isValid('cafe\u0301'), isTrue);
    });

    test('the upper bound is 512 graphemes', () {
      expect(KeyRules.isValid('a' * 512), isTrue);
      expect(KeyRules.isValid('a' * 513), isFalse);
    });
  });

  group('normalisation', () {
    test('NFD input normalises to the same string as NFC input', () {
      expect(KeyRules.normalise('cafe\u0301'), KeyRules.normalise('caf\u00e9'));
    });

    test('normalisation leaves plain ASCII alone', () {
      expect(KeyRules.normalise('shared-key-42'), 'shared-key-42');
    });

    test('emoji survive normalisation intact', () {
      const family = '\u{1F468}\u200d\u{1F469}\u200d\u{1F467}\u200d\u{1F466}';
      expect(KeyRules.normalise(family), family);
    });

    test('keys are case-sensitive', () {
      expect(KeyRules.normalise('Secret'), isNot(KeyRules.normalise('secret')));
    });
  });

  group('the short-key hint', () {
    test('shows for a valid key under eight graphemes', () {
      expect(KeyRules.isShort('abcd'), isTrue);
      expect(KeyRules.isShort('abcdefg'), isTrue);
    });

    test('does not show at eight graphemes or more', () {
      expect(KeyRules.isShort('abcdefgh'), isFalse);
      expect(KeyRules.isShort('a' * 40), isFalse);
    });

    test('does not show for a key that is too short to be valid at all', () {
      // The invalid-key state has its own presentation; the hint would be
      // noise on top of it.
      expect(KeyRules.isShort('abc'), isFalse);
      expect(KeyRules.isShort(''), isFalse);
    });
  });

  group('generated keys', () {
    test('are 16 strictly alphanumeric characters', () {
      for (var i = 0; i < 50; i++) {
        final key = KeyRules.generate();
        expect(key.length, 16);
        expect(key, matches(RegExp(r'^[0-9A-Za-z]{16}$')));
        expect(KeyRules.isValid(key), isTrue);
        expect(KeyRules.isShort(key), isFalse);
      }
    });

    test('are not repeated', () {
      final keys = {for (var i = 0; i < 200; i++) KeyRules.generate()};
      expect(keys.length, 200);
    });
  });
}
