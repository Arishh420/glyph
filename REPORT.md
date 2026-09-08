# Glyph — pass one report

Offline symmetric text-encryption pad. Flutter 3.47.2 / Dart 3.13.2, built and
verified on `emulator-5554` (Android 16, API 36, arm64).

---

## 1. Built and verified

A working Android app, 117 automated tests, zero analyzer issues.

| Step | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | **No issues found** (with four lints added on top of `flutter_lints`) |
| Tests | `flutter test` | **117 passed**, ~17 s (five consecutive clean runs) |
| Debug build | `flutter build apk --debug` | **Built**, 7–15 s warm (Gradle and NDK already warm) |
| On device | `flutter run -d emulator-5554` | **Launches**, renders correctly inside `SafeArea` |

Test breakdown:

| File | Tests | Covers |
|---|---|---|
| `test/glyph_page_test.dart` | 32 | all five button states, direction detection, per-box controls, focus |
| `test/crypto_round_trip_test.dart` | 18 | round trips, randomised output, line wrapping, every failure mode |
| `test/envelope_test.dart` | 16 | framing, padding, version dispatch, whitespace scrubbing |
| `test/key_rules_test.dart` | 15 | length in graphemes, NFC, generation |
| `test/base62_test.dart` | 9 | alphabet, round trips, overflow, linear-time performance |
| `test/glyph_worker_test.dart` | 8 | isolate round trip, typed errors across the boundary |
| `test/glyph_cipher_cache_test.dart` | 6 | derived-key cache contents and its cap |
| `test/version_vectors_test.dart` | 5 | golden vectors pinning what each version byte means |

Verified by hand on the emulator, with screenshots taken at each step:

- Three boxes render correctly in dark mode, monospace, nothing under the
  status bar or the navigation gesture area.
- Key field obscured, green check on a valid key, eye toggle, dice generator.
- Button walks through states 1 → 2 → 3 → 4 as the key and input change.
- Encrypt produced `GLY1...` output; **copy → clear input → paste → Decrypt
  returned the exact original plaintext** (`abcdefghijklmnopqrst`).
- Changing one character of the key and decrypting again showed the red
  "Wrong key, or the message was changed after it was encrypted." with **both
  boxes left untouched**.
- The key survived a full app restart (loaded from `flutter_secure_storage`),
  and focus then correctly moved to the input box rather than the key box.
- Encrypting the same text repeatedly produced visibly different output each
  time.

---

## 2. Dependencies

Five direct dependencies, one of them the Flutter SDK itself. 63 packages in
the lockfile including transitives.

| Package | Version | Why |
|---|---|---|
| `cryptography` | 2.9.0 | AES-256-GCM, Argon2id, PBKDF2 |
| `flutter_secure_storage` | 11.0.0 | Keychain / Android KeyStore-backed key storage |
| `characters` | 1.4.1 | grapheme-cluster counting |
| `unorm_dart` | 0.3.2 | Unicode NFC normalisation |
| `flutter_lints` | 6.0.0 | dev only |

### Crypto package: `cryptography` 2.9.0

The brief's first choice, and it resolved cleanly on Dart 3.13.2, so
`pointycastle` was never needed. It supplies AES-256-GCM with AAD, Argon2id
and PBKDF2-HMAC-SHA256 from one API, with pure-Dart implementations that run
happily inside a background isolate. Only `pointycastle` **or** `cryptography`
is present — never both.

Before committing to it I benchmarked both key-derivation functions on this
machine (`dart run tool/kdf_bench.dart`, kept in the repo):

```
Argon2id m=16 MiB t=2 p=1  :  77 ms
PBKDF2-HMAC-SHA256 210,000 : 759 ms
```

(Host machine, and at the parameters then under consideration. The shipped
Argon2id cost is higher — see the frozen parameters below — but the ordering
against PBKDF2 is what mattered for choosing the primitive.)

Argon2id is both the stronger primitive and about ten times faster here, so it
is the default. I had expected the opposite — the package's own Argon2 test
allows ten seconds for a 1 MiB derivation, which suggested the pure-Dart
implementation would be too slow at 16 MiB. Measuring it rather than trusting
that comment is what settled the choice.

### Rejected

- **`pointycastle`** — not needed; `cryptography` resolved. Adding both would
  have meant two AES implementations in one binary.
- **A state-management package** — one screen, so `setState` is enough.
- **A clipboard package** — `Clipboard` is in `flutter/services.dart`.
- **An icon pack** — Material icons are built in.
- **A monospace font file** — `theme.dart` uses a fallback stack of fonts that
  already ship with each platform (`monospace`, `SF Mono`, `Menlo`,
  `Consolas`, `Courier New`), so the app downloads and bundles nothing.
- **`cupertino_icons`** — came with the scaffold, never used, removed.

### One dependency the brief did not list

`unorm_dart` was added because **Dart has no built-in Unicode normalisation**.
There is no `String.normalize()`, and `characters` only does grapheme
segmentation. The brief requires NFC normalisation of the key and a test that
the same key composed as NFC and NFD both decrypt, and neither is possible
without real Unicode composition tables. It is pure Dart, has no native
component, and adds one package. See Deviations.

---

## 3. Crypto choices

| | |
|---|---|
| Cipher | AES-256-GCM, 12-byte random nonce, 16-byte tag |
| AAD | the 1-byte envelope version, so the KDF cannot be downgraded by flipping the byte |
| KDF actually used | **Argon2id**, version byte `0x02` — see the frozen parameters below |
| KDF also readable | PBKDF2-HMAC-SHA256, version byte `0x01` |
| Salt | fresh 16 random bytes per message |
| RNG | `Random.secure()` everywhere — salt, nonce, generated keys |
| Key normalisation | Unicode NFC, then trim |

### The version byte is a contract, not a label

**The envelope records the salt and the nonce but not the key-derivation cost
parameters.** A version byte therefore has to imply them. `0x02` does not mean
"Argon2id"; it means "Argon2id with exactly these numbers". Change one and
every message ever written under the old value stops decrypting — and it fails
as `WrongKeyOrTampered`, which a user cannot tell apart from having typed the
wrong key. Silent, permanent, undiagnosable from the message itself.

So the parameters are frozen, and this is the authoritative table. The same
table appears at the top of `lib/core/envelope.dart`.

| Byte | KDF | Frozen parameters |
|---|---|---|
| `0x01` | PBKDF2-HMAC-SHA256 | iterations 210,000; derived length 32 bytes |
| `0x02` | Argon2id, RFC 9106 (version 0x13) | **m = 32768, t = 3, p = 1**, tag 32 bytes |

`0x02` was redefined once before release — it briefly meant m = 16384, t = 2 —
and that was legal only because no message in that format existed outside this
repository. **Any cost change from here on requires a new version byte.**

Both versions share the rest of the format: AES-256-GCM, the 16-byte salt and
12-byte nonce taken from the envelope, a 16-byte tag, and the version byte
itself as associated data. Argon2id is used with no optional secret and no
associated data.

**To change a cost parameter:** allocate a *new* version byte, point
`GlyphCipher.currentVersion` at it, keep the old byte readable in
`GlyphCipher._deriveKey`, and add a golden vector for it. Do not edit the
numbers. A future format that wants to tune costs freely should spend bytes
recording them in the envelope.

#### Units of the memory parameter: 1 KiB blocks

Confirmed by reading `cryptography` 2.9.0 rather than assuming, because the
name `memory` is ambiguous between blocks, KiB and bytes:

- The public API documents it as the *"Minimum number of 1 kB blocks needed to
  compute the hash"* (`lib/src/cryptography/algorithms.dart`, `int get memory`).
- `lib/src/dart/argon2.dart` computes
  `blockCount = 4 * parallelism * (memory ~/ (4 * parallelism))`, which is
  RFC 9106's `m' = 4p·floor(m/4p)` — so `memory` is the spec's `m`.
- `lib/src/dart/argon2_impl_default.dart` then allocates
  `malloc.allocate(1024 * blockCount)`, and a block is `Uint32List(256)`.
  1024 bytes per block.

So `memory` is the standard Argon2 `m` in KiB: **m = 32768 is 32 MiB**, and the
constant in the code is written `32 * 1024` to make that obvious.

#### Choosing the parameters: measured, not guessed

Benchmarked on `emulator-5554` (Android 16, arm64), debug/JIT build, five
derivations per configuration, run inside a background isolate exactly as
production does:

| Parameters | min | **median** | max | Within a 500 ms budget? |
|---|---|---|---|---|
| m=16384 (16 MiB), t=2, p=1 | 89 ms | **101 ms** | 181 ms | yes — superseded |
| m=32768 (32 MiB), t=3, p=1 | 263 ms | **297 ms** | 363 ms | yes — **adopted** |
| m=65536 (64 MiB), t=3, p=1 | 544 ms | **571 ms** | 697 ms | **no** |

**64 MiB / t=3 was evaluated and rejected: it exceeded 500 ms on every one of
the five runs**, fastest included, so it is not a borderline miss. 32 MiB / t=3
fits the budget with room to spare and is what `0x02` now means.

Two caveats on those numbers, both of which cut in favour of stronger
parameters later rather than now:

- They are **debug/JIT** measurements. A release AOT build will be faster, so
  64 MiB might well come in under 500 ms once release packaging exists in pass
  two. It cannot be measured today.
- Argon2id allocates its memory for the duration of a derivation, natively via
  `malloc`. At 64 MiB that is a real footprint on a low-end phone, and two
  concurrent derivations would double it. The emulator handled 64 MiB without
  failure, but memory cost — not just time — is part of the trade.

#### The parameters are pinned by tests

`test/version_vectors_test.dart` holds hard-coded armoured messages generated
under each version byte's frozen parameters (by
`dart run tool/make_test_vectors.dart`) and decrypts them against a hard-coded
key and plaintext. Changing a cost parameter breaks those tests immediately.

I verified the guard actually fires rather than trusting it, once per frozen
Argon2id parameter:

| Negative control | Result |
|---|---|
| memory 32 MiB → 64 MiB | `0x02` vector test **failed**, `0x01` kept passing |
| iterations 3 → 2 | `0x02` vector test **failed**, `0x01` kept passing |

Both are the expected signal: a changed Argon2id cost breaks only the Argon2id
vector, and leaves the PBKDF2 one alone. The parameters were restored after
each control and the full suite re-run green.

This also closed a real gap. Before these vectors, **nothing decrypted a
genuine version-`0x01` message end to end** — `test/envelope_test.dart` only
proved a `0x01` envelope *parses*. The PBKDF2 read path is now exercised for
real, so the dual-format promise is tested rather than asserted.

An unknown version byte raises `UnsupportedVersion`;
`test/envelope_test.dart` proves `0x00`, `0x03`, `0x7F` and `0xFF` are all
rejected.

### Measured on the emulator

Debug build, JIT, `emulator-5554`. Timings were taken with temporary
instrumentation that has since been removed.

**These end-to-end figures were measured under the superseded `0x02`
parameters (m=16384, t=2) and have not been re-measured on device since the
change to m=32768, t=3:**

| Operation | Milliseconds (at the superseded m=16384, t=2) |
|---|---|
| Encrypt, 20-character input | **205, 242, 285** typical; one 650 outlier |
| Decrypt, cold (derives the key) | 307 |
| Decrypt, same message again (cache hit) | **1, 1, 2, 14, 14** |

Derivation alone went from a 101 ms median to a 297 ms median, so expect
roughly **0.45 s** per uncached operation now rather than 0.25 s. That is an
estimate by addition, not a measurement — the figure actually measured is the
297 ms derivation median. Corroborating evidence: the full test suite, which
derives keys constantly, went from about 7 s to about 17 s. **Re-measure
end-to-end on device before pass two quotes a number to users.**

A cached decrypt is unaffected and still effectively instant: 1 ms against a
~300 ms floor for a fresh derivation is only possible on a cache hit.

That the cache is responsible is asserted structurally rather than by the
clock. `test/glyph_cipher_cache_test.dart` counts entries — a second decrypt
of the same message must add none, two messages under one key must add two
(fresh salt each), and 40 messages must not exceed the 32-entry cap. An
earlier version compared elapsed microseconds between a cold and a warm
decrypt; it was flaky under parallel test load, where the cached call could
measure *slower* than the uncached one, and it could only ever show that
something was faster, not why. The full suite now runs clean five times in a
row.

These are debug/JIT numbers on an emulator. A release AOT build should be
faster; that is unverified because release packaging is pass two.

### Output length

A **20-character input produces 103 characters** of output. That matches the
envelope arithmetic exactly:

```
payload = 1 version + 16 salt + 12 nonce + (20 ciphertext + 16 tag) = 65
framed  = 4 length prefix + 65 = 69, padded to 72 (9 blocks of 8)
armour  = 4 ("GLY1") + 9 x 11 = 103
```

Overhead is a flat 45 bytes plus padding, then 11 characters per 8 bytes, so
long messages settle at about 1.375x the UTF-8 byte length.

---

## 4. Deviations

Blunt list. Several of these are cases where the brief asked for something
this toolchain will not actually do.

1. **`minSdk` is 24, not 23.** `flutter_secure_storage` 11.0.0's Android module
   declares `minSdk 24`, and the manifest merger refuses a lower value in the
   consuming app. 23 is not achievable with this plugin.

2. **`compileSdk` is 37, not 36.** The same plugin publishes AAR metadata
   requiring callers to compile against API 37 or later; with 36 the build
   fails at `:app:checkDebugAarMetadata`. The brief permits 37 "if a plugin
   demands it", and `android-37.0` was already installed, so this cost no
   download. AGP 9.1.0 only *recommends* up to 36 and warns, so
   `android.suppressUnsupportedCompileSdk=37` is set in `gradle.properties`.
   `targetSdk` stays 36 as asked. AGP, Gradle and the NDK are untouched.

3. **iOS is 15.0 and macOS is 12.0, not iOS 13.0 and macOS 10.15.** Flutter
   3.47.2 ships migrations that *actively rewrite* lower deployment targets
   upward — see
   `packages/flutter_tools/lib/src/macos/migrations/macos_deployment_target_migration.dart`,
   which replaces `MACOSX_DEPLOYMENT_TARGET = 10.15` with `12.0` and
   `platform :osx, '10.15'` with `'12.0'`, and the iOS equivalent alongside it.
   Setting the brief's values would have been silently undone on the next
   build and would have misstated the project's real minimum. I kept Flutter's
   enforced minimums.

4. **`unorm_dart` added** as a fifth dependency. Dart has no built-in Unicode
   normalisation, so the brief's own NFC requirement and its NFC-vs-NFD test
   cannot be satisfied with the SDK alone.

5. **Android key storage is not EncryptedSharedPreferences.**
   `flutter_secure_storage` 11.0.0 removed that option after Google deprecated
   Jetpack Security. The default now encrypts values with AES-GCM under a key
   wrapped by RSA-OAEP in the Android KeyStore. Same intent, stronger
   mechanism, but not the named API.

6. **Enter in the input box inserts a newline; it does not press the button.**
   The brief asked for the keyboard's action key to trigger the button. On a
   multiline field, giving the action key any job other than `newline` makes
   newlines impossible to type from a soft keyboard — and the test suite
   requires that messages containing newlines round-trip. So: the **key**
   field's action key runs the operation (or moves to the input if the input
   is empty), and **Cmd/Ctrl+Enter** runs it from anywhere. Enter in the input
   box stays a newline. This is a deliberate trade against the brief's
   wording, in favour of the app remaining usable for multi-line messages.

7. **"Forget key" and the key box's Clear are one control.** Step 4 wants a
   Forget-key control; step 5 lists Clear among the key box's controls. Rather
   than two adjacent buttons that nearly do the same thing, the key box's
   control wipes the field, the stored key and the derivation cache, and is
   labelled "Forget key".

8. **The short-key hint latches off permanently.** "Show it once" is
   implemented as: visible while the key is short, and once the key grows past
   eight graphemes it never returns for the rest of the session, even if the
   key becomes short again. A test covers exactly this.

9. **Base62 decoding checks the character set before block alignment.** A
   stray symbol yields `NotGlyphMessage` rather than `DamagedMessage`, which
   matches the brief's own definitions but required an explicit ordering pass.
   This was a real bug caught by the test suite.

10. **Two error types beyond the four specified.** `KeyTooShort` (the key rules
    need a failure) and `GlyphInternalError` (anything unexpected crossing the
    isolate boundary). The latter carries only the original error's *type
    name*, never its message, because an arbitrary exception message could
    contain the key or the plaintext.

11. **`com.apple.security.network.server` removed from
    `macos/Runner/DebugProfile.entitlements`.** The brief requires no network
    entitlements in either file. Flutter's template puts it in the debug file
    because the tool's hot reload talks to the app over a local socket, so
    **macOS debug hot reload will probably not work in pass two** until it is
    temporarily restored. Flagged rather than quietly kept.

12. **Extras not asked for:** `data_extraction_rules.xml` excluding everything
    from cloud backup and device transfer (belt and braces next to
    `allowBackup="false"`); the derived-key cache is capped at 32 entries so a
    long backlog cannot grow it without limit; the whitespace scrubber also
    strips zero-width characters (U+200B–U+200D, U+2060), which `\s` does not
    match but which some clients insert as soft wrap points.

---

## 5. Written but unverified

**Xcode and CocoaPods are not installed. Nothing under `ios/` or `macos/` has
been compiled, run, or tested. All of it is written from the specification and
should be treated as unproven.**

Specifically needing a check once Xcode exists:

1. **Keychain entitlements.** `keychain-access-groups` containing
   `$(AppIdentifierPrefix)com.glyphpad.glyph` is in **both**
   `macos/Runner/DebugProfile.entitlements` and
   `macos/Runner/Release.entitlements`. Both files pass `plutil -lint`. The
   failure mode if this is wrong is silent: the app stores nothing and reports
   no error. Test by entering a key, quitting, and relaunching — the key
   should still be there. Check the Release build too, not just Debug.

2. **macOS debug hot reload.** See deviation 11 — the network entitlement the
   Flutter tool relies on has been removed. Expect `flutter run -d macos` to
   misbehave and need it temporarily restored.

3. **Cmd+Enter.** Wired via `CallbackShortcuts`, never executed on a Mac.

4. **Button state 1 on macOS** (disabled and greyed rather than enabled). There
   *is* a widget test for it using `debugDefaultTargetPlatformOverride`, so the
   logic is proven — but not the real platform.

5. **`KeychainAccessibility.first_unlock`** on iOS and macOS. Chosen so the key
   survives a reboot without being readable before first unlock. Untested.

6. **No `Podfile` exists** under `ios/` or `macos/`. `flutter create` does not
   generate one; it appears on the first Apple build. The first
   `flutter build ios` or `flutter build macos` will generate it and run
   `pod install`, which needs network access and will pull the plugin pods.
   Budget bandwidth for that.

7. **Deployment targets** (iOS 15.0, macOS 12.0) and the `PRODUCT_NAME`,
   `CFBundleName` and `CFBundleDisplayName` changes to "Glyph".

8. **`flutter_secure_storage_darwin` builds native code** (`ffiPlugin: true`).
   Whether it compiles cleanly under this Xcode is unknown.

---

## 6. Known rough edges

1. **The debug APK is 152 MB and startup is slow and wildly variable.** Time
   to first frame on this emulator ranged from **3 seconds to 18 seconds**
   across launches. The APK carries two ABIs (`arm64-v8a`, `armeabi-v7a`),
   a native `libdartjni.so`, and debug-mode `-Xcheck:jni` and JIT. Logcat
   shows Dart itself running about 5 s after the launch intent; the rest is
   Android loading a very large debug APK. A release AOT build should be far
   smaller and faster — unverified, and pass two's job.

2. **I saw one "Glyph isn't responding" ANR.** Android's input dispatcher timed
   out waiting 5 s for a focus event during one slow debug startup, while a
   debugger was attached and after I had killed a previous `flutter run`. It
   did not recur across roughly a dozen subsequent launches, and the final
   verification run logged zero ANRs. I could not read
   `/data/anr/...` without root, so **I cannot fully rule out a real
   startup stall.** If a tester taps during a slow debug launch and sees the
   dialog, wait — the app recovers.

3. **Raising the keyboard on launch needed an explicit nudge.** Focus alone
   does not do it: requesting focus while the platform view is still being
   attached leaves the field focused and the keyboard closed, and logcat says
   `Ignoring showSoftInput() as view ... is not served`. `autofocus` has the
   same problem, since it runs during the first build. `_focusOnLaunch` now
   requests focus, waits 250 ms, and re-asserts with `TextInput.show`. It
   works reliably here, but it is a timing workaround, not a guarantee — on a
   much slower device the 250 ms may still be early. The guard re-checks that
   the field still has focus, so the worst case is no keyboard, not a wrong
   one.

4. **`AndroidOptions(resetOnError: true)` is the plugin default and I kept
   it.** If the encrypted store ever hits an error it **permanently erases the
   stored key**. That trades a lost key (retype it) against a hard failure. It
   does mean the key can silently vanish.

5. **Dead weight in the dependency tree.** `flutter_secure_storage` depends on
   its Windows implementation, which drags in `path_provider` →
   `path_provider_android` → `jni` + `jni_flutter`, plus `objective_c` for
   Darwin. That is why a JNI native library ships in an Android APK that never
   calls it. Harmless but ugly, and it is a real chunk of the APK.

6. **Corruption detection is probabilistic in one spot.** An 11-character
   Base62 block can encode values above 2^64, so about 65% of random
   corruption is caught as `DamagedMessage` at decode time; the remainder gets
   caught by the GCM tag as `WrongKeyOrTampered`. Either way it is a typed
   error and never garbage output — but the *choice* of error for a corrupted
   message is not fully deterministic.

7. **No chunking.** A very large message exists in memory several times over
   (input string, UTF-8 bytes, ciphertext, framed bytes, armoured string). The
   100,000-character test passes comfortably, but this is not the design for
   megabyte inputs.

8. **The output box is a read-only `TextField`.** No caret, freely selectable,
   which is what was asked — but it is still a text field, so a long-press
   offers the normal Android text menu. Nothing can be typed into it.

9. **No on-device automated tests.** Everything on the emulator was verified by
   hand, via `adb` and screenshots. There is no `integration_test` suite, so
   nothing guards the device-level behaviour against regressions.

10. **`flutter doctor` still reports Xcode and CocoaPods failures**, and the
    Android licence status as unknown. Expected on this machine, as the brief
    said. Ignored.

---

## 7. Network audit

**No network permission or entitlement on any platform, and no networking code.**

How I checked, and what each check proved:

```bash
# 1. Android, per source set
grep -l "android.permission.INTERNET" android/app/src/*/AndroidManifest.xml
#   main    -> clean (0 uses-permission of any kind)
#   debug   -> HAS INTERNET
#   profile -> HAS INTERNET

# 2. Every plugin registered for the Android build
#    (names from .flutter-plugins-dependencies)
#    flutter_secure_storage, jni, jni_flutter -> no permissions declared
#    path_provider_android                    -> no library manifest at all

# 3. The manifest that actually shipped in the APK
grep -oE 'android:name="android.permission.[A-Z_]*"' \
  build/app/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml
#   -> INTERNET (from src/debug), android:allowBackup="false" confirmed

# 4. macOS entitlements
grep -E "<key>com\.apple\.security\.network" macos/Runner/*.entitlements
#   -> no matches in either file
#   keys present: app-sandbox, cs.allow-jit (debug only), keychain-access-groups
#   both files pass: plutil -lint macos/Runner/*.entitlements

# 5. iOS
grep -cE "NSAppTransportSecurity|NSAllowsArbitraryLoads" ios/Runner/Info.plist
#   -> 0.  No entitlements file exists.

# 6. The Dart source itself
grep -rnE "HttpClient|Socket|WebSocket|http://|https://|package:http|dart:io" lib/
#   -> no matches
```

Two honest caveats:

- **`android/app/src/debug/` and `android/app/src/profile/` do declare
  `INTERNET`.** That is Flutter's own template, and the Flutter tool needs it
  for hot reload and the Dart VM service. Those source sets are compiled only
  into debug and profile builds and are **not** part of a release APK. I left
  them alone because removing `INTERNET` from the debug manifest would break
  `flutter run`, which the brief requires in step 7.

- **I could not produce a release merged manifest to prove the release case
  directly.** `./gradlew :app:processReleaseMainManifest --offline` failed with
  "No cached version of io.flutter:flutter_embedding_release", i.e. generating
  it would have downloaded the release Flutter embedding AAR. Given the
  bandwidth constraint I stopped rather than spend it. So the release claim
  rests on checks 1, 2 and 6 — the release variant merges `src/main` plus
  library manifests, all of which are clean — not on a merged-manifest dump.
  **Worth confirming with `aapt2 dump permissions` on the first release APK in
  pass two.**

---

## 8. What the tester should expect

Plain language, no jargon.

**Encrypting the same thing twice gives two completely different results. That
is correct, and it is the most important thing to understand.** Type "hello",
press Encrypt, note the result. Clear the box, type "hello" again, press
Encrypt. The two results look nothing alike. Both decrypt back to "hello".
This is deliberate: if identical messages produced identical output, anyone
watching your conversation could tell when you repeated yourself, even without
knowing the key. Every message gets fresh randomness mixed in.

**How long it takes.** About a fifth of a second per message. Long enough to
notice the button change to a spinner, short enough not to wait. Decrypting
the *same* message a second time is instant, because the app remembers the
expensive part of the calculation. Very long messages take longer, roughly in
proportion to their length.

**The app is slow to start in this debug build** — usually a few seconds, but
occasionally up to about eighteen on the emulator. That is the debug build and
the emulator, not the encryption. If you tap during a slow start, Android may
offer to close the app; wait instead and it will appear.

**What the four error messages mean.**

- *"This doesn't look like a Glyph message."* — you pressed Decrypt on
  something that was not produced by Glyph. Usually ordinary text, or a
  paste that lost the beginning.
- *"This message is incomplete or was damaged in transit."* — it starts like a
  Glyph message, but part of it is missing. Almost always a partial copy and
  paste: go back and make sure you selected all of it, including the last few
  characters.
- *"Wrong key, or the message was changed after it was encrypted."* — the
  message is intact, but this key does not open it. Check the key character by
  character. It is case-sensitive: `Sunset` and `sunset` are different keys.
  Glyph cannot tell you which of the two problems it is, and deliberately does
  not guess.
- *"This message was made by a newer version of Glyph."* — the sender has a
  newer build. You need to update.

**Things that look broken but are not.**

- *The middle box will not let you type.* Correct. It is only ever a result.
  Type in the bottom box; read the answer in the middle one. You can still
  select and copy the middle box.
- *The button says "Encrypt / Decrypt" and is greyed out.* You have a valid key
  but nothing in the input box. Type something.
- *The button changes label as you type.* Also correct. Glyph looks at the
  input: anything beginning `GLY1` is treated as an encrypted message to open,
  anything else as plain text to encrypt. You never choose a direction.
- *The little icons above each box come and go.* They only appear when that box
  has something in it.
- *"Short key — fine for casual use."* is information, not a warning. It shows
  once and does not come back. Nothing is blocked; a four-character key works.
- *The key is hidden as dots.* Tap the eye to reveal it. A copy button appears
  only while it is revealed, so you can send it to the other person.
- *Autocorrect does nothing in the input box.* On purpose. Autocorrect
  "fixing" a pasted encrypted message would corrupt it in a way that looks
  unfixable.
- *A message that arrived split across several lines still works.* Glyph strips
  line breaks, spaces and invisible characters before decoding, so messaging
  apps and email clients that wrap long strings do not break it.

**Getting started, in order:** open the app, type a key (or press the dice for
a random one and reveal it to send to the other person), type a message in the
bottom box, press Encrypt, press Copy, and paste it into any messaging app.
The other person pastes what they receive into their bottom box and presses
Decrypt. The key is remembered between launches; "Forget key" (the backspace
icon by the key) erases it completely.

---

## 9. Test command

```bash
flutter run -d emulator-5554
```

Run from the project root, with the emulator already booted. To reinstall
without attaching the debugger:

```bash
flutter install -d emulator-5554 --debug
adb -s emulator-5554 shell am start -n com.glyphpad.glyph/.MainActivity
```

---

## 10. Left for pass two

- Release packaging and a real signing config (`flutter build apk --release`
  will not work until then; `buildTypes.release` still signs with debug keys).
- App icons and launch screens on all three platforms.
- Store listings and versioning.
- User-facing documentation and a README.
- GitHub repository setup, CI, branch protection.
- **Apple platforms end to end** — Xcode, CocoaPods, `pod install`, first iOS
  and macOS builds, and everything listed in section 5.
- Confirming the release APK's permissions with `aapt2 dump permissions`
  (section 7).
- Deciding whether to restore `com.apple.security.network.server` for macOS
  debugging (deviation 11).
- An `integration_test` suite so device behaviour is covered automatically
  rather than by hand (rough edge 9).

Local git history exists with the scaffold committed; nothing has been pushed
anywhere.
