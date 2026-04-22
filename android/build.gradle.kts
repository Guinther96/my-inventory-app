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
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    plugins.withId("com.android.library") {
        val androidExtension = extensions.findByName("android") ?: return@withId

        val getNamespace = androidExtension.javaClass.methods.firstOrNull {
            it.name == "getNamespace" && it.parameterCount == 0
        }
        val currentNamespace = getNamespace?.invoke(androidExtension) as? String
        if (!currentNamespace.isNullOrBlank()) {
            return@withId
        }

        val setNamespace = androidExtension.javaClass.methods.firstOrNull {
            it.name == "setNamespace" &&
                it.parameterCount == 1 &&
                it.parameterTypes[0] == String::class.java
        } ?: return@withId

        val fallbackNamespace = if (name == "blue_thermal_printer") {
            "id.kakzaki.blue_thermal_printer"
        } else {
            "local.${name.replace('-', '_')}"
        }

        setNamespace.invoke(androidExtension, fallbackNamespace)
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
