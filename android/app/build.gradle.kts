import java.util.Base64

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

    val releaseVersionName = defaultConfig.versionName ?: "1.0.0"
    val releaseVersionCode = defaultConfig.versionCode ?: 1
    val normalizedEnv = environment.lowercase().ifBlank { "dev" }
    val renamedReleaseApk =
        "staff_chat_${normalizedEnv}_v${releaseVersionName}+${releaseVersionCode}_release.apk"

    val syncFlutterExpectedReleaseApk by tasks.registering(Copy::class) {
        from(layout.buildDirectory.dir("outputs/apk/release"))
        include("app-release.apk")
        into(layout.buildDirectory.dir("outputs/flutter-apk"))
    }

    val copyRenamedReleaseApk by tasks.registering(Copy::class) {
        from(layout.buildDirectory.dir("outputs/apk/release"))
        include("app-release.apk")
        into(layout.buildDirectory.dir("outputs/flutter-apk"))
        rename("app-release.apk", renamedReleaseApk)
    }

    tasks.matching {
        it.name == "assembleRelease" ||
            it.name == "packageRelease" ||
            it.name == "flutterBuildRelease"
    }.configureEach {
        finalizedBy(syncFlutterExpectedReleaseApk)
        finalizedBy(copyRenamedReleaseApk)
    }
}

flutter {
    source = "../.."
}
