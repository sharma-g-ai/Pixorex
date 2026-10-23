plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.amzur.equiptrack"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.amzur.equiptrack"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Demo/review APKs sign release with the debug keystore so installs work
    // without a private keystore. Use a production signingConfig before store release.
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Bundled Latin text recognition (offline, packaged with the APK).
    // Do not substitute the unbundled Play-services download-on-demand artifact.
    implementation("com.google.mlkit:text-recognition:16.0.1")
    // Google's scanner supplies automatic page detection, crop, rotation,
    // cleanup, and scan UI. The app retains its local manual scanner fallback.
    implementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0")
}
