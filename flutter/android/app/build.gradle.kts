import com.google.protobuf.gradle.*
import groovy.json.JsonSlurper
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.google.protobuf") version "0.9.4"
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { reader -> localProperties.load(reader) }
}

val flutterVersionCode = localProperties.getProperty("flutter.versionCode") ?: "1"
val flutterVersionName = localProperties.getProperty("flutter.versionName") ?: "2.0"
val needsFlutter324ApkCopyFallback = localProperties.getProperty("flutter.sdk")
    ?.let { File(it, "version") }
    ?.takeIf(File::isFile)
    ?.readText()
    ?.trim()
    ?.startsWith("3.24.") == true
val requiredLuodaAbis = System.getenv("LUODA_ANDROID_ABIS")
    ?.split(',')
    ?.map(String::trim)
    ?.filter(String::isNotEmpty)
    ?.takeIf(List<String>::isNotEmpty)
    ?: listOf("arm64-v8a", "armeabi-v7a")
val luodaJniLibsDir = file("src/main/jniLibs")

val verifyLuodaNativeLibraries by tasks.registering {
    group = "verification"
    description = "Verifies that every packaged Android ABI contains libluoda.so."
    val requiredLibraries = requiredLuodaAbis.map { abi ->
        luodaJniLibsDir.resolve("$abi/libluoda.so")
    }
    inputs.files(requiredLibraries)
    doLast {
        val missingLibraries = requiredLibraries.filter { library ->
            !library.isFile || library.length() == 0L
        }
        if (missingLibraries.isNotEmpty()) {
            throw GradleException(
                "Missing required LUODA native libraries:\n" +
                    missingLibraries.joinToString("\n") { " - ${it.absolutePath}" } +
                    "\nRun flutter/build_android.ps1 (Windows) or flutter/build_android.sh (Linux/macOS) before packaging."
            )
        }
    }
}

fun findRustlsPlatformVerifierMavenDir(): String? {
    try {
        val dependencyText = providers.exec {
            workingDir = File("../..")
            commandLine("cargo", "metadata", "--format-version", "1")
        }.standardOutput.asText.get()

        val dependencyJson = JsonSlurper().parseText(dependencyText) as Map<*, *>
        val packages = dependencyJson["packages"] as List<*>
        val pkg = packages.find { (it as Map<*, *>)["name"] == "rustls-platform-verifier-android" }

        @Suppress("UNCHECKED_CAST")
        val pkgMap = pkg as Map<String, Any>?
        if (pkgMap == null) return null

        val manifestPath = File(pkgMap["manifest_path"] as String)
        val mavenDir = File(manifestPath.parentFile, "maven")

        if (!mavenDir.exists()) return null

        println("Found rustls-platform-verifier maven repo at: ${mavenDir.path}")
        return mavenDir.path
    } catch (e: Exception) {
        println("Warning: Could not locate rustls-platform-verifier maven repo: ${e.message}")
        return null
    }
}

val rustlsMavenDir = findRustlsPlatformVerifierMavenDir()

repositories {
    if (rustlsMavenDir != null) {
        maven {
            url = uri(rustlsMavenDir)
            metadataSources {
                mavenPom()
                artifact()
            }
        }
    }
}

tasks.register<Copy>("copyProtoFiles") {
    from(file("../../../libs/hbb_common/protos"))
    into(file("src/main/proto"))
    include("*.proto")
}

protobuf {
    protoc {
        artifact = "com.google.protobuf:protoc:3.20.1"
    }
    generateProtoTasks {
        all().forEach { task ->
            task.dependsOn("copyProtoFiles")
            task.builtins {
                create("java") {
                    option("lite")
                }
            }
        }
    }
}

android {
    namespace = "com.luoda.remote"
    compileSdkVersion(35)

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
            jniLibs.srcDirs(luodaJniLibsDir)
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.luoda.remote"
        minSdkVersion(23)
        targetSdkVersion(33)
        versionCode = flutterVersionCode.toInt()
        versionName = flutterVersionName
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties["storeFile"] as? String
            val storeFileObj = storeFilePath?.let { project.file(it) }
            if (storeFileObj?.exists() == true) {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = storeFileObj
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            // 与官方 rustdesk 一致：release 始终用 signingConfigs.release（而非 debug 签名）
            // 如果 key.properties 不存在或 storeFile 不存在，则为 null 签名（装不上）。
            // 见官方：https://github.com/rustdesk/rustdesk/blob/master/flutter/android/app/build.gradle
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules"
            )
        }
    }
}

tasks.configureEach {
    if (name.startsWith("merge") && name.endsWith("NativeLibs")) {
        dependsOn(verifyLuodaNativeLibraries)
    }
}

if (needsFlutter324ApkCopyFallback) {
    gradle.projectsEvaluated {
        listOf("debug", "profile", "release").forEach { mode ->
            val variantName = mode.replaceFirstChar(Char::uppercaseChar)
            val assembleTask = tasks.findByName("assemble$variantName")
                ?: return@forEach
            assembleTask.actions.clear()
            assembleTask.doLast {
                val apkDir = layout.buildDirectory
                    .dir("outputs/apk/$mode")
                    .get()
                    .asFile
                val producedApks = apkDir
                    .listFiles { file -> file.isFile && file.name.endsWith(".apk") }
                    ?.toList()
                    ?: emptyList()
                // Flutter 3.24 的 --split-per-abi 产出 app-<abi>-release.apk 而非
                // universal app-release.apk；普通模式产出 app-release.apk。
                // 只要 outputs/apk/<mode>/ 下有任意 APK 即视为打包成功，
                // 全部拷贝到 outputs/flutter-apk/ 供 Flutter 工具收集。
                if (producedApks.isEmpty()) {
                    throw GradleException("Android packaging did not produce any APK in ${apkDir.absolutePath}")
                }
                project.copy {
                    from(producedApks)
                    into(layout.buildDirectory.dir("outputs/flutter-apk"))
                }
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.protobuf:protobuf-javalite:3.20.1")
    implementation("androidx.media:media:1.6.0")
    implementation("com.github.getActivity:XXPermissions:18.5")
    implementation("org.jetbrains.kotlin:kotlin-stdlib") {
        version { strictly("1.9.24") }
    }
    implementation("com.caverock:androidsvg-aar:1.4")
    implementation("rustls:rustls-platform-verifier:0.1.1")
    // FaceAISDK 宿主库：插件的 FaceSDKLib 是 compileOnly，运行时类必须由宿主提供
    implementation(files("libs/FaceSDKLib-release.aar"))
}
