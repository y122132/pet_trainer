# Flutter Wrapper (Keep entry points)
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# TFLite Flutter (Critical for Release Build)
-keep class org.tensorflow.lite.** { *; }
-keep class org.tensorflow.lite.flutter.** { *; }
-keep class org.tensorflow.lite.gpu.** { *; }
-keep class org.tensorflow.lite.nnapi.** { *; }
-keep class org.tensorflow.lite.support.** { *; }

# Suppress warnings for missing optional delegates
-dontwarn org.tensorflow.lite.**
-dontwarn com.google.android.gms.internal.**
-dontwarn java.lang.invoke.*

# Flutter Deferred Components / Play Core (Suppress missing optional deps)
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
