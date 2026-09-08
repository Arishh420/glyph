// Command-line benchmark, run with `dart run tool/kdf_bench.dart`.
// Printing to stdout is the entire point of this file.
// ignore_for_file: avoid_print

// Benchmark: how slow is pure-Dart key stretching on this machine?
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

Future<void> main() async {
  final password = SecretKey(utf8.encode('correct horse battery staple'));
  final salt = Uint8List(16);

  for (final memory in [1024, 4096, 16384]) {
    final sw = Stopwatch()..start();
    await Argon2id(memory: memory, parallelism: 1, iterations: 2, hashLength: 32)
        .deriveKey(secretKey: password, nonce: salt);
    sw.stop();
    print('Argon2id m=${memory}KiB t=2 p=1 : ${sw.elapsedMilliseconds} ms');
  }

  for (final iters in [10000, 210000]) {
    final sw = Stopwatch()..start();
    await Pbkdf2.hmacSha256(iterations: iters, bits: 256)
        .deriveKey(secretKey: password, nonce: salt);
    sw.stop();
    print('PBKDF2-HMAC-SHA256 iters=$iters : ${sw.elapsedMilliseconds} ms');
  }
}
