import 'glyph_codec.dart';
import 'glyph_worker.dart';

/// Native codec: key stretching runs on a long-lived background isolate, so
/// it never blocks the UI thread.
GlyphCodec createGlyphCodec() => IsolateGlyphCodec();

/// Whether this build stretches keys off the calling thread.
const bool kCodecUsesIsolate = true;
