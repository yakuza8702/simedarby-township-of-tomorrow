allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
// NOTE (CI fix): a previous `subprojects { afterEvaluate { extensions.findByType(
// com.android.build.gradle.BaseExtension::class.java) ... } }` block that
// forced compileOptions / kotlin jvmTarget 17 was REMOVED here. The root
// script's classpath does NOT contain AGP (AGP + KGP ride in via flutter_tools'
// includeBuild at the subproject level), so any com.android.* reference in this
// root script fails Kotlin DSL script compilation ("Unresolved reference
// 'android'"). No behaviour is lost: the only subproject (:app) already sets
// compileOptions { source/targetCompatibility = JavaVersion.VERSION_17 } and
// kotlin { compilerOptions { jvmTarget = JVM_17 } } in its own build script.

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// ─────────────────────────────────────────────────────────────────────────────
// Uniform Kotlin JVM target 17 for EVERY Kotlin subproject (:app + the Flutter
// plugin projects, e.g. :tflite_flutter).
//
// Why: KGP 2.2.10 defaults `jvmTarget` to the JVM running Gradle (CI = JDK 21).
// Plugin subprojects declare Java `compileOptions { JavaVersion.VERSION_11 }`
// and NO Kotlin compilerOptions, so the Android/Kotlin pair became
// 11-vs-21 and the build died in :tflite_flutter:compileReleaseKotlin with
// "Inconsistent JVM Target Compatibility Between Java (11) and Kotlin (21)".
//
// `plugins.withId(...)` (not a bare subprojects{} configure) is REQUIRED here:
// the Flutter plugin loader applies `kotlin-android` IMPERATIVELY to plugin
// subprojects while :app evaluates (FlutterPluginUtils.detectApplyingKotlin-
// GradlePlugin), i.e. after this script has run. withId also fires for an
// already-applied plugin, so either evaluation order is safe.
// Kotlin DSL types below resolve because settings.gradle.kts already requests
// org.jetbrains.kotlin.android (apply false) onto the build classpath.
subprojects {
    plugins.withId("org.jetbrains.kotlin.android") {
        extensions.configure(org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension::class.java) {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
    plugins.withId("org.jetbrains.kotlin.jvm") {
        extensions.configure(org.jetbrains.kotlin.gradle.dsl.KotlinJvmProjectExtension::class.java) {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
