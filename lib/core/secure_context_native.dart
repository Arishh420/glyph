/// Whether key stretching can reach a native cryptographic implementation.
///
/// Always true off the web: the question is about the browser's secure-context
/// rule, and a native build has no such gate. Android reaches the same PBKDF2
/// through the Dart implementation in `package:cryptography`, on a worker
/// isolate, with no origin to qualify.
bool get isCryptoContextSecure => true;
