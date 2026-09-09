import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/core/glyph_errors.dart';
import 'package:glyph/data/key_store.dart';
import 'package:glyph/main.dart';
import 'package:glyph/ui/glyph_page.dart';

import 'support/stub_codec.dart';

/// Pumps the app and lets the stored-key load settle.
Future<StubCodec> pumpGlyph(
  WidgetTester tester, {
  String? storedKey,
  StubCodec? codec,
}) async {
  final stub = codec ?? StubCodec();
  await tester.pumpWidget(
    GlyphApp(codec: stub, keyStore: InMemoryKeyStore(storedKey)),
  );
  await tester.pumpAndSettle();
  return stub;
}

FilledButton actionButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(GlyphKeys.actionButton));

bool buttonEnabled(WidgetTester tester) =>
    actionButton(tester).onPressed != null;

String buttonText(WidgetTester tester) {
  final button = find.byKey(GlyphKeys.actionButton);
  final text = find.descendant(of: button, matching: find.byType(Text));
  return tester.widget<Text>(text).data ?? '';
}

Future<void> enterInput(WidgetTester tester, String value) async {
  await tester.enterText(find.byKey(GlyphKeys.inputField), value);
  await tester.pump();
}

void main() {
  group('button state machine', () {
    testWidgets('state 1: no valid key shows an enabled "Enter Key"',
        (tester) async {
      await pumpGlyph(tester);

      expect(buttonText(tester), 'Enter Key');
      // Enabled on a touch platform: tapping it raises the keyboard.
      expect(buttonEnabled(tester), isTrue);
    });

    testWidgets('state 1: a key too short to be valid still shows "Enter Key"',
        (tester) async {
      await pumpGlyph(tester);
      await tester.enterText(find.byKey(GlyphKeys.keyField), 'abc');
      await tester.pump();

      expect(buttonText(tester), 'Enter Key');
    });

    testWidgets('state 1 on macOS: the button is disabled instead',
        (tester) async {
      // Reset inside the test body, not in a tear-down: the binding asserts
      // that foundation debug variables are unset before tear-downs run.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pumpGlyph(tester);

        expect(buttonText(tester), 'Enter Key');
        expect(buttonEnabled(tester), isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('state 2: valid key and empty input is disabled',
        (tester) async {
      await pumpGlyph(tester, storedKey: 'a-stored-key');

      expect(buttonText(tester), 'Encrypt / Decrypt');
      expect(buttonEnabled(tester), isFalse);
    });

    testWidgets('state 2: whitespace-only input counts as empty',
        (tester) async {
      await pumpGlyph(tester, storedKey: 'a-stored-key');
      await enterInput(tester, '   \n  ');

      expect(buttonText(tester), 'Encrypt / Decrypt');
      expect(buttonEnabled(tester), isFalse);
    });

    testWidgets('state 3: ordinary text offers an enabled "Encrypt"',
        (tester) async {
      await pumpGlyph(tester, storedKey: 'a-stored-key');
      await enterInput(tester, 'Meet me at six.');

      expect(buttonText(tester), 'Encrypt');
      expect(buttonEnabled(tester), isTrue);
    });

    testWidgets('state 4: GLY1 text offers an enabled "Decrypt"',
        (tester) async {
      await pumpGlyph(tester, storedKey: 'a-stored-key');
      await enterInput(tester, 'GLY1aaaaaaaaaaa');

      expect(buttonText(tester), 'Decrypt');
      expect(buttonEnabled(tester), isTrue);
    });

    testWidgets('state 5: a running operation shows a disabled spinner',
        (tester) async {
      await pumpGlyph(
        tester,
        storedKey: 'a-stored-key',
        codec: StubCodec(blockForever: true),
      );
      await enterInput(tester, 'Meet me at six.');
      await tester.tap(find.byKey(GlyphKeys.actionButton));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(buttonEnabled(tester), isFalse);
    });
  });

  group('direction detection', () {
    testWidgets('flips to Decrypt as soon as the input starts with GLY1',
        (tester) async {
      await pumpGlyph(tester, storedKey: 'a-stored-key');

      await enterInput(tester, 'GLY');
      expect(buttonText(tester), 'Encrypt');

      await enterInput(tester, 'GLY1');
      expect(buttonText(tester), 'Decrypt');

      await enterInput(tester, 'GLY');
      expect(buttonText(tester), 'Encrypt');
    });

    testWidgets('is case-insensitive and tolerates leading whitespace',
        (tester) async {
      await pumpGlyph(tester, storedKey: 'a-stored-key');

      for (final input in <String>[
        'gly1abc',
        'GlY1abc',
        '   GLY1abc',
        '\n\tGLY1abc',
      ]) {
        await enterInput(tester, input);
        expect(buttonText(tester), 'Decrypt', reason: 'for "$input"');
      }
    });

    testWidgets('GLY1 in the middle of the text still means Encrypt',
        (tester) async {
      await pumpGlyph(tester, storedKey: 'a-stored-key');
      await enterInput(tester, 'I got your GLY1abc message');

      expect(buttonText(tester), 'Encrypt');
    });
  });

  group('operations', () {
    testWidgets('encrypting puts the result in the output box', (tester) async {
      final stub = await pumpGlyph(tester, storedKey: 'a-stored-key');
      await enterInput(tester, 'Meet me at six.');
      await tester.tap(find.byKey(GlyphKeys.actionButton));
      await tester.pumpAndSettle();

      expect(stub.encrypted, <String>['Meet me at six.']);
      final output =
          tester.widget<TextField>(find.byKey(GlyphKeys.outputField));
      expect(output.controller?.text, 'GLY1stubencrypted');
      // The input is left alone, so it can be re-sent or edited.
      final input = tester.widget<TextField>(find.byKey(GlyphKeys.inputField));
      expect(input.controller?.text, 'Meet me at six.');
    });

    testWidgets('decrypting routes to the decrypt path', (tester) async {
      final stub = await pumpGlyph(tester, storedKey: 'a-stored-key');
      await enterInput(tester, 'GLY1aaaaaaaaaaa');
      await tester.tap(find.byKey(GlyphKeys.actionButton));
      await tester.pumpAndSettle();

      expect(stub.decrypted, <String>['GLY1aaaaaaaaaaa']);
      expect(stub.encrypted, isEmpty);
    });

    testWidgets('an error shows in red and leaves both boxes untouched',
        (tester) async {
      final stub = await pumpGlyph(
        tester,
        storedKey: 'a-stored-key',
        codec: StubCodec(error: const WrongKeyOrTampered()),
      );
      await enterInput(tester, 'GLY1aaaaaaaaaaa');
      await tester.tap(find.byKey(GlyphKeys.actionButton));
      await tester.pumpAndSettle();

      expect(
        find.text('Wrong key, or the message was changed after it was '
            'encrypted.'),
        findsOneWidget,
      );
      expect(stub.decrypted, hasLength(1));
      final output =
          tester.widget<TextField>(find.byKey(GlyphKeys.outputField));
      expect(output.controller?.text, isEmpty);
      final input = tester.widget<TextField>(find.byKey(GlyphKeys.inputField));
      expect(input.controller?.text, 'GLY1aaaaaaaaaaa');
    });

    testWidgets('the error clears as soon as the input is edited',
        (tester) async {
      await pumpGlyph(
        tester,
        storedKey: 'a-stored-key',
        codec: StubCodec(error: const NotGlyphMessage()),
      );
      await enterInput(tester, 'GLY1aaaaaaaaaaa');
      await tester.tap(find.byKey(GlyphKeys.actionButton));
      await tester.pumpAndSettle();
      expect(find.text("This doesn't look like a Glyph message."),
          findsOneWidget);

      await enterInput(tester, 'GLY1aaaaaaaaaaab');
      expect(find.text("This doesn't look like a Glyph message."), findsNothing);
    });
  });

  group('the key field', () {
    testWidgets('a stored key is loaded on launch', (tester) async {
      await pumpGlyph(tester, storedKey: 'a-stored-key');

      final field = tester.widget<TextField>(find.byKey(GlyphKeys.keyField));
      expect(field.controller?.text, 'a-stored-key');
    });

    testWidgets('is obscured by default and reveals on the eye toggle',
        (tester) async {
      await pumpGlyph(tester, storedKey: 'a-stored-key');
      expect(
        tester.widget<TextField>(find.byKey(GlyphKeys.keyField)).obscureText,
        isTrue,
      );

      await tester.tap(find.byTooltip('Reveal key'));
      await tester.pump();

      expect(
        tester.widget<TextField>(find.byKey(GlyphKeys.keyField)).obscureText,
        isFalse,
      );
    });

    testWidgets('the dice button fills a revealed 16-character key',
        (tester) async {
      await pumpGlyph(tester);
      await tester.tap(find.byTooltip('Generate a random key'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byKey(GlyphKeys.keyField));
      expect(field.controller?.text, matches(RegExp(r'^[0-9A-Za-z]{16}$')));
      // Revealed, because a generated key is no use unless it can be read.
      expect(field.obscureText, isFalse);
    });

    testWidgets('a valid key shows the green check', (tester) async {
      await pumpGlyph(tester);
      expect(find.bySemanticsLabel('Key is valid'), findsNothing);

      await tester.enterText(find.byKey(GlyphKeys.keyField), 'abcd');
      await tester.pump();

      expect(find.bySemanticsLabel('Key is valid'), findsOneWidget);
    });

    testWidgets('the short-key hint tracks the current key',
        (tester) async {
      // This test used to assert the opposite -- that the hint latched off
      // permanently the first time the key grew past eight. That was a
      // misreading of "do not nag": not nagging means no animation, no
      // repetition and nothing to dismiss, not showing once and never again.
      // The latch also tripped during startup on any build that restores a
      // saved key, so a short key typed afterwards produced no hint at all.
      // test/short_key_hint_test.dart covers the boundaries in detail.
      await pumpGlyph(tester);
      const hint = 'Short key — fine for casual use.';

      await tester.enterText(find.byKey(GlyphKeys.keyField), 'abcd');
      await tester.pump();
      expect(find.text(hint), findsOneWidget);

      await tester.enterText(find.byKey(GlyphKeys.keyField), 'abcdefghij');
      await tester.pump();
      expect(find.text(hint), findsNothing);

      await tester.enterText(find.byKey(GlyphKeys.keyField), 'abcd');
      await tester.pump();
      expect(find.text(hint), findsOneWidget);
    });

    testWidgets('forgetting the key clears the field and the cache',
        (tester) async {
      final stub = await pumpGlyph(tester, storedKey: 'a-stored-key');
      final before = stub.clearCacheCalls;

      await tester.tap(find.byTooltip('Forget key'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byKey(GlyphKeys.keyField));
      expect(field.controller?.text, isEmpty);
      expect(stub.clearCacheCalls, greaterThan(before));
      expect(buttonText(tester), 'Enter Key');
    });
  });

  group('per-box controls appear only when the box has content', () {
    testWidgets('the output controls are hidden until there is output',
        (tester) async {
      await pumpGlyph(tester, storedKey: 'a-stored-key');
      expect(find.byTooltip('Copy'), findsNothing);
      expect(find.byTooltip('Clear output'), findsNothing);

      await enterInput(tester, 'Meet me at six.');
      await tester.tap(find.byKey(GlyphKeys.actionButton));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Copy'), findsOneWidget);
      expect(find.byTooltip('Clear output'), findsOneWidget);
    });

    testWidgets('the input clear control is hidden until there is input',
        (tester) async {
      await pumpGlyph(tester, storedKey: 'a-stored-key');
      expect(find.byTooltip('Clear input'), findsNothing);
      // Paste is always available: it is how content gets in.
      expect(find.byTooltip('Paste'), findsOneWidget);

      await enterInput(tester, 'something');
      expect(find.byTooltip('Clear input'), findsOneWidget);
    });

    testWidgets('the key copy control appears only while the key is revealed',
        (tester) async {
      await pumpGlyph(tester, storedKey: 'a-stored-key');
      expect(find.byTooltip('Copy key'), findsNothing);

      await tester.tap(find.byTooltip('Reveal key'));
      await tester.pump();
      expect(find.byTooltip('Copy key'), findsOneWidget);

      await tester.tap(find.byTooltip('Hide key'));
      await tester.pump();
      expect(find.byTooltip('Copy key'), findsNothing);
    });
  });

  group('the output box', () {
    testWidgets('is read-only, caret-free and still selectable',
        (tester) async {
      await pumpGlyph(tester, storedKey: 'a-stored-key');
      final output =
          tester.widget<TextField>(find.byKey(GlyphKeys.outputField));

      expect(output.readOnly, isTrue);
      expect(output.showCursor, isFalse);
      expect(output.enableInteractiveSelection, isTrue);
    });

    testWidgets('shows its placeholder when empty', (tester) async {
      await pumpGlyph(tester, storedKey: 'a-stored-key');
      expect(find.text('Your result appears here'), findsOneWidget);
    });
  });

  group('the input box', () {
    testWidgets('has every text-mangling behaviour disabled', (tester) async {
      await pumpGlyph(tester, storedKey: 'a-stored-key');
      final input = tester.widget<TextField>(find.byKey(GlyphKeys.inputField));

      expect(input.autocorrect, isFalse);
      expect(input.enableSuggestions, isFalse);
      expect(input.textCapitalization, TextCapitalization.none);
      expect(input.smartDashesType, SmartDashesType.disabled);
      expect(input.smartQuotesType, SmartQuotesType.disabled);
    });

    testWidgets('shows its placeholder when empty', (tester) async {
      await pumpGlyph(tester, storedKey: 'a-stored-key');
      expect(
        find.text('Type a message, or paste an encrypted one'),
        findsOneWidget,
      );
    });
  });

  group('focus on launch', () {
    testWidgets('with no stored key, the key field takes focus',
        (tester) async {
      await pumpGlyph(tester);

      final keyField =
          tester.widget<TextField>(find.byKey(GlyphKeys.keyField));
      expect(keyField.focusNode?.hasFocus, isTrue);
    });

    testWidgets('with a usable stored key, focus moves on to the input',
        (tester) async {
      await pumpGlyph(tester, storedKey: 'a-stored-key');

      final inputField =
          tester.widget<TextField>(find.byKey(GlyphKeys.inputField));
      expect(inputField.focusNode?.hasFocus, isTrue);
      final keyField =
          tester.widget<TextField>(find.byKey(GlyphKeys.keyField));
      expect(keyField.focusNode?.hasFocus, isFalse);
    });

    testWidgets('a stored key too short to use leaves focus on the key field',
        (tester) async {
      await pumpGlyph(tester, storedKey: 'ab');

      final keyField =
          tester.widget<TextField>(find.byKey(GlyphKeys.keyField));
      expect(keyField.focusNode?.hasFocus, isTrue);
    });
  });

  testWidgets('the layout sits inside a SafeArea', (tester) async {
    await pumpGlyph(tester, storedKey: 'a-stored-key');
    expect(find.byType(SafeArea), findsWidgets);
  });
}
