plugins {
}

rootProject.buildDir = file("../build")
subprojects {
    project.buildDir = file("${rootProject.buildDir}/${project.name}")
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register("clean", Delete::class) {
    delete(rootProject.buildDir)
}

allprojects {
    repositories {
        google()
        mavenCentral()
        maven { setUrl("https://jitpack.io") }
    }
}

subprojects {
    buildscript {
        configurations.configureEach {
            resolutionStrategy.eachDependency {
                if (requested.group == "com.android.tools.build" && requested.name == "gradle") {
                    useVersion("8.11.1")
                }
            }
        }
    }

    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension> {
            val androidExtensions =
                (this as org.gradle.api.plugins.ExtensionAware).extensions
            if (androidExtensions.findByName("flutter") == null) {
                androidExtensions.add(
                    "flutter",
                    mapOf("compileSdkVersion" to 35),
                )
            }
            if (namespace == null) {
                namespace = project.group.toString()
            }
        }
    }
}


