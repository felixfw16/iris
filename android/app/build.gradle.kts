import java.security.MessageDigest

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "id.sahabatnetra.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "id.sahabatnetra.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk { abiFilters += listOf("arm64-v8a") }
        externalNativeBuild { cmake { arguments += listOf("-DANDROID_STL=c++_shared") } }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
    externalNativeBuild { cmake { path = file("src/main/cpp/CMakeLists.txt"); version = "3.22.1" } }
    androidResources { noCompress += listOf("tflite", "onnx", "bin", "litertlm") }
    packaging { jniLibs { pickFirsts += "**/libc++_shared.so" } }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.camera:camera-camera2:1.4.2")
    implementation("androidx.camera:camera-lifecycle:1.4.2")
    implementation("androidx.camera:camera-view:1.4.2")
    implementation("androidx.fragment:fragment-ktx:1.8.6")
    implementation("com.google.mlkit:text-recognition:16.0.1")
    implementation("com.google.mlkit:face-detection:16.1.7")
    implementation("org.tensorflow:tensorflow-lite:2.16.1")
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.22.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.ai.edge.litertlm:litertlm-android:0.17.0")
    testImplementation("junit:junit:4.13.2")
}

val verifyModelAssets by tasks.registering {
    val modelDirectory = file("src/main/assets/models")
    inputs.dir(modelDirectory)
    doLast {
        val manifestFile = modelDirectory.resolve("manifest.json")
        check(manifestFile.isFile) { "Run scripts/prepare_models.py before building the complete APK." }
        @Suppress("UNCHECKED_CAST")
        val manifest = groovy.json.JsonSlurper().parse(manifestFile) as Map<String, Map<String, Any>>
        for (id in listOf("objects", "objectLabels", "face", "speech", "depth", "qwen")) {
            val entry = checkNotNull(manifest[id]) { "Missing model manifest entry: $id" }
            val modelFile = modelDirectory.resolve(entry["file"] as String)
            check(modelFile.isFile) { "Missing model asset: $id" }
            val digest = MessageDigest.getInstance("SHA-256")
            modelFile.inputStream().use { stream ->
                val buffer = ByteArray(65536)
                while (true) { val read = stream.read(buffer); if (read < 0) break; digest.update(buffer, 0, read) }
            }
            val actual = digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
            check(actual == entry["sha256"]) { "Corrupted model asset: $id" }
        }
    }
}
tasks.matching { it.name == "preReleaseBuild" }.configureEach { dependsOn(verifyModelAssets) }
