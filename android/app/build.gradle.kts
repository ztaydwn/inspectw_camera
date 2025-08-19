plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.inspectw_camera"
    compileSdkVersion 34
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.inspectw_camera"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdkVersion 21
        targetSdkVersion 34
        versionCode 1
        versionName "1.0"
        multiDexEnabled true
    }

    buildTypes {
        release {
            // Primero valida con minify OFF; si todo ok, actívalo y usa ProGuard.
            minifyEnabled true      // pon false para aislar problemas de R8
            shrinkResources true     // opcional
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'),
                    'proguard-rules.pro'
        }
        debug {
            minifyEnabled false
        }
    }
}