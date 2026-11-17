allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// desktop_drop is retained for macOS. Its Android module hardcodes API 33,
// below the Flutter embedding's dependency minimum; adjust only that module.
subprojects {
    if (name == "desktop_drop") {
        afterEvaluate {
            extensions.findByType<com.android.build.gradle.LibraryExtension>()?.compileSdk = 36
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
