allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

// SAFE OVERRIDE FOR ALL PLUGINS WITHOUT AFTEREVALUATE CONFLICTS
subprojects {
    plugins.withId("com.android.library") {
        val android = extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)
        android?.compileSdk = 36
        android?.buildToolsVersion = "36.0.0"

        project.dependencies.add("compileOnly", "androidx.concurrent:concurrent-futures:1.2.0")
        project.dependencies.add("implementation", "androidx.concurrent:concurrent-futures:1.2.0")
        project.dependencies.add("implementation", "androidx.concurrent:concurrent-futures-ktx:1.2.0")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}