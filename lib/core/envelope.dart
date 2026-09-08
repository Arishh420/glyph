import 'dart:typed_data';

import 'base62.dart';
import 'glyph_errors.dart';

// ---------------------------------------------------------------------------
// Version bytes: the wire contract
//
// READ THIS BEFORE CHANGING ANY COST PARAMETER.
//
// The envelope records the salt and the nonce, but NOT the key-derivation cost
// parameters. A version byte therefore has to *imply* them: it is a contract,
// not a label. Change any number in the table below and every message ever
// written under the old value stops decrypting -- and it fails as
// `WrongKeyOrTampered`, which is indistinguishable to the user from having
// typed the wrong key. Silent, permanent, and impossible to diagnose from the
// message alone.
//
// | Byte | KDF                       | Frozen parameters                     |
// |------|---------------------------|---------------------------------------|
// | 0x01 | PBKDF2-HMAC-SHA256        | iterations 210000, dkLen 32 bytes     |
// | 0x02 | Argon2id, RFC 9106 v0x13  | m = 16384, t = 2, p = 1, tag 32 bytes |
//
// Argon2id `m` is the standard memory parameter in 1 KiB blocks, so
// m = 16384 is 16 MiB. That unit is confirmed in cryptography 2.9.0: the
// public API documents `memory` as the "number of 1 kB blocks", and
// `lib/src/dart/argon2_impl_default.dart` allocates `1024 * blockCount` bytes
// with `blockCount = 4 * p * floor(m / 4p)` (RFC 9106's m'). Blocks are
// `Uint32List(256)`, i.e. 1024 bytes each.
//
// Both versions share the rest of the format: AES-256-GCM, a 16-byte salt and
// a 12-byte nonce from the envelope, a 16-byte tag, and the version byte
// itself passed as associated data so it cannot be swapped for a weaker one.
// Argon2id is used with no optional secret and no associated data.
//
// These parameters were chosen by measurement, not taste. On emulator-5554
// (Android 16, arm64, debug/JIT), median of five derivations each:
//
//   m=16384 t=2  ->  101 ms   (chosen)
//   m=32768 t=3  ->  297 ms
//   m=65536 t=3  ->  571 ms   (rejected: over a 500 ms budget on every run)
//
// TO CHANGE A COST PARAMETER: allocate a NEW version byte, make it the value
// of `GlyphCipher.currentVersion`, and keep the old byte readable in
// `GlyphCipher._deriveKey`. Do not edit the numbers above. A future format
// that wants to tune costs freely should record them in the envelope and
// spend a byte on doing so.
// ---------------------------------------------------------------------------

/// Envelope version byte: PBKDF2-HMAC-SHA256 key stretching.
///
/// Frozen: 210,000 iterations, 32-byte output. See the table above.
const int kVersionPbkdf2 = 0x01;

/// Envelope version byte: Argon2id key stretching.
///
/// Frozen: m = 16384 (16 MiB), t = 2, p = 1, 32-byte tag. See the table above.
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
