import 'dart:typed_data';

import 'base62.dart';
import 'glyph_errors.dart';

/// Envelope version byte: PBKDF2-HMAC-SHA256 key stretching.
const int kVersionPbkdf2 = 0x01;

/// Envelope version byte: Argon2id key stretching.
const int kVersionArgon2id = 0x02;

/// Wire format of a Glyph message.
///
/// ```
/// payload  = version (1) || salt (16) || nonce (12) || body (n)
/// framed   = uint32be(payload.length) || payload || zero-pad to a multiple of 8
/// armoured = "GLY1" + base62(framed)
/// ```
///
/// `body` is the AES-GCM ciphertext followed by the 16-byte tag.
class Envelope {
  const Envelope({
    required this.version,
    required this.salt,
    required this.nonce,
    required this.body,
  });

  /// Literal, case-sensitive armour prefix.
  static const String prefix = 'GLY1';

  static const int saltLength = 16;
  static const int nonceLength = 12;
  static const int tagLength = 16;
  static const int _lengthHeaderBytes = 4;
  static const int _blockBytes = 8;

  /// Smallest payload that could possibly be well-formed: header fields plus
  /// an empty ciphertext and its tag.
  static const int _minPayloadLength =
      1 + saltLength + nonceLength + tagLength;

  final int version;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List body;

  /// Whitespace and zero-width characters that messaging apps, mail clients
  /// and terminals inject into a long unbroken string.
  ///
  /// Dart's `\s` already covers tab, newline, form feed, vertical tab,
  /// non-breaking space, the U+2000 block, line/paragraph separators,
  /// ideographic space and the BOM. The explicit additions are the zero-width
  /// characters, which `\s` does not match but which some clients insert as
  /// soft wrap points.
  static final RegExp _junk =
      RegExp(r'[\s\u200b\u200c\u200d\u2060\ufeff]');

  /// Removes every character that could have been introduced in transit.
  static String scrub(String armoured) => armoured.replaceAll(_junk, '');

  /// Serialises this envelope to armoured text.
  String armour() {
    final payloadLength = 1 + salt.length + nonce.length + body.length;
    final framedLength = _padUp(_lengthHeaderBytes + payloadLength);
    final framed = Uint8List(framedLength);

    framed[0] = (payloadLength >> 24) & 0xFF;
    framed[1] = (payloadLength >> 16) & 0xFF;
    framed[2] = (payloadLength >> 8) & 0xFF;
    framed[3] = payloadLength & 0xFF;

    var at = _lengthHeaderBytes;
    framed[at++] = version;
    framed.setRange(at, at + salt.length, salt);
    at += salt.length;
    framed.setRange(at, at + nonce.length, nonce);
    at += nonce.length;
    framed.setRange(at, at + body.length, body);

    return prefix + Base62.encode(framed);
  }

  /// Parses armoured text back into an envelope.
  ///
  /// The input is scrubbed of whitespace first, so a message that was
  /// line-wrapped in transit still parses. The prefix check is
  /// case-sensitive: leniency about case belongs to the UI's direction
  /// detection, not to the decoder.
  static Envelope parse(String armoured) {
    final clean = scrub(armoured);
    if (!clean.startsWith(prefix)) {
      throw const NotGlyphMessage();
    }
    final encoded = clean.substring(prefix.length);
    if (encoded.isEmpty) {
      throw const DamagedMessage();
    }

    final framed = Base62.decode(encoded);
    if (framed.length < _lengthHeaderBytes) {
      throw const DamagedMessage();
    }

    final payloadLength = (framed[0] << 24) |
        (framed[1] << 16) |
        (framed[2] << 8) |
        framed[3];

    final end = _lengthHeaderBytes + payloadLength;
    // The declared length must land inside the frame, and whatever follows it
    // must be padding only -- fewer than 8 bytes, since the frame is padded to
    // the next 8-byte boundary and no further.
    if (payloadLength < _minPayloadLength ||
        end > framed.length ||
        framed.length - end >= _blockBytes) {
      throw const DamagedMessage();
    }

    var at = _lengthHeaderBytes;
    final version = framed[at++];
    if (version != kVersionPbkdf2 && version != kVersionArgon2id) {
      throw UnsupportedVersion(version);
    }

    final salt = Uint8List.sublistView(framed, at, at + saltLength);
    at += saltLength;
    final nonce = Uint8List.sublistView(framed, at, at + nonceLength);
    at += nonceLength;
    final body = Uint8List.sublistView(framed, at, end);

    return Envelope(
      version: version,
      salt: salt,
      nonce: nonce,
      body: body,
    );
  }

  static int _padUp(int length) {
    final remainder = length % _blockBytes;
    return remainder == 0 ? length : length + (_blockBytes - remainder);
  }
}
