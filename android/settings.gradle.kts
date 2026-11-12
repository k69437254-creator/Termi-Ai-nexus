
pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        val localProperties = file("local.properties")
        require(localProperties.exists()) { "Create android/local.properties with flutter.sdk and sdk.dir. See README.md." }
        localProperties.inputStream().use { properties.load(it) }
        properties.getProperty("flutter.sdk") ?: error("flutter.sdk not set in android/local.properties")
    }
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.3.1" apply false
    id("com.android.library") version "9.3.1" apply false
}

include(":app", ":aram-engine", ":llama")

project(":aram-engine").projectDir = file("aram-engine")
project(":llama").projectDir = file("aram-source/vendor/llama.cpp/examples/llama.android/lib")
