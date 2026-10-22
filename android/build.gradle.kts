// ============================================================================
//  Root build.gradle.kts — Pathephon
// ============================================================================
plugins {
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

// Flutter engine artifacts (io.flutter:*_debug/release) live here.
// AGP 9 ignores settings.gradle.kts repositories when project declares its own.
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
        maven { url = uri("https://jitpack.io") }
    }
}

subprojects {
    project.evaluationDependsOn(":app")

    project.plugins.withId("com.android.library") {
        project.extensions.configure<com.android.build.api.dsl.LibraryExtension>("android") {
            if (namespace.isNullOrEmpty()) {
                val group = project.group.toString().ifEmpty { "com.example.${project.name.replace("-", "_")}" }
                namespace = group
                println("[pathephon] Injected namespace '" + group + "' into " + project.name)
            }
        }
        project.extensions.getByType<com.android.build.api.variant.LibraryAndroidComponentsExtension>().finalizeDsl { ext ->
            if (ext.compileSdk == null || ext.compileSdk!! < 36) {
                ext.compileSdk = 36
                println("[pathephon] Forced compileSdk=36 on " + project.name + " via finalizeDsl")
            }
        }
    }

    project.tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        val androidExt = project.extensions.findByName("android")
        if (androidExt is com.android.build.api.dsl.LibraryExtension) {
            val javaTarget = androidExt.compileOptions.targetCompatibility.toString()
            compilerOptions {
                jvmTarget.set(
                    when (javaTarget) {
                        "1.8", "8" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8
                        "11" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
                        "17" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
                        "21" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21
                        else -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8
                    }
                )
            }
        }
    }
}
