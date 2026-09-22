import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.budget_pro1"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.budget_pro1"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

// Copy release APKs as BudgetPro_v<version>_<ddMMMyy>[_abi].apk
afterEvaluate {
    tasks.named("assembleRelease").configure {
        doLast {
            val apkDir = layout.buildDirectory.dir("outputs/flutter-apk").get().asFile
            val shortDate = SimpleDateFormat("ddMMMyy", Locale.US).format(Date())
            val ver = flutter.versionName
            val copies = listOf(
                "app-release.apk" to "BudgetPro_v${ver}_$shortDate.apk",
                "app-arm64-v8a-release.apk" to "BudgetPro_v${ver}_${shortDate}_arm64.apk",
                "app-armeabi-v7a-release.apk" to "BudgetPro_v${ver}_${shortDate}_arm32.apk",
                "app-x86_64-release.apk" to "BudgetPro_v${ver}_${shortDate}_x86_64.apk",
            )
            for ((srcName, dstName) in copies) {
                val src = File(apkDir, srcName)
                if (src.exists()) {
                    src.copyTo(File(apkDir, dstName), overwrite = true)
                }
            }
        }
    }
}
