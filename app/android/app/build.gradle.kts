import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. `android/key.properties` is git-ignored and holds the real
// keystore; when it is absent (a fresh clone, or CI without secrets) the build
// falls back to debug signing so `flutter run --release` still works locally.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.gwd.clubos"
    // Pinned above the Flutter SDK's default (34), because plugin AARs now
    // routinely declare they must be compiled against 36 or later and the build
    // fails outright at :checkReleaseAarMetadata otherwise.
    //
    // compileSdk only decides which APIs the code may *reference*. targetSdk —
    // which opts the app into new runtime behaviour — and minSdk, which decides
    // what the APK installs on, are deliberately left tracking the Flutter SDK
    // below, so raising this changes nothing about which phones can run it.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent application identity (Section 11). This must stay in step
        // with the iOS bundle ID and any Firebase/APNs project bindings.
        applicationId = "com.gwd.clubos"
        // Flutter's own supported floor. The Flutter tool rewrites this line if
        // it is pinned to a literal, so it is left tracking the SDK — which is
        // already above what home_widget and modern TLS require.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Minification is OFF, deliberately.
            //
            // home_widget pulls in WorkManager, which uses Room. Room loads its
            // generated `WorkDatabase_Impl` reflectively by name, so R8 renaming
            // it made `androidx.startup.InitializationProvider` throw during
            // application startup — before any Activity exists. The app died
            // instantly with no UI, and only in release builds.
            //
            // R8 buys very little here anyway: this APK's size is dominated by
            // the Flutter engine and native libraries, which R8 does not touch.
            // Correctness for a club app beats a few hundred KB.
            //
            // proguard-rules.pro carries the keep rules that make R8 safe if
            // anyone turns this back on. Re-enable only with a real device test.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
