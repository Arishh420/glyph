import 'glyph_codec.dart';

/// Web codec: runs on the calling thread, because there is nowhere else.
///
/// `dart:isolate` exists on web only as a stub that throws
/// `UnsupportedError: dart:isolate is not supported on dart4web`, and
/// Flutter's `compute` is, on web, `await null; return callback(message);` --
/// the main thread either way. So [IsolateGlyphCodec] cannot be used here at
/// all, and importing glyph_worker.dart is avoided entirely rather than
/// imported and never called.
///
/// This is affordable only because the shipping KDF is PBKDF2, which reaches
/// Web Crypto and costs about 18 ms. It would not be affordable for Argon2id,
/// which costs about 2 s of compiled JavaScript.
GlyphCodec createGlyphCodec() => InlineGlyphCodec();

/// Whether this build stretches keys off the calling thread.
const bool kCodecUsesIsolate = false;
