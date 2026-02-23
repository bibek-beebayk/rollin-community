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

    tasks.whenTaskAdded {
        if (name == "assembleRelease") {
            val currentEnv = environment
            val currentVersion = flutter.versionName
            println("\n=========================================================")
            println("Current Environment: $currentEnv")
            println("Current Version: $currentVersion")
            println("=========================================================\n")
            doLast {
                val apkDir = layout.buildDirectory.get().dir("outputs/flutter-apk").asFile
                val oldApk = File(apkDir, "app-release.apk")
                if (oldApk.exists()) {
                    val newApk = File(apkDir, "rollin_community_${currentEnv}_${currentVersion}.apk")
                    oldApk.renameTo(newApk)
                    println("\n=========================================================")
                    println("✅ SUCCESS: APK Renamed to:")
                    println(newApk.absolutePath)
                    println("=========================================================\n")
                }
            }
        }
    }
}

flutter {
    source = "../.."
}
