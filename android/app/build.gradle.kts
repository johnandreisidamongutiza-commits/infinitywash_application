plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.infinitywash"
    compileSdk = flutter.compileSdkVersion
    // NDK 25.1.8937393 is required for compatibility with CMake 3.22.1 and jni package 1.0.3
    // NDK 28+ introduces breaking changes to toolchain structure that cause linker failures
    // for x86/x86_64 architectures (cannot find crtbegin_dynamic.o, crtend_android.o, and standard libs).
    // This is a known incompatibility between NDK 28 and CMake 3.22.1.
    // TODO: Upgrade to NDK 28+ when CMake 3.28+ and jni package with NDK 28 support are available
    ndkVersion = "25.1.8937393"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.infinitywash"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        ndk {
            abiFilters.addAll(setOf("armeabi-v7a", "arm64-v8a", "x86_64"))
        }
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
