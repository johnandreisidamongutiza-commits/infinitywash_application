buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // Add the dependency for the Google services Gradle plugin
        classpath("com.google.gms:google-services:4.4.0")
    }
}

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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    val android = extensions.findByName("android")
    if (android != null) {
        configureAndroid(android)
    } else {
        afterEvaluate {
            val postAndroid = extensions.findByName("android")
            if (postAndroid != null) {
                configureAndroid(postAndroid)
            }
        }
    }
}

fun configureAndroid(android: Any) {
    try {
        // Set NDK version for all Android subprojects (including jni package)
        val setNdkVersion = android.javaClass.getMethod("setNdkVersion", String::class.java)
        setNdkVersion.invoke(android, "25.1.8937393")
        
        val getDefaultConfig = android.javaClass.getMethod("getDefaultConfig")
        val defaultConfig = getDefaultConfig.invoke(android)
        val getNdk = defaultConfig.javaClass.getMethod("getNdk")
        val ndk = getNdk.invoke(defaultConfig)
        val getAbiFilters = ndk.javaClass.getMethod("getAbiFilters")
        @Suppress("UNCHECKED_CAST")
        val abiFilters = getAbiFilters.invoke(ndk) as? MutableSet<String>
        abiFilters?.let {
            it.clear()
            it.addAll(setOf("armeabi-v7a", "arm64-v8a", "x86_64"))
        }
    } catch (e: Exception) {
        // Ignore if method not found or signature differs
    }
}
