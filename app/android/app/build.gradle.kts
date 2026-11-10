import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Clé de signature de release : app/android/key.properties, jamais versionné (P8).
// Champs : storeFile (chemin absolu, ou relatif à app/android/app/), storePassword, keyAlias,
// keyPassword. Sur le PC, écrit à la main ; dans la CI, écrit par le job à partir des
// secrets, ou avec une clé jetable pour la seule compilation.
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    FileInputStream(keyPropertiesFile).use { keyProperties.load(it) }
}

android {
    namespace = "fr.kassbeer.kass_beer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        if (keyPropertiesFile.exists()) {
            create("release") {
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
            }
        }
    }

    defaultConfig {
        applicationId = "fr.kassbeer.kass_beer"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Tirés de « version: X.Y.Z+N » de pubspec.yaml : N devient le versionCode (P7).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Aucune signature de débogage en release : sans key.properties, la
            // compilation de release échoue (voir plus bas) au lieu de produire un APK
            // signé par une clé que Firebase ne connaît pas.
            if (keyPropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// FileProvider du partage d'un export (ADR-007). Version déjà résolue par le graphe des
// greffons Firebase (./gradlew :app:dependencies --configuration releaseRuntimeClasspath,
// relevé du 2026-11-10) : la déclarer n'ajoute aucun code à l'APK. À remonter avec eux.
dependencies {
    implementation("androidx.core:core:1.17.0")
}

flutter {
    source = "../.."
}

gradle.taskGraph.whenReady {
    val wantsRelease = allTasks.any { it.name.contains("Release") && it.project == project }
    if (wantsRelease && !keyPropertiesFile.exists()) {
        throw GradleException(
            "app/android/key.properties absent : la compilation de release exige la clé " +
                "de signature (CLAUDE.md, P8).",
        )
    }
}
