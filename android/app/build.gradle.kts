import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // ...
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // <-- Just remove the "//"
}

val keystorePropertiesFile = rootProject.file("android/key.properties")
val keystoreProperties = Properties()

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val releaseSigningConfigValues = keystoreProperties
    .takeIf { keystorePropertiesFile.exists() }
    ?.let {
        val alias = it.getProperty("keyAlias")?.takeUnless(String::isBlank)
        val keyPassword = it.getProperty("keyPassword")?.takeUnless(String::isBlank)
        val storePassword = it.getProperty("storePassword")?.takeUnless(String::isBlank)
        val storeFile = it.getProperty("storeFile")?.takeUnless(String::isBlank)
        if (alias != null && keyPassword != null && storePassword != null && storeFile != null) {
            mapOf(
                "keyAlias" to alias,
                "keyPassword" to keyPassword,
                "storePassword" to storePassword,
                "storeFile" to storeFile
            )
        } else {
            null
        }
    }

val releaseSigningConfigName = releaseSigningConfigValues?.let { "release" } ?: "debug"

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
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        getByName("debug")
        releaseSigningConfigValues?.let {
            create("release") {
                keyAlias = it["keyAlias"]!!
                keyPassword = it["keyPassword"]!!
                storePassword = it["storePassword"]!!
                storeFile = rootProject.file(it["storeFile"]!!)
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(releaseSigningConfigName)
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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

