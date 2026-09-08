// Generates the golden armoured messages used by test/version_vectors_test.dart.
//
// Run with: dart run tool/make_test_vectors.dart
//
// Only needed when a NEW version byte is added: print a vector for it and
// paste it into the test, so the new format is pinned the way 0x01 and 0x02
// are. Regenerating an existing vector defeats its purpose -- the whole point
// is that the bytes never change.
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:glyph/core/envelope.dart';
import 'package:glyph/core/glyph_cipher.dart';
import 'package:glyph/core/key_rules.dart';

/// Fixed, non-random salt and nonce: these are test vectors, not messages.
final Uint8List _salt =
    Uint8List.fromList(List<int>.generate(Envelope.saltLength, (i) => i + 1));
final Uint8List _nonce =
    Uint8List.fromList(List<int>.generate(Envelope.nonceLength, (i) => 200 - i));

const String _key = 'the-frozen-test-key';
const String _plaintext = 'Frozen parameters, frozen output.';

Future<String> _vector(int version) async {
  final password = SecretKey(utf8.encode(KeyRules.normalise(_key)));

  final KdfAlgorithm kdf = switch (version) {
    // These must match GlyphCipher's frozen constants. They are duplicated
    // rather than shared because those constants are private to the cipher,
    // so `main` below decrypts every vector with the real GlyphCipher as a
    // self-check: if these drift, the generator fails instead of quietly
    // emitting a vector that production cannot read.
    kVersionArgon2id => Argon2id(
        memory: 32 * 1024,
        parallelism: 1,
        iterations: 3,
        hashLength: 32,
      ),
    kVersionPbkdf2 => Pbkdf2.hmacSha256(iterations: 210000, bits: 256),
    _ => throw ArgumentError.value(version, 'version'),
  };

  final secretKey = await kdf.deriveKey(secretKey: password, nonce: _salt);
  final box = await AesGcm.with256bits(nonceLength: Envelope.nonceLength)
      .encrypt(
    utf8.encode(_plaintext),
    secretKey: secretKey,
    nonce: _nonce,
    aad: Uint8List.fromList(<int>[version]),
  );

  final body = Uint8List(box.cipherText.length + box.mac.bytes.length)
    ..setRange(0, box.cipherText.length, box.cipherText)
    ..setRange(box.cipherText.length, box.cipherText.length + box.mac.bytes.length,
        box.mac.bytes);

  return Envelope(
    version: version,
    salt: _salt,
    nonce: _nonce,
    body: body,
  ).armour();
}

Future<void> main() async {
  final cipher = GlyphCipher();

  print('key       : $_key');
  print('plaintext : $_plaintext');
  print('');

  for (final (label, version) in <(String, int)>[
    ('0x01 PBKDF2  ', kVersionPbkdf2),
    ('0x02 Argon2id', kVersionArgon2id),
  ]) {
    final armoured = await _vector(version);

    // Self-check: the production cipher must be able to read what was just
    // written. This catches the parameters above drifting from GlyphCipher's.
    final roundTripped = await cipher.decrypt(key: _key, armoured: armoured);
    if (roundTripped != _plaintext) {
      throw StateError('$label vector does not decrypt with GlyphCipher; '
          'the parameters in this file have drifted');
    }

    print('$label : $armoured');
  }

  print('');
  print('Both vectors verified against GlyphCipher.');
}
