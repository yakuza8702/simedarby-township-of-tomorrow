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
        // AGP + KGP versions are declared here as build-wide defaults, read from
        // gradle/libs.versions.toml (single source of truth). They are then
        // REQUESTED with `apply false` by the top-level plugins block below.
        // Both halves are needed: the defaults alone only work when something
        // already puts AGP on this build's classpath (locally the flutter_tools
        // includeBuild above did), while a FRESH clone (CI) fails in :app with
        // "Plugin Repositories (plugin dependency must include a version number
        // for this source)". Requesting them at settings level puts AGP/KGP on
        // the settings classpath, inherited by every project and by the included
        // Flutter plugin build — what Flutter's stock template does with literal
        // versions.
        id("com.android.application") version ver("agp") apply false
        id("org.jetbrains.kotlin.android") version ver("kotlin") apply false
    }
}

plugins {
    // Applied here (not just declared) — this is what makes the loader include
    // every Android plugin from .flutter-plugins-dependencies.
    id("dev.flutter.flutter-plugin-loader")
    // Resolved, not applied: puts AGP/KGP on the settings classpath so :app can
    // keep applying them without a version (versions come from the defaults above).
    id("com.android.application") apply false
    id("org.jetbrains.kotlin.android") apply false
}

include(":app")
