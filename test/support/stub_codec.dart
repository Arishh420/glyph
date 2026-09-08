import 'dart:async';

import 'package:glyph/core/glyph_codec.dart';
import 'package:glyph/core/glyph_errors.dart';

/// A [GlyphCodec] that returns canned answers immediately.
///
/// Widget tests must not run real key stretching: it is slow, and awaiting a
/// genuine background isolate inside `testWidgets` does not co-operate with
/// the test binding's fake clock.
class StubCodec implements GlyphCodec {
  StubCodec({this.error, this.blockForever = false});

  /// If set, every operation fails with this error.
  final GlyphError? error;

  /// If true, operations never complete, so the running state can be observed.
  final bool blockForever;

  final List<String> encrypted = <String>[];
  final List<String> decrypted = <String>[];
  int clearCacheCalls = 0;
  int disposeCalls = 0;

  @override
  Future<String> encrypt({required String key, required String plaintext}) {
    encrypted.add(plaintext);
    return _answer('GLY1stubencrypted');
  }

  @override
  Future<String> decrypt({required String key, required String armoured}) {
    decrypted.add(armoured);
    return _answer('stub decrypted plaintext');
  }

  Future<String> _answer(String value) {
    if (blockForever) {
      return Completer<String>().future;
    }
    if (error != null) {
      return Future<String>.error(error!);
    }
    return Future<String>.value(value);
  }

  @override
  Future<void> clearCache() async => clearCacheCalls++;

  @override
  Future<void> dispose() async => disposeCalls++;
}
