import 'dart:math';

import 'package:characters/characters.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Rules governing what counts as a usable shared key.
///
/// The key is a human string agreed out-of-band, so the rules are deliberately
/// permissive: any Unicode, any case, no complexity requirements. The only
/// hard rule is a minimum length.
class KeyRules {
  const KeyRules._();

  /// Minimum length, in grapheme clusters, after normalising and trimming.
  static const int minLength = 4;

  /// Upper bound, generous enough never to be hit in practice.
  static const int maxLength = 512;

  /// At or above this length the "short key" hint is not shown.
  static const int comfortableLength = 8;

  /// Length of a generated key.
  static const int generatedLength = 16;

  /// Alphabet for generated keys: strictly alphanumeric, so a generated key
  /// survives being pasted through any app.
  static const String generatedAlphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

  static final Random _random = Random.secure();

  /// Canonical form of a key, as fed to the key-derivation function.
  ///
  /// Unicode NFC first, then trim. Both sides of a conversation must do this
  /// identically or an accented or emoji key derived on one platform will not
  /// match the same key typed on another: macOS filesystems and some IMEs hand
  /// back NFD, most Android keyboards hand back NFC.
  static String normalise(String raw) => unorm.nfc(raw).trim();

  /// Length in grapheme clusters, so a family emoji or a flag counts as one
  /// character rather than four or five code units.
  static int length(String raw) => normalise(raw).characters.length;

  /// Whether [raw] may be used to encrypt or decrypt.
  static bool isValid(String raw) {
    final count = length(raw);
    return count >= minLength && count <= maxLength;
  }

  /// Whether to show the quiet "short key" hint. Never blocks anything.
  static bool isShort(String raw) {
    final count = length(raw);
    return count >= minLength && count < comfortableLength;
  }

  /// A fresh 16-character key from a cryptographically secure source.
  static String generate() {
    final buffer = StringBuffer();
    for (var i = 0; i < generatedLength; i++) {
      buffer.write(generatedAlphabet[_random.nextInt(generatedAlphabet.length)]);
    }
    return buffer.toString();
  }
}
