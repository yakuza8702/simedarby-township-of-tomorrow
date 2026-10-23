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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
