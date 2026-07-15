import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and
    // Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// google-services.json is delivered by the operator alongside the
// Firebase project. If the file is present we apply the plugin;
// otherwise the app still builds — Firebase init in main.dart is
// wrapped in try/catch so a missing configuration means "no push"
// rather than a crash.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Load the release keystore. Missing files fall back to debug signing
// so builds succeed locally before the signing bundle arrives.
val signingProps = Properties()
val signingPropsFile = rootProject.file("key.properties")
val hasSigning = signingPropsFile.exists()
if (hasSigning) {
    signingProps.load(FileInputStream(signingPropsFile))
}

android {
    namespace = "com.chicksprint.chicksprintgame"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications 18.x uses java.time.* on API 30
        // fallback paths — desugaring is mandatory. Pitfalls §5.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.chicksprint.chicksprintgame"
        minSdk = 30
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (hasSigning) {
        signingConfigs {
            create("release") {
                val storeFilePath = signingProps["storeFile"] as String
                storeFile = rootProject.file(storeFilePath)
                storePassword = signingProps["storePassword"] as String
                keyAlias = signingProps["keyAlias"] as String
                keyPassword = signingProps["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = if (hasSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
