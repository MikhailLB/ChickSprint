# Flutter runtime
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Play Core (deferred components loader still expected by Flutter)
-dontwarn com.google.android.play.core.**

# Firebase / GMS
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# AppsFlyer SDK
-keep class com.appsflyer.** { *; }
-dontwarn com.appsflyer.**

# WebView
-keep class io.flutter.plugins.webviewflutter.** { *; }

# File picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# Preserve JNI native method names
-keepclasseswithmembernames class * {
    native <methods>;
}

# Parcelable
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# Strip verbose logging from release
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
