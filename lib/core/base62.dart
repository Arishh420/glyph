import 'dart:typed_data';

import 'glyph_errors.dart';

/// Fixed-block Base62 codec.
///
/// Deliberately *not* an arbitrary-precision conversion of the whole message:
/// that is O(n^2) and hangs on a long paragraph. Instead the input is chopped
/// into 8-byte blocks, each block read as a big-endian unsigned 64-bit
/// integer and emitted as exactly 11 Base62 characters, left-padded with '0'.
/// Encoding and decoding are both linear in the length of the input.
///
/// 62^11 (~5.2e19) exceeds 2^64 (~1.8e19), so 11 characters is always enough
/// for 8 bytes; 62^10 (~8.4e17) is not, so 11 is also the minimum.
///
/// Dart's `int` is 64-bit *signed*, so a block with the high bit set would go
/// negative and break `~/`. Every block is therefore carried as a pair of
/// 32-bit halves and the divisions are done as base-2^32 long division.
class Base62 {
  const Base62._();

  /// `0-9 A-Z a-z`, in that order. Strictly alphanumeric: no symbols, so the
  /// armoured text survives any messaging app.
  static const String alphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

  static const int _bytesPerBlock = 8;
  static const int _charsPerBlock = 11;
  static const int _twoPow32 = 0x100000000;

  /// Reverse lookup table, indexed by code unit. -1 means "not Base62".
  static final Int8List _decodeTable = _buildDecodeTable();

  static Int8List _buildDecodeTable() {
    final table = Int8List(128)..fillRange(0, 128, -1);
    for (var i = 0; i < alphabet.length; i++) {
      table[alphabet.codeUnitAt(i)] = i;
    }
    return table;
  }

  /// Encodes [bytes], whose length must be a multiple of 8.
  static String encode(Uint8List bytes) {
    if (bytes.length % _bytesPerBlock != 0) {
      throw ArgumentError.value(
        bytes.length,
        'bytes.length',
        'must be a multiple of $_bytesPerBlock',
      );
    }
    final blocks = bytes.length ~/ _bytesPerBlock;
    final out = Uint8List(blocks * _charsPerBlock);
    var outIndex = 0;

    for (var b = 0; b < blocks; b++) {
      final off = b * _bytesPerBlock;
      var hi = (bytes[off] << 24) |
          (bytes[off + 1] << 16) |
          (bytes[off + 2] << 8) |
          bytes[off + 3];
      var lo = (bytes[off + 4] << 24) |
          (bytes[off + 5] << 16) |
          (bytes[off + 6] << 8) |
          bytes[off + 7];

      // Emit least-significant digit first, filling the 11-char window
      // backwards so the result is big-endian and zero-padded.
      for (var i = _charsPerBlock - 1; i >= 0; i--) {
        // Long division of the 64-bit value [hi, lo] by 62.
        final qHi = hi ~/ 62;
        final current = (hi % 62) * _twoPow32 + lo;
        out[outIndex + i] = alphabet.codeUnitAt(current % 62);
        hi = qHi;
        lo = current ~/ 62;
      }
      outIndex += _charsPerBlock;
    }
    return String.fromCharCodes(out);
  }

  /// Decodes [text], whose length must be a multiple of 11.
  ///
  /// Throws [NotGlyphMessage] if any character is outside the alphabet, and
  /// [DamagedMessage] if the block count is wrong or a block decodes to a
  /// value that cannot fit in 64 bits (roughly 72% of arbitrary 11-character
  /// strings do not, so this catches most corruption).
  static Uint8List decode(String text) {
    // Charset before block alignment, deliberately: a stray non-Base62
    // character means this was never a Glyph message, which is a different
    // (and more useful) thing to tell the user than "damaged in transit".
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit >= 128 || _decodeTable[unit] < 0) {
        throw const NotGlyphMessage();
      }
    }
    if (text.length % _charsPerBlock != 0) {
      throw const DamagedMessage();
    }
    final blocks = text.length ~/ _charsPerBlock;
    final out = Uint8List(blocks * _bytesPerBlock);
    var outIndex = 0;

    for (var b = 0; b < blocks; b++) {
      final off = b * _charsPerBlock;
      var hi = 0;
      var lo = 0;

      for (var i = 0; i < _charsPerBlock; i++) {
        // Already validated above.
        final digit = _decodeTable[text.codeUnitAt(off + i)];
        // Multiply the 64-bit value [hi, lo] by 62, then add the digit.
        final low = lo * 62 + digit;
        lo = low & 0xFFFFFFFF;
        final high = hi * 62 + (low ~/ _twoPow32);
        if (high > 0xFFFFFFFF) {
          // Overflows 64 bits: this was never a valid encoded block.
          throw const DamagedMessage();
        }
        hi = high;
      }

      out[outIndex] = (hi >> 24) & 0xFF;
      out[outIndex + 1] = (hi >> 16) & 0xFF;
      out[outIndex + 2] = (hi >> 8) & 0xFF;
      out[outIndex + 3] = hi & 0xFF;
      out[outIndex + 4] = (lo >> 24) & 0xFF;
      out[outIndex + 5] = (lo >> 16) & 0xFF;
      out[outIndex + 6] = (lo >> 8) & 0xFF;
      out[outIndex + 7] = lo & 0xFF;
      outIndex += _bytesPerBlock;
    }
    return out;
  }
}
