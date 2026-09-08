import 'glyph_cipher.dart';

/// The encrypt/decrypt surface the interface talks to.
///
/// An interface rather than a concrete class for two reasons: the application
/// uses an implementation that hands work to a background isolate, while unit
/// tests use a direct in-line one, and widget tests substitute a stub so they
/// never touch real key stretching.
abstract interface class GlyphCodec {
  /// Encrypts [plaintext] under [key], returning armoured `GLY1...` text.
  Future<String> encrypt({required String key, required String plaintext});

  /// Decrypts armoured [armoured] text under [key].
  Future<String> decrypt({required String key, required String armoured});

  /// Discards cached derived keys. Call when the key changes or is forgotten.
  Future<void> clearCache();

  /// Releases any resources held by the implementation.
  Future<void> dispose();
}

/// Runs the cipher on the calling isolate.
///
/// Convenient for unit tests. Not used by the application: key stretching
/// takes long enough to drop frames.
class InlineGlyphCodec implements GlyphCodec {
  InlineGlyphCodec();

  final GlyphCipher _cipher = GlyphCipher();

  @override
  Future<String> encrypt({required String key, required String plaintext}) =>
      _cipher.encrypt(key: key, plaintext: plaintext);

  @override
  Future<String> decrypt({required String key, required String armoured}) =>
      _cipher.decrypt(key: key, armoured: armoured);

  @override
  Future<void> clearCache() async => _cipher.clearCache();

  @override
  Future<void> dispose() async {}
}
