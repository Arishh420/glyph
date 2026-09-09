# Glyph — technical reference

The durable design document: what the format is, what is frozen, and why each
choice was made. `REPORT.md` and `PASS2-REPORT.md` are build records of a
particular pass; this file is meant to stay true.

Glyph is an offline symmetric text-encryption pad. Two people agree a key
out-of-band, and each side encrypts and decrypts locally. There is no server, no
account, and no network code.

- **Shipping targets:** Android (universal APK) and web.
- **Not shipped:** iOS and macOS. `ios/` and `macos/` remain configured in the
  repository but have never been compiled — Xcode is not installed on the build
  machine.

---

## 1. The envelope

```
payload  = version (1) || salt (16) || nonce (12) || body (n)
framed   = uint32be(payload.length) || payload || zero-pad to a multiple of 8
armoured = "GLY1" + base62(framed)
```

`body` is the AES-256-GCM ciphertext followed by its 16-byte authentication tag.
The `GLY1` prefix is literal and case-sensitive.

Fixed elements:

| Field | Size | Notes |
|---|---|---|
| Cipher | — | AES-256-GCM |
| Salt | 16 bytes | fresh per message, from `Random.secure()` |
| Nonce | 12 bytes | fresh per message |
| Tag | 16 bytes | GCM authentication tag |
| AAD | 1 byte | the version byte itself, so it cannot be swapped for a weaker one |

Because the salt and nonce are fresh per message, **encrypting the same
plaintext twice produces two entirely different messages.** That is intended.

**Output length.** A 20-character message becomes 103 characters: 20 + 16 tag =
36 body; + 1 + 16 + 12 = 65 payload; + 4 length header = 69; padded to 72;
9 blocks × 11 chars = 99; + `GLY1` = 103. Roughly 1.375× overhead plus a
constant.

**Input hygiene.** Before decoding, every Unicode whitespace character is
stripped, including internal newlines, non-breaking spaces and the zero-width
characters some clients insert as soft wrap points. A message that was
line-wrapped by a mail client still decrypts.

**Key normalisation.** Keys are normalised to Unicode NFC and trimmed before
derivation, and their length is counted in grapheme clusters, so a family emoji
counts as one character. Without this, an accented or emoji key typed on one
platform would not match the same key typed on another: macOS and some IMEs hand
back NFD, most Android keyboards hand back NFC.

---

## 2. The version byte is a contract, not a label

**The envelope records the salt and the nonce, but not the key-derivation cost
parameters.** A version byte therefore has to *imply* them.

| Byte | KDF | Frozen parameters | Status |
|---|---|---|---|
| `0x01` | PBKDF2-HMAC-SHA256 | iterations 210,000; derived length 32 bytes | **shipping default** |
| `0x02` | Argon2id, RFC 9106 (v0x13) | m = 32768 (32 MiB), t = 3, p = 1, tag 32 bytes | legacy-readable |

**Any cost change to either row requires a new version byte, not an edit to
these numbers.** Change one and every message ever written under the old value
stops decrypting — and it fails as `WrongKeyOrTampered`, which is
indistinguishable to the user from having typed the wrong key. Silent,
permanent, and impossible to diagnose from the message alone.

To change a cost parameter: allocate a **new** version byte, make it the value of
`GlyphCipher.currentVersion`, and keep the old byte readable in
`GlyphCipher._deriveKey`.

> The authoritative copy of this table is the comment at the top of
> [`lib/core/envelope.dart`](lib/core/envelope.dart). It sits next to the
> constants it governs, so it is the one that gets read when someone is about to
> change them. This section is a summary; if the two ever disagree, the source
> comment wins.

`0x01` is what this build writes. `0x02` is never written any more but stays
readable forever, with its parameters and its golden vector intact. Both are
pinned by `test/version_vectors_test.dart`, which decrypts hard-coded messages
in both formats — the guard was verified to actually fire by temporarily
doubling Argon2id's memory, which broke the `0x02` vector while `0x01` kept
passing.

`0x02` was redefined once before release (it briefly meant m = 16384, t = 2).
That was legal exactly once, because no `0x02` message existed outside this
repository. That window is closed.

---

## 3. Why PBKDF2 ships, when Argon2id is the stronger primitive

Argon2id is memory-hard and PBKDF2 is not, so on paper Argon2id is the better
choice, and on Android it is also about three times *cheaper*. It does not ship.

The reason is one format everywhere. Argon2id has no Web Crypto equivalent, so in
a browser it is compiled JavaScript on the main thread — and `dart:isolate` does
not exist on the web to move it off. PBKDF2 reaches Web Crypto natively.

Measured medians, five runs each:

| | Android AOT (worker isolate) | Chrome release, dart2js (main thread) |
|---|---|---|
| **`0x01` PBKDF2 210k** | **892 ms** | **18 ms** |
| `0x02` Argon2id 32 MiB / t=3 | 331 ms | 2028 ms |

The 18 ms figure was re-measured in pass two against the shipping release build
and came back at 18 ms again, which is the evidence that Web Crypto's native path
is genuinely being used rather than a pure-Dart fallback.

**Per-platform KDFs were the obvious alternative and were rejected.** A
per-platform KDF only controls what each platform *encrypts* with. An Android
friend encrypting with `0x02` hands a web friend a message that takes two seconds
to open — putting the slow path on exactly the cross-platform exchange the web
build exists to serve.

Accepted cost: perhaps 50–100× less GPU resistance than memory-hard Argon2id.
That is immaterial for a 12-character key and does not rescue a 4-character one.
**Key length is the lever**, which is why the README leads with it.

`0x02`'s parameters were themselves chosen by measurement, on emulator-5554
(Android 16, arm64, debug/JIT), median of five derivations:

| Parameters | min | median | max | Within a 500 ms budget? |
|---|---|---|---|---|
| m=16384 (16 MiB), t=2, p=1 | 89 ms | 101 ms | 181 ms | yes — superseded |
| m=32768 (32 MiB), t=3, p=1 | 263 ms | **297 ms** | 363 ms | yes — **adopted** |
| m=65536 (64 MiB), t=3, p=1 | 544 ms | 571 ms | 697 ms | **no** |

Argon2id's `memory` is the standard `m` in 1 KiB blocks, so m = 32768 is 32 MiB.
Confirmed three ways in `cryptography` 2.9.0: the public API documents it as the
"number of 1 kB blocks"; `argon2.dart` computes RFC 9106's
`m' = 4p·floor(m/4p)`; and `argon2_impl_default.dart` allocates `1024 *
blockCount` bytes with 1024-byte blocks.

---

## 4. Base62 is fixed-block, not a bignum conversion

Output must be strictly alphanumeric (`0-9 A-Z a-z`), so it survives every
messaging app without being mangled or line-broken on a symbol.

**It is deliberately not an arbitrary-precision conversion of the whole
message.** That is O(n²) and hangs on a long paragraph.

Instead the framed bytes are taken 8 at a time, each block read as a big-endian
unsigned 64-bit integer and emitted as exactly 11 Base62 characters, left-padded
with `0`. Both directions are linear in the length of the input.

- 62¹¹ ≈ 5.2×10¹⁹ exceeds 2⁶⁴ ≈ 1.8×10¹⁹, so 11 characters always suffice for
  8 bytes; 62¹⁰ ≈ 8.4×10¹⁷ does not, so 11 is also the minimum.
- Dart's `int` is 64-bit **signed**, so a block with the high bit set would go
  negative and break `~/`. Every block is therefore carried as a pair of 32-bit
  halves with base-2³² long division.
- Safe under JavaScript's float64 semantics: peak intermediate value is about
  2.66×10¹¹ against float64's exact-integer limit of 9.0×10¹⁵ — roughly 34,000×
  headroom. The maximal 2⁶⁴−1 block round-trips, encoding to `LygHa16AHYF`.
- The charset is validated **before** block alignment, deliberately: a stray
  character reports `NotGlyphMessage`, a misaligned length reports
  `DamagedMessage`.

---

## 5. Platform selection

Three compile-time conditional exports, all with the same polarity: **native is
the default branch, web is the conditional one.** If a condition ever failed to
resolve, a native build keeps the safe behaviour and a web build fails loudly,
which is the better failure of the two.

| Concern | Native | Web |
|---|---|---|
| `glyph_codec_factory.dart` | `IsolateGlyphCodec` — key stretching on a long-lived worker isolate | `InlineGlyphCodec` — the calling thread, affordable only because PBKDF2 costs ~18 ms |
| `key_store_factory.dart` | `SecureKeyStore` — Keychain / Android KeyStore | `InMemoryKeyStore` — no persistence at all |
| `secure_context.dart` | always secure (not applicable) | checks `window.isSecureContext` **and** that `crypto.subtle` exists |

`dart:isolate` on web compiles but every call throws `UnsupportedError`, and
Flutter's `compute` on web is `await null; return callback(message);` — the main
thread either way. So the web codec avoids importing `glyph_worker.dart` at all
rather than importing it and never calling it.

**No key persistence on web, by design.** `flutter_secure_storage` publishes an
endorsed web implementation that wraps `window.localStorage`. Everything a
browser offers — localStorage, sessionStorage, IndexedDB — is readable by any
script on the page, and there is no browser equivalent of the Keychain. So the
key lives in memory for the life of the tab and the interface says so
permanently. Verified in the release build: after a full encrypt/decrypt round
trip and a page reload, `Object.keys(localStorage)` was `[]`,
`sessionStorage.length` was `0`, and `indexedDB.databases()` was `[]`.

**Secure-context gate.** Web Crypto is only available over HTTPS or on
localhost. Over plain HTTP anywhere else the browser leaves `crypto.subtle`
undefined and PBKDF2 silently loses the native path that was the entire reason
it was chosen. Glyph detects this at startup and shows a blocking explanation
rather than running two orders of magnitude slower without saying so.

**Derived-key cache.** Keyed by `(version, salt, normalised key)`, capped at 32
entries, FIFO-evicted, cleared whenever the key changes or is forgotten.
Re-decrypting the same message drops from ~892 ms to ~1 ms.

---

## 6. Android permissions

`aapt2 dump permissions` on the release APK reports exactly one permission:

```
package: com.glyphpad.glyph
permission: com.glyphpad.glyph.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
uses-permission: name='com.glyphpad.glyph.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'
```

Anyone auditing this repository will run the same command and see the same line,
so: **it is not a network permission, and it is not a request for any device
capability.** It has `protectionLevel="signature"` and is namespaced under
Glyph's own application ID — the app defining a permission for itself so that no
other app on the phone can reach its internal broadcast receivers. Only code
signed with the same key could ever hold it. It is declared by
`androidx.core:core:1.13.1`, pulled in by Flutter's Android embedding, not by
anything in this repository.

**There is no `INTERNET` permission**, and no `ACCESS_NETWORK_STATE` or
`ACCESS_WIFI_STATE` either — zero matches in the shipped manifest. Glyph cannot
send a message anywhere even if it wanted to.

`android/app/src/debug/` and `android/app/src/profile/` *do* declare `INTERNET`.
That is Flutter's own template and is needed for hot reload and the Dart VM
service. Those source sets are not compiled into a release build, which is what
the `aapt2` output above demonstrates.

---

## 7. Release signing

The release signing config is read from `android/key.properties`, which is
gitignored, as are `*.jks` and `*.keystore`.

A release build **fails loudly** if that file is missing, if any of `storeFile`,
`storePassword`, `keyAlias` or `keyPassword` is absent or blank, or if the
keystore is not on disk. Error messages name the missing **keys** only, never
their values. There is no debug-key fallback.

This matters more than it looks. AGP names an unsigned artifact
`app-release-unsigned.apk`, but Flutter's Gradle plugin then copies whatever AGP
produced into `build/app/outputs/flutter-apk/` and renames it to
`app-release.apk` — so an unsigned release build prints a green tick under a
filename that looks correct. The signing config is therefore created only when it
is completely valid (a half-populated config makes AGP skip signing silently),
and a `verifyReleaseSigning` task is wired ahead of `preReleaseBuild`,
`packageRelease`, `packageReleaseBundle`, `signReleaseBundle` and
`packageReleaseUniversalApk`. It is a real task rather than a `doFirst`, because
a `doFirst` is skipped when its task is up-to-date, and it throws rather than
warns, because `flutter build` passes `-q` and warnings would be invisible.

**Verifying a signature:** `unzip -l … | grep META-INF` is *not* a valid check.
AGP defaults to `enableV1Signing=false`, and v2 signatures live in the APK
Signing Block rather than in `META-INF`, so a correctly signed APK shows no
`.SF`/`.RSA` pair. Use `apksigner verify -v --print-certs` instead.

Two escape hatches exist and cannot be closed from inside the build script:
`./gradlew packageRelease -x verifyReleaseSigning`, and Android Studio's
Generate-Signed-Bundle flow via `-Pandroid.injected.signing.*`, which bypasses
`key.properties` entirely.

**Files that can contain the keystore password in plaintext** and must never be
committed or pasted anywhere: `android/.gradle/configuration-cache/**`,
`build/app/intermediates/signing_config_data/**/signing-config-data.json`,
`build/reports/configuration-cache/**`, and `~/.gradle/daemon/*/daemon-*.log` if
a password is ever passed on a command line. Never pass one on a command line.

---

## 8. Errors

Every message is safe to show a user verbatim, and none ever carries the key or
the plaintext — these objects cross an isolate boundary and may end up in logs.

| Type | Trigger | Message |
|---|---|---|
| `NotGlyphMessage` | No `GLY1` prefix, or non-Base62 characters | *"This doesn't look like a Glyph message."* |
| `DamagedMessage` | Correct prefix, malformed length or truncated body | *"This message is incomplete or was damaged in transit."* |
| `WrongKeyOrTampered` | GCM tag mismatch | *"Wrong key, or the message was changed after it was encrypted."* |
| `UnsupportedVersion` | Unknown version byte | *"This message was made by a newer version of Glyph."* |
| `KeyTooShort` | Key under 4 graphemes | *"Key must be at least 4 characters."* |
| `GlyphInternalError` | Anything else | *"Something went wrong while handling this message."* |

`GlyphInternalError` deliberately carries only the runtime *type name* of the
underlying error, never its message: an arbitrary exception's message could
contain the key or the plaintext.

Direction is detected by reading the input, case-insensitively, for the `GLY1`
prefix. That leniency picks the button label only; the decoder itself stays
strict. **Consequence: an already-encrypted message can never be re-encrypted.**

---

## 9. Known limitations

- **Not audited.** Written by one person. No independent review has happened.
- **A short key defeats everything else.** The KDF multiplies whatever entropy
  the key already has. 210,000 PBKDF2 iterations applied to `cat123` is still
  `cat123`.
- **The web build is inherently weaker than the APK**, not because of the
  cryptography but because of delivery: a page re-fetches its code on every
  visit, so whoever controls the host can change it. An installed APK is fixed
  at install time. The README says this plainly.
- **Corruption detection at the Base62 layer is probabilistic** — around 65% of
  random single-character corruptions are caught at decode; the rest fall
  through to the GCM tag, which catches them all, but reports
  `WrongKeyOrTampered` rather than `DamagedMessage`.
- **No chunking.** A very long message produces one very long string.
- **Android's `resetOnError: true`** is the `flutter_secure_storage` default, so
  a keystore error can silently erase the saved key. The user can retype it.
- **No automated on-device tests.** There is no `integration_test` suite; device
  behaviour is verified by hand.
- **iOS and macOS have never been compiled.** Everything under `ios/` and
  `macos/` is written but unverified, including the macOS keychain entitlements
  that `flutter_secure_storage` fails silently without.
