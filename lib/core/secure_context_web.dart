import 'dart:js_interop';
// `has` lives here rather than in dart:js_interop. It is the SDK's own
// property-existence check, not a package, so it costs no dependency.
import 'dart:js_interop_unsafe';

/// Whether the browser will hand this page a working Web Crypto.
///
/// Web Crypto is gated behind a *secure context*: HTTPS, or localhost. Over
/// plain HTTP on any other origin the browser leaves `crypto.subtle`
/// undefined, and `package:cryptography` quietly falls back to its pure-Dart
/// PBKDF2 -- which is the whole reason PBKDF2 was chosen over Argon2id in the
/// first place, so losing it is not a small regression. The measured medians
/// are 18 ms through Web Crypto against roughly two seconds of compiled
/// JavaScript on a main thread that cannot even animate a spinner, because
/// `dart:isolate` does not exist on web.
///
/// Both conditions are checked. `isSecureContext` is the browser's own verdict
/// and is the one that matters, but `crypto.subtle` is tested too: it is the
/// object that actually has to exist, and a page can be a secure context in a
/// browser that still withholds it.
bool get isCryptoContextSecure => _isSecureContext && _hasSubtleCrypto;

@JS('window.isSecureContext')
external bool? get _windowIsSecureContext;

@JS('window.crypto')
external JSObject? get _windowCrypto;

bool get _isSecureContext => _windowIsSecureContext ?? false;

bool get _hasSubtleCrypto {
  final crypto = _windowCrypto;
  if (crypto == null) {
    return false;
  }
  // `subtle` is absent rather than null in an insecure context, so a property
  // lookup is the honest test.
  return crypto.has('subtle');
}
