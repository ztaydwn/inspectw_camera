############################################
# media_store_plus / Gson / Flutter Android
############################################

# Mantener Gson (el plugin lo usa por reflexión)
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**

# Mantener anotaciones y firmas genéricas
-keepattributes Signature
-keepattributes *Annotation*

# (Opcional) Evitar advertencias comunes
-dontwarn sun.misc.Unsafe
-keep class sun.misc.Unsafe { *; }

# Asegurar clases del canal de plataforma no se podan
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }

# Si conoces el paquete Java del plugin, puedes ser más específico:
# -keep class **.mediastore** { *; }
