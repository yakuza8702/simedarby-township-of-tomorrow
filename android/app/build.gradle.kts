import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application") // version rides on the classpath (see libs.versions.toml)
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Version comes from the classpath (AGP's embedded KGP) — see libs.versions.toml.
    id("org.jetbrains.kotlin.android")
}

// ABI selection: the FINAL artifact is Android-hardware-only (arm64-v8a + armeabi-v7a).
// x86_64 exists solely for emulator testing: override with
//   ./gradlew ... -Ptownship.abiFilters=x86_64
//   flutter build apk --target-platform android-x64 -Ptownship.abiFilters=x86_64
val townshipAbis: List<String> = (findProperty("township.abiFilters") as String?)
    ?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() }
    ?: listOf("arm64-v8a", "armeabi-v7a")

android {
    namespace = "com.townshipoftomorrow.township_of_tomorrow"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.townshipoftomorrow.township_of_tomorrow"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = libs.versions.townshipVersionCode.get().toInt()
        versionName = libs.versions.township.get()
        ndk {
            abiFilters += townshipAbis
        }
    }

    buildFeatures {
        // MainActivity's adb debug-import hook reads BuildConfig.DEBUG.
        buildConfig = true
    }

    androidResources {
        // Size optimisation (v0.4.1): keep English only. Every resident-facing
        // string lives in Dart (lib/), so the ~85 locales that arrive through
        // AndroidX / ML Kit / Flutter engine resources are dead weight in
        // resources.arsc. This is the AGP 8 replacement for `resConfig "en"`.
        localeFilters += "en"
    }

    buildTypes {
        release {
            // TODO(#rel): dedicated release keystore before any Play upload.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Go core (gomobile bind): embedding kNN search, perceptual hashing, verify engine.
    implementation(files("libs/townshipcore.aar"))
}
