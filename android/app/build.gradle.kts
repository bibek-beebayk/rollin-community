import java.util.Base64
import java.io.File

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Google Services for Firebase
    id("com.google.gms.google-services")
}

android {
    namespace = "com.hirollin.community"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        jvmToolchain(17)
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.hirollin.community"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
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

    // Extract the ENV dart-define variable automatically injected by Flutter
    val dartDefines = if (project.hasProperty("dart-defines")) project.property("dart-defines") as String else ""
    val environment = dartDefines.split(",").mapNotNull {
        try {
            val decoded = String(Base64.getDecoder().decode(it))
            if (decoded.startsWith("ENV=")) decoded.substringAfter("ENV=") else null
        } catch (e: Exception) {
            null
        }
    }.firstOrNull() ?: "dev"

    applicationVariants.all {
        val variant = this
        variant.outputs
            .map { it as com.android.build.gradle.internal.api.BaseVariantOutputImpl }
            .forEach { output ->
                val outputFileName = "rollin_community_${environment}_${variant.versionName}.apk"
                output.outputFileName = outputFileName
            }
    }
}

flutter {
    source = "../.."
}
