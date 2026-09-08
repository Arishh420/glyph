import 'dart:async';
import 'dart:isolate';

import 'glyph_cipher.dart';
import 'glyph_codec.dart';
import 'glyph_errors.dart';

/// Opcodes on the wire between the application and the worker isolate.
const int _opEncrypt = 0;
const int _opDecrypt = 1;
const int _opClearCache = 2;

/// Reply tags.
const int _replyOk = 0;
const int _replyGlyphError = 1;
const int _replyUnexpected = 2;

/// Runs [GlyphCipher] on a single long-lived background isolate.
///
/// Long-lived rather than one `Isolate.run` per call, for two reasons: the
/// derived-key cache lives inside the cipher and would be thrown away with a
/// short-lived isolate, and spawning an isolate per keystroke-triggered
/// operation is wasteful.
class IsolateGlyphCodec implements GlyphCodec {
  IsolateGlyphCodec();

  Isolate? _isolate;
  SendPort? _commands;
  ReceivePort? _replies;
  Future<void>? _starting;

  int _nextId = 0;
  final Map<int, Completer<String>> _pending = <int, Completer<String>>{};
  bool _disposed = false;

  @override
  Future<String> encrypt({required String key, required String plaintext}) =>
      _send(_opEncrypt, key, plaintext);

  @override
  Future<String> decrypt({required String key, required String armoured}) =>
      _send(_opDecrypt, key, armoured);

  @override
  Future<void> clearCache() async {
    // Nothing to clear if the isolate was never started.
    if (_isolate == null && _starting == null) {
      return;
    }
    await _send(_opClearCache, '', '');
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(const GlyphInternalError('Disposed'));
      }
    }
    _pending.clear();
    _replies?.close();
    _replies = null;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commands = null;
    _starting = null;
  }

  Future<String> _send(int op, String key, String text) async {
    if (_disposed) {
      throw const GlyphInternalError('Disposed');
    }
    await _ensureStarted();
    final commands = _commands;
    if (commands == null) {
      throw const GlyphInternalError('WorkerUnavailable');
    }

    final id = _nextId++;
    final completer = Completer<String>();
    _pending[id] = completer;
    commands.send(<Object?>[id, op, key, text]);
    return completer.future;
  }

  Future<void> _ensureStarted() {
    if (_commands != null) {
      return Future<void>.value();
    }
    return _starting ??= _start();
  }

  Future<void> _start() async {
    final replies = ReceivePort();
    final handshake = Completer<SendPort>();

    replies.listen((Object? message) {
      if (message is SendPort) {
        handshake.complete(message);
        return;
      }
      _handleReply(message);
    });

    _replies = replies;
    _isolate = await Isolate.spawn(
      _workerMain,
      replies.sendPort,
      debugName: 'glyph-cipher',
      errorsAreFatal: false,
    );
    _commands = await handshake.future;
  }

  void _handleReply(Object? message) {
    if (message is! List || message.length < 3) {
      return;
    }
    final id = message[0] as int;
    final tag = message[1] as int;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) {
      return;
    }
    switch (tag) {
      case _replyOk:
        completer.complete(message[2] as String);
      case _replyGlyphError:
        completer.completeError(message[2] as GlyphError);
      default:
        completer.completeError(GlyphInternalError(message[2] as String));
    }
  }
}

/// Entry point of the worker isolate.
///
/// Owns exactly one [GlyphCipher], and therefore one derived-key cache, for
/// the lifetime of the isolate.
Future<void> _workerMain(SendPort replies) async {
  final commands = ReceivePort();
  replies.send(commands.sendPort);
  final cipher = GlyphCipher();

  await for (final Object? message in commands) {
    if (message is! List || message.length < 4) {
      continue;
    }
    final id = message[0] as int;
    final op = message[1] as int;
    final key = message[2] as String;
    final text = message[3] as String;

    try {
      final String result;
      switch (op) {
        case _opEncrypt:
          result = await cipher.encrypt(key: key, plaintext: text);
        case _opDecrypt:
          result = await cipher.decrypt(key: key, armoured: text);
        case _opClearCache:
          cipher.clearCache();
          result = '';
        default:
          throw GlyphInternalError('UnknownOp($op)');
      }
      replies.send(<Object?>[id, _replyOk, result]);
    } on GlyphError catch (error) {
      replies.send(<Object?>[id, _replyGlyphError, error]);
    } catch (error) {
      // Only the type name crosses back: an arbitrary exception's message
      // could contain the key or the plaintext.
      replies.send(<Object?>[
        id,
        _replyUnexpected,
        error.runtimeType.toString(),
      ]);
    }
  }
}
