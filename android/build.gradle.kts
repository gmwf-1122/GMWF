import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

val newBuildDir = layout.projectDirectory.dir("../build")
rootProject.layout.buildDirectory.set(newBuildDir)

subprojects {
    val subprojectBuildDir = rootProject.layout.buildDirectory.dir(project.name).get()
    project.layout.buildDirectory.set(subprojectBuildDir)
}

repositories {
    google()
    mavenCentral()
    gradlePluginPortal()
}

subprojects {
    project.evaluationDependsOn(":app")

    tasks.withType<KotlinCompile>().configureEach {
        compilerOptions {
            val currentVersion = languageVersion.orNull
            if (currentVersion != null) {
                val versionStr = currentVersion.version
                if (versionStr == "1.3" || versionStr == "1.4" || versionStr == "1.5" || versionStr == "1.6" || versionStr == "1.7") {
                    languageVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_8)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
