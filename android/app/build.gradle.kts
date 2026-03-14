import java.util.Base64
import java.util.Properties

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

    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(keystorePropertiesFile.inputStream())
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

    flavorDimensions += "dist"
    productFlavors {
        create("play") {
            dimension = "dist"
            // Keep package id same for Play/App Signing continuity.
            resValue("string", "app_name", "Rollin Community")
        }
        create("direct") {
            dimension = "dist"
            resValue("string", "app_name", "Rollin Community")
        }
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties.getProperty("storeFile")
            val storePasswordValue = keystoreProperties.getProperty("storePassword")
            val keyAliasValue = keystoreProperties.getProperty("keyAlias")
            val keyPasswordValue = keystoreProperties.getProperty("keyPassword")

            if (storeFilePath.isNullOrBlank() ||
                storePasswordValue.isNullOrBlank() ||
                keyAliasValue.isNullOrBlank() ||
                keyPasswordValue.isNullOrBlank()
            ) {
                throw GradleException(
                    "Missing release signing config. Define storeFile, storePassword, keyAlias, and keyPassword in android/key.properties."
                )
            }

            storeFile = file(storeFilePath)
            storePassword = storePasswordValue
            keyAlias = keyAliasValue
            keyPassword = keyPasswordValue
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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

    val copyRenamedReleaseArtifacts by tasks.registering(Copy::class) {
        from(layout.buildDirectory.dir("outputs/apk")) {
            include("**/*-release.apk")
        }
        from(layout.buildDirectory.dir("outputs/bundle")) {
            include("**/*-release.aab")
        }
        into(layout.buildDirectory.dir("outputs/renamed"))
        includeEmptyDirs = false

        eachFile {
            val originalName = name
            val extension = originalName.substringAfterLast('.')
            val baseName = originalName.removeSuffix(".${extension}")
            val flavor = baseName
                .removePrefix("app-")
                .removeSuffix("-release")
                .ifBlank { "default" }

            name =
                "staff_chat_${flavor}_${normalizedEnv}_v${releaseVersionName}+${releaseVersionCode}_release.${extension}"
        }
    }

    tasks.matching {
        (it.name.startsWith("assemble") && it.name.endsWith("Release")) ||
            (it.name.startsWith("bundle") && it.name.endsWith("Release")) ||
            it.name == "flutterBuildRelease"
    }.configureEach {
        finalizedBy(copyRenamedReleaseArtifacts)
    }
}

flutter {
    source = "../.."
}
