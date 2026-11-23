import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// --- Single source of truth for the app version ---------------------------
// pubspec.yaml holds "version: MAJOR.MINOR.PATCH+BUILD"; versionName and
// versionCode are derived from it so the two files can never drift apart.
// The parsing lives in a function because a top-level `val` cannot be assigned
// from inside a `run {}` block (Kotlin only defers assignment of local vals).
fun readAppVersion(): Pair<String, Int> {
    val pubspec = file("../../pubspec.yaml")
    val rawVersion =
        pubspec
            .readLines()
            .firstOrNull { it.startsWith("version:") }
            ?.removePrefix("version:")
            ?.trim()
            ?: throw GradleException("pubspec.yaml has no version line.")
    val rawName = rawVersion.substringBefore('+').trim().removeSurrounding("\"")
    val rawBuild =
        rawVersion.substringAfter('+', "0").trim().removeSurrounding("\"").toIntOrNull()
    if (rawName.isEmpty() || rawBuild == null) {
        throw GradleException("pubspec.yaml version '$rawVersion' is not MAJOR.MINOR.PATCH+BUILD.")
    }
    return rawName to rawBuild
}

val (appVersionName, appVersionCode) = readAppVersion()
logger.lifecycle("Sanjab version: name=$appVersionName code=$appVersionCode")

// --- Release signing ----------------------------------------------------
// Key material is never committed: it is read from a Gradle property or an
// environment variable (see docs/ANDROID_RELEASE.md).
val releaseStorePath: String? =
    (project.findProperty("ANDROID_KEYSTORE") as String?)
        ?: System.getenv("ANDROID_KEYSTORE")
val releaseStorePassword: String? =
    (project.findProperty("ANDROID_KEYSTORE_PASS") as String?)
        ?: System.getenv("ANDROID_KEYSTORE_PASS")
val releaseKeyAlias: String? =
    (project.findProperty("ANDROID_KEY_ALIAS") as String?)
        ?: System.getenv("ANDROID_KEY_ALIAS")
val releaseKeyPassword: String? =
    (project.findProperty("ANDROID_KEY_PASS") as String?)
        ?: System.getenv("ANDROID_KEY_PASS")

val releaseSigningValues = listOf(
    releaseStorePath,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
)
val releaseSigningConfigured = releaseSigningValues.all { !it.isNullOrBlank() }
val releaseSigningPartiallyConfigured =
    releaseSigningValues.any { !it.isNullOrBlank() } && !releaseSigningConfigured

if (releaseSigningPartiallyConfigured) {
    throw GradleException("Provide all four Android release signing values, or none.")
}

android {
    namespace = "com.sanjab.game"
    // Explicit Android API levels: do not rely on Flutter's floating defaults.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Application ID: never changes after the first publication.
        applicationId = "com.sanjab.game"
        minSdk = 24          // Android 7.0
        targetSdk = 36       // explicit: do not inherit a floating default
        versionCode = appVersionCode     // read from pubspec.yaml
        versionName = appVersionName     // read from pubspec.yaml
    }

    signingConfigs {
        create("release") {
            if (releaseSigningConfigured) {
                storeFile = file(releaseStorePath!!)
                storePassword = releaseStorePassword!!
                keyAlias = releaseKeyAlias!!
                keyPassword = releaseKeyPassword!!
            }
        }
    }

    buildTypes {
        release {
            // R8 minify + resource shrinking are enabled for the release build.
            // They need a machine/CI runner with sufficient memory; the release
            // workflow builds on GitHub Actions (see org.gradle.jvmargs in
            // android/gradle.properties). If a release build reports missing
            // classes from a plugin, add minimal keep rules to
            // android/app/proguard-rules.pro instead of disabling minification.
            isMinifyEnabled = true
            isShrinkResources = true
            // Never fall back to the debug certificate for a release build.
            signingConfig = signingConfigs.getByName("release")
        }
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
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
