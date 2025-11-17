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

// Fix namespace issue for plugins that don't have it defined
subprojects {
if (project.name == "twilio_programmable_video") {
        // Fix build.gradle - add namespace
        project.buildFile.parentFile.resolve("build.gradle").let { buildFile ->
            if (buildFile.exists()) {
                val content = buildFile.readText()
                if (!content.contains("namespace")) {
                    buildFile.writeText(
                        content.replace(
                            "android {",
                            "android {\n    namespace 'twilio.flutter.twilio_programmable_video'"
                        )
                    )
                }
            }
        }
        
        // Fix AndroidManifest.xml - remove package attribute
        project.buildFile.parentFile.resolve("src/main/AndroidManifest.xml").let { manifestFile ->
            if (manifestFile.exists()) {
                val content = manifestFile.readText()
                if (content.contains("package=")) {
                    manifestFile.writeText(
                        content.replace(
                            Regex("""package="[^"]+"\s*"""),
                            ""
                        )
                    )
                }
            }
        }
    }

    if (project.name == "flutter_local_notifications") {
        // Older releases (<14) ship without an Android namespace. Add it so AGP 8+ can configure the module.
        project.buildFile.parentFile.resolve("build.gradle").let { buildFile ->
            if (buildFile.exists()) {
                val content = buildFile.readText()
                if (!content.contains("namespace")) {
                    buildFile.writeText(
                        content.replace(
                            "android {",
                            "android {\n    namespace 'com.dexterous.flutterlocalnotifications'"
                        )
                    )
                }
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

