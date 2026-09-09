/// Selects the key store for the platform being compiled for.
///
/// Native is the default and web is the conditional case, matching
/// `glyph_codec_factory.dart` and for the same reason: if the condition ever
/// failed to resolve, a native build would keep its real secure store rather
/// than silently dropping to an in-memory one and losing the user's key on
/// every launch. A web build that somehow took the native branch would fail
/// loudly at runtime instead, which is the better failure of the two.
///
/// `dart.library.js_interop` is the marker for a web target; `dart:js_interop`
/// exists only there.
library;

export 'key_store_factory_native.dart'
    if (dart.library.js_interop) 'key_store_factory_web.dart';
