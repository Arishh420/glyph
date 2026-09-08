import 'package:flutter/material.dart';

/// Visual style for the one screen.
///
/// Calm and native-feeling: a muted slate seed colour, Material 3 defaults for
/// everything the platform already gets right, and a monospace stack for the
/// two text areas.
class GlyphTheme {
  const GlyphTheme._();

  /// Seed for both light and dark schemes. Slate rather than a bright hue: the
  /// only saturated colour in the interface should be the action button.
  static const Color seed = Color(0xFF44566C);

  /// Green used for the enabled action button, in light and dark.
  static const Color actionLight = Color(0xFF1B7F4B);
  static const Color actionDark = Color(0xFF3DD68C);

  /// Monospace families, in preference order.
  ///
  /// Deliberately no bundled font file: every one of these ships with its
  /// platform, so the app downloads nothing and adds nothing to its size.
  /// 'monospace' resolves on Android, 'Menlo' and 'SF Mono' on Apple.
  static const List<String> monoFallback = <String>[
    'monospace',
    'SF Mono',
    'Menlo',
    'Consolas',
    'Courier New',
  ];

  static ThemeData get light => _build(Brightness.light);

  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
    );
  }

  /// Text style for the input and output areas.
  static TextStyle monoStyle(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
    return base.copyWith(
      fontFamily: monoFallback.first,
      fontFamilyFallback: monoFallback.sublist(1),
      fontSize: 15,
      height: 1.45,
    );
  }

  /// Colour of the action button when it is enabled.
  static Color actionColour(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? actionDark : actionLight;
}
