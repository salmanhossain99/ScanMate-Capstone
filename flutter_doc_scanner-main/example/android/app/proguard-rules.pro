# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.

# Keep Google MediaPipe classes (used by flutter_gemma)
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# Keep Google Protobuf classes (used by flutter_gemma)
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# Keep annotation processing classes
-keep class javax.lang.model.** { *; }
-dontwarn javax.lang.model.**

# Keep SSL/TLS platform classes
-keep class org.bouncycastle.** { *; }
-keep class org.conscrypt.** { *; }
-keep class org.openjsse.** { *; }
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**

# Keep AutoValue classes
-keep class com.google.auto.value.** { *; }
-dontwarn com.google.auto.value.**

# Keep all classes referenced by flutter_gemma
-keep class dev.flutterberlin.flutter_gemma.** { *; }
-dontwarn dev.flutterberlin.flutter_gemma.**

# Keep Google Play Core classes (for Flutter Play Store features)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Keep Google ML Kit Text Recognition classes
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.vision.text.chinese.** { *; }
-keep class com.google.mlkit.vision.text.devanagari.** { *; }
-keep class com.google.mlkit.vision.text.japanese.** { *; }
-keep class com.google.mlkit.vision.text.korean.** { *; }
-dontwarn com.google.mlkit.vision.text.**

# Keep Google ML Kit common classes
-keep class com.google.mlkit.common.** { *; }
-dontwarn com.google.mlkit.common.**

# General Flutter rules
-keep class io.flutter.** { *; }
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**