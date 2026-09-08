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
    kVersionArgon2id => Argon2id(
        memory: 16 * 1024,
        parallelism: 1,
        iterations: 2,
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
  print('key       : $_key');
  print('plaintext : $_plaintext');
  print('');
  print('0x01 PBKDF2   : ${await _vector(kVersionPbkdf2)}');
  print('0x02 Argon2id : ${await _vector(kVersionArgon2id)}');
}
