# Flutter WebRTC & WebRTC Native ProGuard Rules
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

-keep class com.cloudwebrtc.webrtc.** { *; }
-dontwarn com.cloudwebrtc.webrtc.**

# Preserve JNI methods for native hardware codecs (VideoToolbox / MediaCodec)
-keepclasseswithmembernames class * {
    native <methods>;
}
