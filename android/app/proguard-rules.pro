# ML Kit resolves components reflectively. AGP 9 full-mode R8 can otherwise
# remove SharedPrefManager/registrars, making release-only scanner startup fail.
# Scoped workaround; do not disable shrinking for the rest of the application.
# https://github.com/googlesamples/mlkit/issues/1018
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_document_scanner.** { *; }
