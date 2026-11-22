import java.security.MessageDigest
plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
val apiUrl = project.property("API_BASE_URL").toString()
android {
    namespace = "com.afghanvpn.app"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.afghanvpn.app"
        minSdk = 24; targetSdk = 34; versionCode = 1; versionName = "0.2.0"
        buildConfigField("String", "API_BASE_URL", "\"$apiUrl\"")
    }
    signingConfigs {
        create("release") {          // secrets come from the environment (GitHub Secrets), never from the repository
            val ks = System.getenv("KEYSTORE_PATH")
            if (ks != null) {
                storeFile = file(ks); storePassword = System.getenv("KEYSTORE_PASSWORD")
                keyAlias = System.getenv("KEY_ALIAS"); keyPassword = System.getenv("KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true; isShrinkResources = true; isDebuggable = false
            isCrunchPngs = false          // never re-encode the official welcome image
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.getByName("release")
        }
    }
    lint { abortOnError = false; checkReleaseBuilds = false }
    buildFeatures { compose = true; buildConfig = true }
    composeOptions { kotlinCompilerExtensionVersion = "1.5.14" }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17; isCoreLibraryDesugaringEnabled = true }
    kotlinOptions { jvmTarget = "17" }
    packaging { jniLibs { useLegacyPackaging = true } }
}
// The official welcome image must never change by accident: compare it with the stored SHA-256 fingerprint before every build.
val verifyWelcomeImage by tasks.registering {
    val img = file("src/main/res/drawable-nodpi/welcome_art.png")
    val expected = file("welcome_art.sha256").readText().trim().split(" ")[0]
    doLast {
        val actual = MessageDigest.getInstance("SHA-256").digest(img.readBytes()).joinToString("") { "%02x".format(it) }
        if (actual != expected) throw GradleException("STOP: the official welcome image (welcome_art.png) was changed or replaced. Restore your original image.")
    }
}
tasks.matching { it.name == "preBuild" }.configureEach { dependsOn(verifyWelcomeImage) }

gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.contains("Release") }) {
        if (System.getenv("KEYSTORE_PATH") == null) throw GradleException("Release build needs the signing keystore (see docs/DEPLOYMENT.md).")
        if (!apiUrl.startsWith("https://") || apiUrl.contains("example.invalid")) throw GradleException("Set API_BASE_URL to your real https:// address.")
    }
}
dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.06.00"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.activity:activity-compose:1.9.1")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.4")
    implementation("com.wireguard.android:tunnel:1.0.20230706")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
