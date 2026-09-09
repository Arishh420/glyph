import 'package:flutter/material.dart';

import 'core/glyph_codec.dart';
import 'core/glyph_codec_factory.dart';
import 'data/key_store.dart';
import 'ui/glyph_page.dart';
import 'ui/theme.dart';

void main() {
  runApp(
    GlyphApp(
      // Worker isolate on native, inline on web, where isolates do not exist.
      codec: createGlyphCodec(),
      keyStore: SecureKeyStore(),
    ),
  );
}

/// Root of the application.
///
/// The codec and key store are injected so that tests can supply
/// implementations that neither spawn isolates nor touch platform channels.
class GlyphApp extends StatelessWidget {
  const GlyphApp({
    required this.codec,
    required this.keyStore,
    super.key,
  });

  final GlyphCodec codec;
  final KeyStore keyStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Glyph',
      debugShowCheckedModeBanner: false,
      theme: GlyphTheme.light,
      darkTheme: GlyphTheme.dark,
      themeMode: ThemeMode.system,
      home: GlyphPage(codec: codec, keyStore: keyStore),
    );
  }
}
