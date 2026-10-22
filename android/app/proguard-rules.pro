# ============================================================================
#  proguard-rules.pro — audio_player_x64
# ============================================================================

# Keep Media3 native bridges (ExoPlayer extensions).
-keep class androidx.media3.** { *; }
-keepclassmembers class androidx.media3.** { *; }

# Keep media_kit / FFmpeg bindings (DSF / AMR fallback).
-keep class com.media.kit.** { *; }
-keep class media_kit.** { *; }

# Keep audiotags reflection (ID3 / Vorbis / FLAC tag readers).
-keep class com.example.audiotags.** { *; }
-keep class org.jaudiotagger.** { *; }

# Flutter / Riverpod reflection — Flutter ships its own rules.
-dontwarn io.flutter.embedding.**

# Kotlin metadata — keep for freezed/data class reflection.
-keepattributes *Annotation*, InnerClasses, Signature, EnclosingMethod
-keepclassmembers class **$$serializer { *; }

# Drift (SQLite ORM) — generated code is fine, but keep runtime reflection.
-keep class dev.gitlive.firebase.** { *; }
-keepclassmembers class * extends drift.runtime.DriftDatabase { *; }
-keep class drift.** { *; }

# on_audio_query uses MediaStore reflection.
-keep class com.lucifercbio.on_audio_query.** { *; }

# Don't obfuscate FlutterGeneratedPluginRegistrant
-keep class io.flutter.app.FlutterGeneratedPluginRegistrant { *; }
