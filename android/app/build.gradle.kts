import java.io.StringReader
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Release signing input: <repo>/android/key.properties
//
// WHY THIS IS MORE THAN FOUR LINES OF PROPERTY READING
//
// A release build that fails to sign does not look like a failure. AGP names an
// unsigned artifact `app-release-unsigned.apk`, but Flutter's own Gradle plugin
// then copies whatever AGP produced into build/app/outputs/flutter-apk/ and
// renames it to `app-release.apk`. The single warning signal AGP gives you is
// erased, and `flutter build apk --release` prints a green tick over an APK
// nobody can install as an update. So the rules here are:
//
//   - never fall back to debug signing,
//   - never produce an unsigned release,
//   - fail loudly and early instead, naming what is missing,
//   - and never, ever put a password in a message, a log line or an exception.
//
// `layout.settingsDirectory` is the directory holding settings.gradle.kts, i.e.
// <repo>/android, so this resolves to <repo>/android/key.properties. Same file
// as `rootProject.file("key.properties")`, but it does not reach across
// projects, so it stays valid if Isolated Projects is ever enabled.
//
// Read through `providers.fileContents(...)` rather than `File.readText()`: the
// provider registers the file as a tracked build-configuration input, so
// creating, editing or deleting key.properties correctly invalidates the
// configuration cache. `.asBytes` rather than `.asText` because the charset of
// `getAsText()` is unspecified -- UTF-8 on JDK 18+ per JEP 400, but
// locale-dependent before that. Decoding explicitly removes the question.
//
// The value is absent when the file does not exist, which is the ordinary
// `flutter run` / debug case and must not fail anything.
// ---------------------------------------------------------------------------
val keystorePropertiesLocation = layout.settingsDirectory.file("key.properties")
val keystorePropertiesFile: File = keystorePropertiesLocation.asFile

val keystoreProperties: Properties? =
    providers.fileContents(keystorePropertiesLocation).asBytes.orNull
        ?.toString(Charsets.UTF_8)
        ?.let { text ->
            // The Reader overload, not the InputStream one: Properties.load
            // decodes an InputStream as ISO-8859-1 and would silently corrupt a
            // non-ASCII password.
            Properties().apply { load(StringReader(text)) }
        }

val requiredKeystoreKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")

// Key NAMES only. This list never holds, and is never derived from, a value.
val missingKeystoreKeys: List<String> =
    keystoreProperties
        ?.let { props -> requiredKeystoreKeys.filter { props.getProperty(it).isNullOrBlank() } }
        ?: requiredKeystoreKeys

val releaseKeystoreFile: File? =
    keystoreProperties?.let { props ->
        if (missingKeystoreKeys.isNotEmpty()) {
            null
        } else {
            // An absolute storeFile is used exactly as given. A relative one
            // resolves against the directory holding key.properties, i.e.
            // <repo>/android -- deliberately not <repo>/android/app, which is
            // what project.file() would have done and is never what someone
            // writing this file means.
            val raw = props.getProperty("storeFile").trim()
            val asGiven = File(raw)
            if (asGiven.isAbsolute) asGiven else File(keystorePropertiesFile.parentFile, raw)
        }
    }

/**
 * Single source of truth for "may this build produce a release artifact?".
 * Null means the release signing config is complete and usable.
 *
 * SECURITY: this string is the only thing the guard task may surface. It
 * contains file paths and property key names only. No storePassword,
 * keyPassword or keyAlias VALUE is interpolated into it, logged, or attached to
 * an exception anywhere in this file. The storeFile path is included on
 * purpose: it is a path, not a credential, and AGP prints it anyway.
 */
val releaseSigningFailure: String? = run {
    val propsPath = keystorePropertiesFile.absolutePath
    val keystore = releaseKeystoreFile
    when {
        keystoreProperties == null ->
            """
            Release signing is not configured, and this build will not sign a
            release build with debug keys.

              Missing file: $propsPath

            Create it with exactly these four keys:

              storeFile=<absolute path to your .jks>
              storePassword=<secret>
              keyAlias=<alias>
              keyPassword=<secret>

            key.properties, *.jks and *.keystore are already gitignored.
            Debug and profile builds do not need this file.
            """.trimIndent()

        missingKeystoreKeys.isNotEmpty() ->
            """
            Release signing is incomplete, and this build will not sign a
            release build with debug keys.

              File: $propsPath
              Missing or empty keys: ${missingKeystoreKeys.joinToString(", ")}

            Fill in the keys listed above. No value from key.properties is ever
            printed by this build.
            """.trimIndent()

        keystore == null || !keystore.isFile ->
            """
            Release signing is misconfigured, and this build will not sign a
            release build with debug keys.

              File: $propsPath
              'storeFile' does not point at an existing file:
                ${keystore?.absolutePath}

            Restore the keystore or correct 'storeFile'. An absolute path is
            used as given; a relative path resolves against
            ${keystorePropertiesFile.parentFile.absolutePath}.
            """.trimIndent()

        else -> null
    }
}

// ---------------------------------------------------------------------------
// Test channel.
//
// CI publishes a rolling test APK that has to install *alongside* the real
// Glyph on the same phone, which means a different application ID and a
// different launcher label. Everything else -- the cipher, the envelope, the
// version bytes -- is identical; this is the same app with a different name on
// the box.
//
// Read through providers.gradleProperty() rather than project.property() or
// the `project.hasProperty` idiom: the provider registers the property as a
// tracked build-configuration input, so the configuration cache is correctly
// invalidated when it changes, and nothing reaches into `project` at execution
// time. It resolves both spellings:
//
//   ./gradlew ... -PglyphChannel=test
//   ORG_GRADLE_PROJECT_glyphChannel=test flutter build apk --release
//
// The second is the one CI uses, because `flutter build` owns the Gradle
// command line and there is no supported way to add -P to it.
//
// Absent, empty, or any value other than "test" means the ordinary build. A
// typo therefore produces a normal Glyph, never a half-renamed one.
// ---------------------------------------------------------------------------
val isTestChannel: Boolean = providers.gradleProperty("glyphChannel").orNull == "test"

android {
    namespace = "com.glyphpad.glyph"
    // Pinned deliberately: never let a plugin bump these. A changed NDK version
    // triggers a fresh ~2.8 GB download.
    //
    // compileSdk is 37 because flutter_secure_storage 11.0.0 publishes AAR
    // metadata requiring callers to compile against API 37 or later. The
    // android-37.0 platform is installed locally, so this costs no download.
    // AGP 9.1.0 only "recommends" up to 36, hence the suppression flag in
    // gradle.properties.
    compileSdk = 37
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.glyphpad.glyph"
        // minSdk is 24, not the 23 originally intended: the Android module of
        // flutter_secure_storage 11.0.0 declares minSdk 24 and the manifest
        // merger refuses a lower value in the consuming app.
        minSdk = 24
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Test channel only. The suffix applies to the application ID, not to
        // `namespace`, so the R class and the relative ".MainActivity" in the
        // manifest still resolve against com.glyphpad.glyph.
        if (isTestChannel) {
            applicationIdSuffix = ".test"
        }

        // Consumed by android:label in AndroidManifest.xml. Always set, in both
        // channels: an unset placeholder is a manifest-merger failure, not a
        // default, so there is no way to end up with a literal "${appLabel}" on
        // the home screen.
        manifestPlaceholders["appLabel"] = if (isTestChannel) "Glyph (test)" else "Glyph"
    }

    // Declared before buildTypes: the release build type looks this config up by
    // name below.
    signingConfigs {
        // Created ONLY when key.properties is present, complete, and the
        // keystore actually exists on disk. A half-populated signing config is
        // worse than no config at all: AGP treats a config whose storeFile is
        // null as "do not sign", and the resulting unsigned APK reaches
        // flutter-apk/app-release.apk under a name that looks perfectly fine.
        if (releaseSigningFailure == null) {
            create("release") {
                storeFile = releaseKeystoreFile
                storePassword = keystoreProperties?.getProperty("storePassword")
                keyAlias = keystoreProperties?.getProperty("keyAlias")
                keyPassword = keystoreProperties?.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Signed with the "release" config built above from
            // android/key.properties. There is deliberately no
            // signingConfigs.getByName("debug") fallback. If the config could
            // not be created, signingConfig stays null and
            // :app:verifyReleaseSigning below fails the build before AGP can
            // emit an artifact.
            signingConfigs.findByName("release")?.let { signingConfig = it }
        }
    }
}

// ---------------------------------------------------------------------------
// Release signing guard.
//
// This task, not the DSL above, is what enforces "a release build fails
// loudly". It is a real task rather than a doFirst {} because a doFirst is
// skipped when its task is UP-TO-DATE or FROM-CACHE, and a guard that can be
// skipped is not a guard. It declares no outputs and is explicitly never up to
// date, so it runs on every release invocation.
//
// It throws rather than warns: `flutter build` passes -q, which shows QUIET and
// ERROR only, so logger.warn and logger.lifecycle would be invisible in exactly
// the situation this exists for.
// ---------------------------------------------------------------------------
val verifyReleaseSigning =
    tasks.register("verifyReleaseSigning") {
        group = "verification"
        description =
            "Fails the build if android/key.properties cannot produce a valid release signing config."
        outputs.upToDateWhen { false }
        // Capture ONLY this local String. Referencing `project`, `project.logger`
        // or anything holding a keystore password inside the action would be a
        // configuration-cache violation ("Tasks must not use any Project objects
        // during execution") and would risk serialising a password into
        // android/.gradle/configuration-cache.
        val failure: String? = releaseSigningFailure
        doLast {
            if (failure != null) {
                throw GradleException(failure)
            }
        }
    }

// Task names verified against AGP 9.1.0's computeTaskName(prefix, suffix):
//   TaskManager.AbstractPreBuildCreationAction -> preReleaseBuild
//   PackageApplication                         -> packageRelease
//   PackageBundleTask                          -> packageReleaseBundle
//   FinalizeBundleTask                         -> signReleaseBundle
//   BundleToStandaloneApkTask                  -> packageReleaseUniversalApk
//
// preReleaseBuild makes the failure happen in seconds rather than after the
// whole Dart AOT compile. The rest are the last line of defence, immediately
// before an artifact would be written. If flavours are ever added these become
// package<Flavour>Release and must be regenerated.
val releaseSigningGuardedTasks =
    setOf(
        "preReleaseBuild",
        "packageRelease",
        "packageReleaseBundle",
        "signReleaseBundle",
        "packageReleaseUniversalApk",
    )

// tasks.configureEach {} is lazy: the action runs only for tasks that are
// actually realised. tasks.matching {}.configureEach {} is NOT -- the Gradle 9
// docs state matching() "requires all tasks to be created". A debug-only
// invocation (flutter run, assembleDebug) never realises any task above, so it
// never sees this guard and never needs key.properties.
tasks.configureEach {
    if (name in releaseSigningGuardedTasks) {
        dependsOn(verifyReleaseSigning)
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
