/// Reports whether the platform can reach a working Web Crypto implementation.
///
/// Native is the default and web is the conditional case, matching
/// `glyph_codec_factory.dart` and `key_store_factory.dart`. If the condition
/// ever failed to resolve, a native build would report "secure" -- which is
/// correct there, since the question is meaningless off the web -- rather than
/// blocking a phone behind a browser-only warning.
///
/// `dart.library.js_interop` is the marker for a web target; `dart:js_interop`
/// exists only there.
library;

export 'secure_context_native.dart'
    if (dart.library.js_interop) 'secure_context_web.dart';
