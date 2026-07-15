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

// -----------------------------------------------------------------
// Force every Android library subproject to compileSdk = 36. Some
// plugins hard-code 33/34 while their transitive deps require 36
// (e.g. flutter_plugin_android_lifecycle). Gradle's CheckAarMetadata
// aborts the build without this override.
//
// The `afterEvaluate` MUST be attached inside the same subprojects
// block that reroutes `layout.buildDirectory`, and it MUST come
// BEFORE the `evaluationDependsOn(":app")` block below. Otherwise the
// target projects are already evaluated and Gradle throws
// `Cannot run Project.afterEvaluate(Action) when the project is
//  already evaluated.` — pitfalls §2 and §7.
// -----------------------------------------------------------------
subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    afterEvaluate {
        extensions
            .findByType(com.android.build.gradle.LibraryExtension::class.java)
            ?.apply {
                if ((compileSdk ?: 0) < 36) {
                    compileSdk = 36
                }
            }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
