// ─────────────────────────────────────────────────────────────────────────────
// Single source of truth for plugin versions: gradle/libs.versions.toml.
// pluginManagement declares the versions from the catalog's [versions] table;
// the top-level plugins block below APPLIES the Flutter plugin loader (its
// version 1.0.0 is Flutter's own constant).
// ─────────────────────────────────────────────────────────────────────────────
pluginManagement {
    val catalog = java.util.Properties().apply {
        var section = ""
        for (raw in file("gradle/libs.versions.toml").readLines()) {
            val line = raw.substringBefore('#').trim()
            if (line.isEmpty()) continue
            if (line.startsWith("[") && line.endsWith("]")) { section = line; continue }
            val idx = line.indexOf('=')
            if (idx <= 0) continue
            val key = line.substring(0, idx).trim()
            val value = line.substring(idx + 1).trim().trim('"')
            if (section == "[versions]") setProperty(key, value)
        }
    }
    fun ver(key: String) = catalog.getProperty(key)
        ?: throw GradleException("gradle/libs.versions.toml is missing [versions] key '$key'")

    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }

    plugins {
        id("dev.flutter.flutter-plugin-loader") version ver("flutterPluginLoader")
        // AGP + KGP ride in via the flutter_tools includeBuild runtime classpath;
        // their versions must stay aligned with that build (see toml comment).
    }
}

plugins {
    // Applied here (not just declared) — this is what makes the loader include
    // every Android plugin from .flutter-plugins-dependencies.
    id("dev.flutter.flutter-plugin-loader")
}

include(":app")
