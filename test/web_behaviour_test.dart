import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/core/secure_context.dart';
import 'package:glyph/data/key_store_factory.dart';
import 'package:glyph/ui/insecure_context_page.dart';

import 'glyph_page_test.dart' show pumpGlyph;

/// The two behaviours that differ in a browser.
///
/// These run on the Dart VM, so they assert the *native* side of each
/// conditional export -- the same limitation, and the same purpose, as
/// `glyph_codec_factory_test.dart`. A regression that flipped either condition
/// the wrong way would show up here as a notice appearing on a phone, or as a
/// phone being blocked behind a browser-only warning.
void main() {
  group('the no-persistence notice', () {
    testWidgets('is absent on a build that does persist the key',
        (WidgetTester tester) async {
      expect(kKeyStorePersists, isTrue);
      await pumpGlyph(tester);
      expect(find.textContaining('not saved in the browser'), findsNothing);
    });
  });

  group('the secure-context gate', () {
    testWidgets('lets a native build straight through',
        (WidgetTester tester) async {
      expect(isCryptoContextSecure, isTrue);
      await pumpGlyph(tester);
      expect(find.byType(InsecureContextPage), findsNothing);
    });

    testWidgets('explains itself and names the fix when it does show',
        (WidgetTester tester) async {
      // Rendered directly: the condition that triggers it cannot occur on the
      // VM, but the screen a browser would get still has to be correct.
      await tester.pumpWidget(
        const MaterialApp(home: InsecureContextPage()),
      );

      expect(find.textContaining("can't run safely"), findsOneWidget);
      expect(find.textContaining('insecure connection'), findsOneWidget);
      expect(find.textContaining('https://'), findsOneWidget);
      expect(find.textContaining('localhost'), findsOneWidget);
    });

    testWidgets('offers no way past it', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: InsecureContextPage()),
      );

      // A dismissable warning would just be a slower path to the same weaker
      // cryptography, so there is deliberately nothing to press.
      expect(find.byType(TextButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);
    });
  });
}
