plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// --- امضای نسخهٔ انتشار -------------------------------------------------
// اطلاعات کلید هرگز داخل سورس ذخیره نمی‌شود؛ از Gradle property یا متغیر محیطی
// خوانده می‌شود (راهنما: documentation/راهنمای انتشار.txt).
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
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // شناسهٔ بستهٔ برنامه — پس از انتشار هرگز تغییر نمی‌کند.
        applicationId = "com.sanjab.game"
        minSdk = 24          // Android 7.0
        targetSdk = flutter.targetSdkVersion
        versionCode = 6      // Sanjab 1.0.0
        versionName = "1.0.0"
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
            // R8/minify در این محیط ساخت خاموش است (حافظهٔ محدود)؛ برای انتشار
            // روی ماشین قوی‌تر می‌توانید isMinifyEnabled را true کنید.
            isMinifyEnabled = false
            isShrinkResources = false
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
