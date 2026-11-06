plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
    namespace = "com.waqas.hdrama"
    compileSdk = 35
    defaultConfig {
        applicationId = "com.waqas.hdramabrowser"
        minSdk = 26
        targetSdk = 35
        versionCode = 20
        versionName = "1.9.1"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    signingConfigs.getByName("debug") {
        // Environment overrides let an existing release key sign a compatible update instead of
        // forcing the Android default debug credentials.
        System.getenv("HDRAMA_BROWSER_DEBUG_KEYSTORE")?.takeIf { it.isNotBlank() }?.let { storeFile = file(it) }
        storePassword = System.getenv("HDRAMA_BROWSER_DEBUG_STORE_PASSWORD") ?: "android"
        keyAlias = System.getenv("HDRAMA_BROWSER_DEBUG_KEY_ALIAS") ?: "androiddebugkey"
        keyPassword = System.getenv("HDRAMA_BROWSER_DEBUG_KEY_PASSWORD") ?: "android"
    }
    buildTypes { release { isMinifyEnabled = false } }
    testOptions {
        unitTests.isIncludeAndroidResources = true
        unitTests.all { test ->
            test.systemProperty("robolectric.dependency.repo.url", "https://repo.maven.apache.org/maven2")
            listOf("https.proxyHost", "https.proxyPort", "http.proxyHost", "http.proxyPort", "javax.net.ssl.trustStore").forEach { key ->
                System.getProperty(key)?.let { test.systemProperty(key, it) }
            }
        }
    }
}
dependencies {
    implementation("androidx.activity:activity-ktx:1.10.1")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.webkit:webkit:1.12.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jsoup:jsoup:1.18.3")
    val media3 = "1.5.1"
    implementation("androidx.media3:media3-exoplayer:$media3")
    implementation("androidx.media3:media3-exoplayer-hls:$media3")
    implementation("androidx.media3:media3-exoplayer-dash:$media3")
    implementation("androidx.media3:media3-datasource-okhttp:$media3")
    implementation("androidx.media3:media3-ui:$media3")
    testImplementation("junit:junit:4.13.2")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
    testImplementation("org.robolectric:robolectric:4.14.1")
}
