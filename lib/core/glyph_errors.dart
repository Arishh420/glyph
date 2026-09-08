/// Typed failures raised by the Glyph codec.
///
/// Every message here is safe to show a user verbatim. Nothing in this file
/// ever carries the key or the plaintext: these objects cross an isolate
/// boundary and may end up in logs.
sealed class GlyphError implements Exception {
  const GlyphError();

  /// Human-readable, user-safe explanation.
  String get message;

  @override
  String toString() => message;
}

/// The input is not a Glyph message at all: no `GLY1` prefix, or characters
/// outside the Base62 alphabet.
final class NotGlyphMessage extends GlyphError {
  const NotGlyphMessage();

  @override
  String get message => "This doesn't look like a Glyph message.";
}

/// The input announces itself as a Glyph message but the frame is unusable:
/// bad block alignment, an impossible length header, or a truncated body.
final class DamagedMessage extends GlyphError {
  const DamagedMessage();

  @override
  String get message => 'This message is incomplete or was damaged in transit.';
}

/// The AES-GCM authentication tag did not verify.
final class WrongKeyOrTampered extends GlyphError {
  const WrongKeyOrTampered();

  @override
  String get message =>
      'Wrong key, or the message was changed after it was encrypted.';
}

/// The envelope version byte is one this build does not know how to read.
final class UnsupportedVersion extends GlyphError {
  const UnsupportedVersion(this.version);

  /// The unrecognised version byte. Not secret.
  final int version;

  @override
  String get message => 'This message was made by a newer version of Glyph.';
}

/// The key failed the minimum-length rule.
final class KeyTooShort extends GlyphError {
  const KeyTooShort();

  @override
  String get message => 'Key must be at least 4 characters.';
}

/// A failure that is not one of the expected cases above.
///
/// Deliberately carries only the runtime type name of the underlying error,
/// never its message: an arbitrary exception's message could contain the key
/// or the plaintext, and this object may be logged.
final class GlyphInternalError extends GlyphError {
  const GlyphInternalError(this.detail);

  /// Runtime type name of the original error. Safe to display or log.
  final String detail;

  @override
  String get message => 'Something went wrong while handling this message.';
}
