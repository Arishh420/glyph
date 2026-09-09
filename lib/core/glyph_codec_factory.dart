/// Selects the codec implementation for the platform being compiled for.
///
/// Native is the default and web is the conditional case, deliberately: if the
/// condition ever failed to resolve, a native build would keep its worker
/// isolate rather than silently dropping to inline key stretching on the UI
/// thread. A web build that somehow took the native branch would fail loudly
/// at runtime instead, which is the better failure of the two.
///
/// `dart.library.js_interop` is the marker for a web target; `dart:js_interop`
/// exists only there.
library;

export 'glyph_codec_factory_native.dart'
    if (dart.library.js_interop) 'glyph_codec_factory_web.dart';
