plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

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
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
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
