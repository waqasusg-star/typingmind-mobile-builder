// Source-rebuild reference for the reviewed native Android pipeline.
// The builder worker generates its own controlled Gradle configuration, so this file
// exists so the delivered SOURCE ZIP can be rebuilt locally:
//   ANDROID_HOME=<sdk> ./gradlew :app:assembleRelease :app:testReleaseUnitTest
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.waqas.qabchecklist"
    compileSdk = 35
    defaultConfig {
        applicationId = "com.waqas.qabchecklist"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildTypes { release { isMinifyEnabled = false } }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
