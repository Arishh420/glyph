import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'envelope.dart';
import 'glyph_errors.dart';
import 'key_rules.dart';

/// AES-256-GCM encryption with stretched keys.
///
/// Pure Dart and free of Flutter imports, so it is unit-testable in isolation
/// and can be instantiated inside a worker isolate.
///
/// One instance owns one derived-key cache, so it is meant to be long-lived.
class GlyphCipher {
  GlyphCipher();

  /// Version byte written by this build: PBKDF2-HMAC-SHA256.
  ///
  /// Chosen for one format on every platform rather than for raw cost.
  /// Argon2id is the stronger primitive and is cheaper on native, but it has
  /// no Web Crypto equivalent, so in a browser it costs about 2 s of compiled
  /// JavaScript on the main thread with no isolate available to move it to.
  /// PBKDF2 reaches Web Crypto and lands at about 18 ms there. Splitting the
  /// KDF per platform would have put the slow path on exactly the
  /// cross-platform exchange the web target exists to serve.
  ///
  /// Argon2id remains fully readable as version 0x02, forever. See the
  /// version-byte contract at the top of envelope.dart.
  static const int currentVersion = kVersionPbkdf2;

  // The constants below are the frozen meaning of their version bytes. They
  // are not tuning knobs: the envelope does not record them, so changing one
  // orphans every message already written. See the version-byte contract at
  // the top of envelope.dart before touching them, and allocate a new version
  // byte instead.

  /// Argon2id memory, in 1 KiB blocks. 32768 blocks = 32 MiB.
  ///
  /// The unit is the standard Argon2 `m` parameter: cryptography 2.9.0
  /// documents it as the "number of 1 kB blocks" and allocates
  /// `1024 * blockCount` bytes for it.
  static const int _argonMemoryBlocks = 32 * 1024;

  /// Argon2id passes over memory (`t`).
  static const int _argonIterations = 3;

  /// Argon2id lanes (`p`). One, so derivation is deterministic and single
  /// threaded; on native the work already happens off the UI thread in a
  /// worker isolate.
  static const int _argonParallelism = 1;

  /// PBKDF2 iteration count. Frozen meaning of version byte 0x01, which is
  /// what this build writes.
  static const int _pbkdf2Iterations = 210000;

  /// Derived key length in bytes, for both KDFs: AES-256 needs 32.
  static const int _keyBytes = 32;

  /// Upper bound on cached derived keys. Each entry is 32 bytes plus overhead;
  /// the cap only exists so that decrypting a long backlog cannot grow without
  /// limit.
  static const int _maxCacheEntries = 32;

  final AesGcm _aesGcm = AesGcm.with256bits(nonceLength: Envelope.nonceLength);
  final Random _random = Random.secure();

  /// Derived keys, keyed by version, salt and normalised key. Insertion
  /// ordered so the oldest entry can be evicted.
  final LinkedHashMap<String, SecretKey> _derivedKeys =
      LinkedHashMap<String, SecretKey>();

  /// Forgets every derived key. Call when the key changes or is forgotten.
  void clearCache() => _derivedKeys.clear();

  /// Number of cached derived keys. Exposed for tests.
  int get cacheSize => _derivedKeys.length;

  /// Encrypts [plaintext] under [key], returning armoured text.
  Future<String> encrypt({
    required String key,
    required String plaintext,
  }) async {
    final normalised = _requireUsableKey(key);
    final salt = _randomBytes(Envelope.saltLength);
    final nonce = _randomBytes(Envelope.nonceLength);
    final secretKey = await _deriveKey(normalised, salt, currentVersion);

    final box = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
      nonce: nonce,
      aad: _aadFor(currentVersion),
    );

    // The envelope carries ciphertext and tag as one contiguous body.
    final cipherText = box.cipherText;
    final mac = box.mac.bytes;
    final body = Uint8List(cipherText.length + mac.length)
      ..setRange(0, cipherText.length, cipherText)
      ..setRange(cipherText.length, cipherText.length + mac.length, mac);

    return Envelope(
      version: currentVersion,
      salt: salt,
      nonce: nonce,
      body: body,
    ).armour();
  }

  /// Decrypts [armoured] under [key], returning the original plaintext.
  ///
  /// Throws one of the [GlyphError] subtypes on any failure. Never returns
  /// partially decoded or garbage output.
  Future<String> decrypt({
    required String key,
    required String armoured,
  }) async {
    final normalised = _requireUsableKey(key);
    final envelope = Envelope.parse(armoured);

    if (envelope.body.length < Envelope.tagLength) {
      throw const DamagedMessage();
    }
    final split = envelope.body.length - Envelope.tagLength;
    final cipherText = Uint8List.sublistView(envelope.body, 0, split);
    final mac = Mac(Uint8List.sublistView(envelope.body, split));

    final secretKey = await _deriveKey(
      normalised,
      envelope.salt,
      envelope.version,
    );

    final List<int> clearText;
    try {
      clearText = await _aesGcm.decrypt(
        SecretBox(cipherText, nonce: envelope.nonce, mac: mac),
        secretKey: secretKey,
        aad: _aadFor(envelope.version),
      );
    } on SecretBoxAuthenticationError {
      throw const WrongKeyOrTampered();
    }

    try {
      return utf8.decode(clearText);
    } on FormatException {
      // The tag verified, so this can only happen if something other than
      // Glyph produced the message. Treat it as damaged rather than returning
      // replacement characters.
      throw const DamagedMessage();
    }
  }

  /// The version byte is authenticated as associated data, so a message
  /// cannot be downgraded to a weaker KDF by flipping the byte.
  Uint8List _aadFor(int version) => Uint8List.fromList(<int>[version]);

  String _requireUsableKey(String key) {
    final normalised = KeyRules.normalise(key);
    if (!KeyRules.isValid(normalised)) {
      throw const KeyTooShort();
    }
    return normalised;
  }

  Future<SecretKey> _deriveKey(
    String normalisedKey,
    Uint8List salt,
    int version,
  ) async {
    final cacheKey = '$version:${_hex(salt)}:$normalisedKey';
    final cached = _derivedKeys[cacheKey];
    if (cached != null) {
      return cached;
    }

    final password = SecretKey(utf8.encode(normalisedKey));
    final KdfAlgorithm kdf;
    switch (version) {
      case kVersionArgon2id:
        kdf = Argon2id(
          memory: _argonMemoryBlocks,
          parallelism: _argonParallelism,
          iterations: _argonIterations,
          hashLength: _keyBytes,
        );
      case kVersionPbkdf2:
        kdf = Pbkdf2.hmacSha256(
          iterations: _pbkdf2Iterations,
          bits: _keyBytes * 8,
        );
      default:
        throw UnsupportedVersion(version);
    }

    final derived = await kdf.deriveKey(secretKey: password, nonce: salt);

    if (_derivedKeys.length >= _maxCacheEntries) {
      _derivedKeys.remove(_derivedKeys.keys.first);
    }
    _derivedKeys[cacheKey] = derived;
    return derived;
  }

  Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  static String _hex(Uint8List bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
