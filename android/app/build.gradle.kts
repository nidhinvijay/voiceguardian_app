plugins {
    id("com.android.application")
    id("kotlin-android")
    // ...
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // <-- Just remove the "//"
}

android {
    namespace = "com.example.voice_guardian_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // Required for packages that rely on newer Java APIs (e.g., flutter_local_notifications)
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.voice_guardian_app"
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = 28
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

flutter {
    source = "../.."
}

dependencies {
    // Enable desugaring support libraries
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

