import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/ui/glyph_page.dart';

import 'glyph_page_test.dart' show pumpGlyph;

/// The short-key hint is a pure function of the current key: visible whenever
/// the key is usable but under eight graphemes, gone at eight or when cleared.
///
/// It regressed once by being implemented as a one-shot that latched off the
/// first time the key grew past the threshold. That looked reasonable but meant
/// the hint could never reappear, and on a build that restores a saved key the
/// latch tripped during startup, before the user typed anything -- so a tester
/// entering a four-character key saw nothing at all. Hence the "returns" cases
/// below, which are the ones that actually failed.
const String hintText = 'Short key';

Future<void> setKey(WidgetTester tester, String value) async {
  await tester.enterText(find.byKey(GlyphKeys.keyField), value);
  await tester.pumpAndSettle();
}

void expectHint(WidgetTester tester, bool visible, String because) {
  expect(
    find.textContaining(hintText),
    visible ? findsOneWidget : findsNothing,
    reason: because,
  );
}

void main() {
  group('short-key hint, by grapheme count', () {
    testWidgets('shows at 4, 5 and 7 graphemes; hides at 8',
        (WidgetTester tester) async {
      await pumpGlyph(tester);

      for (final key in <String>['abcd', 'abcde', 'abcdefg']) {
        await setKey(tester, key);
        expectHint(tester, true, '"$key" is ${key.length} graphemes, under 8');
      }

      await setKey(tester, 'abcdefgh');
      expectHint(tester, false, 'eight graphemes is the comfortable threshold');
    });

    testWidgets('below the 4-grapheme minimum there is no hint either',
        (WidgetTester tester) async {
      await pumpGlyph(tester);
      // The key is unusable, so the button already says "Enter Key". A hint
      // about length on top of that would be noise.
      await setKey(tester, 'abc');
      expectHint(tester, false, 'three graphemes is not a usable key at all');
    });
  });

  group('short-key hint counts graphemes, not code units', () {
    // Every emoji here is a surrogate pair, so String.length is double the
    // grapheme count. If the threshold ever compared code units, these two
    // cases would both flip.
    testWidgets('four emoji is four graphemes, so the hint shows',
        (WidgetTester tester) async {
      await pumpGlyph(tester);
      const key = '🔑🌙🐙🦊';
      expect(key.length, 8, reason: 'four surrogate pairs');
      await setKey(tester, key);
      expectHint(tester, true, 'four graphemes despite eight code units');
    });

    testWidgets('eight emoji is eight graphemes, so the hint hides',
        (WidgetTester tester) async {
      await pumpGlyph(tester);
      const key = '🔑🌙🐙🦊🎉🧭🛰🪐';
      await setKey(tester, key);
      expectHint(tester, false, 'eight graphemes, whatever the code-unit count');
    });

    testWidgets('a family emoji counts as one grapheme, not several',
        (WidgetTester tester) async {
      await pumpGlyph(tester);
      // One ZWJ sequence plus seven ASCII = 8 graphemes -> no hint. Counting
      // code units would make this 18 and also give no hint, so pair it with
      // the shorter case below to be discriminating.
      await setKey(tester, '👨‍👩‍👧‍👦abcdefg');
      expectHint(tester, false, 'one ZWJ sequence + 7 = 8 graphemes');

      await setKey(tester, '👨‍👩‍👧‍👦abc');
      expectHint(tester, true, 'one ZWJ sequence + 3 = 4 graphemes');
    });
  });

  group('the hint is not a one-shot', () {
    testWidgets('it returns after the key grows past eight and shrinks back',
        (WidgetTester tester) async {
      await pumpGlyph(tester);

      await setKey(tester, 'abcd');
      expectHint(tester, true, 'first time under the threshold');

      await setKey(tester, 'abcdefghij');
      expectHint(tester, false, 'comfortably long');

      await setKey(tester, 'abcd');
      expectHint(tester, true, 'short again, so the hint is true again');
    });

    testWidgets('a long key restored at launch does not suppress it later',
        (WidgetTester tester) async {
      // The exact release-build failure: the stored key is applied during
      // startup, and the old latch tripped on it before any user input.
      await pumpGlyph(tester, storedKey: 'a-comfortably-long-key');
      expectHint(tester, false, 'the restored key is long');

      await setKey(tester, 'abcd');
      expectHint(tester, true, 'a short key typed afterwards must still hint');
    });

    testWidgets('clearing the key removes the hint',
        (WidgetTester tester) async {
      await pumpGlyph(tester);
      await setKey(tester, 'abcd');
      expectHint(tester, true, 'short key');

      await setKey(tester, '');
      expectHint(tester, false, 'no key, nothing to comment on');
    });
  });

  testWidgets('the hint and the green validity tick coexist',
      (WidgetTester tester) async {
    // They occupy different slots -- footer versus the field's suffix icon --
    // and a valid-but-short key must show both.
    await pumpGlyph(tester);
    await setKey(tester, 'abcd');
    expectHint(tester, true, 'short but usable');
    expect(find.byIcon(Icons.check_circle), findsOneWidget,
        reason: 'the key is valid, so the tick shows too');
  });
}
