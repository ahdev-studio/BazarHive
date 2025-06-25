plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream
import java.io.File
import org.gradle.api.JavaVersion

val keystoreProperties = Properties()
val keystoreFile = File(project.projectDir.parentFile, "key.properties")
if (keystoreFile.exists()) {
    try {
        FileInputStream(keystoreFile).use { stream ->
            keystoreProperties.load(stream)
        }
    } catch (e: Exception) {
        println("Warning: Could not load key.properties file. Release builds may fail to sign.")
    }
}

android {
    namespace = "com.example.bazarhive"
    compileSdk = flutter.compileSdkVersion.toInt()

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.bazarhive"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 23 // Required for flutter_secure_storage
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
    create("release") {
        val keystoreProps = keystoreProperties // Uses the above loaded properties

        val storeFileName = keystoreProps.getProperty("storeFile")
        val loadedStorePassword = keystoreProps.getProperty("storePassword")
        val loadedKeyAlias = keystoreProps.getProperty("keyAlias")
        val loadedKeyPassword = keystoreProps.getProperty("keyPassword")

        if (storeFileName != null && loadedStorePassword != null && loadedKeyAlias != null && loadedKeyPassword != null) {
            storeFile = project.file(storeFileName)
            storePassword = loadedStorePassword
            keyAlias = loadedKeyAlias
            keyPassword = loadedKeyPassword


        } else {






        }
    }
}

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    implementation("com.google.firebase:firebase-firestore-ktx")
    implementation("com.google.firebase:firebase-auth-ktx")
    implementation("com.google.android.gms:play-services-auth:20.7.0")
    implementation("com.google.android.gms:play-services-drive:17.0.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.7.3")
}

flutter {
    source = "../.."
}
