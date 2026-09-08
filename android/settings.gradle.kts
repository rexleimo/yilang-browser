pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // 国内镜像仅本地构建使用（CI=null 时生效）。GitHub Actions 上必须直连
        // 官方仓库：阿里云镜像对部分插件工件（如 google-services 4.4.2 的 marker）
        // 返回 502，Gradle 遇 5xx 直接中止且不降级到下一仓库——v0.2.1 起 CI
        // 构建全挂的根因。本地有 ~/.gradle 缓存 + init.gradle，行为不变。
        if (System.getenv("CI") == null) {
            maven { url = uri("https://maven.aliyun.com/repository/google") }
            maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
            maven { url = uri("https://maven.aliyun.com/repository/central") }
        }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        if (System.getenv("CI") == null) {
            maven { url = uri("https://maven.aliyun.com/repository/google") }
            maven { url = uri("https://maven.aliyun.com/repository/central") }
            maven { url = uri("https://maven.aliyun.com/repository/public") }
            maven { url = uri("https://storage.flutter-io.cn/download.flutter.io") }
        } else {
            // Flutter 引擎工件（io.flutter:*_release）只发布在 Flutter 官方
            // maven 仓库，google()/mavenCentral() 上没有；CI 必须显式声明。
            maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
        }
        google()
        mavenCentral()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
