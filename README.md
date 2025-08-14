# InspectW Camera (Flutter)
Minimal app de cámara enfocada en fotos + descripciones, organización por **Proyecto/Ubicación**, exportación en ZIP con metadatos.

## Pasos rápidos
1) Crea el proyecto base:
```bash
flutter create inspectw_camera
```
2) Copia **lib/** y **pubspec.yaml** de este paquete sobre tu proyecto:
```bash
# Asumiendo que este paquete lo descargaste y descomprimiste
cp -r lib pubspec.yaml inspectw_camera/
```
3) Agrega permisos:
- **Android**: abre `android/app/src/main/AndroidManifest.xml` y añade dentro de `<manifest>`:
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
<!-- Para Android < 13 -->
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
```
Dentro de `<application>` asegúrate de tener un `provider` de FileProvider (si no existe aún):
```xml
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.fileprovider"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/file_paths" />
</provider>
```
Crea `android/app/src/main/res/xml/file_paths.xml` con:
```xml
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <external-path name="external" path="." />
    <cache-path name="cache" path="." />
    <files-path name="files" path="." />
</paths>
```

- **iOS**: en `ios/Runner/Info.plist` agrega:
```xml
<key>NSCameraUsageDescription</key>
<string>Necesitamos acceso a la cámara para tomar fotos de inspección.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Necesitamos guardar fotos en tu galería.</string>
```

4) Instala dependencias:
```bash
flutter pub get
```

5) Ejecuta:
```bash
flutter run
```

## Estructura de datos
- Carpeta de proyecto: almacenamiento interno de la app
  - `/projects/{proyecto}/{ubicacion}/IMG_*.jpg`
  - `/projects/{proyecto}/metadata.json` (lista de fotos con descripción, ubicación, timestamp)
  - `/projects/{proyecto}/descripciones.json` (sugerencias frecuentes)
- **Exportación**: genera `{proyecto}.zip` con toda la carpeta del proyecto y lo comparte con `share_plus`.

## Notas
- El guardado inicial es en el almacenamiento de la app para evitar problemas de permisos. Al **Exportar**, se crea el ZIP listo para copiar / enviar; opcionalmente se puede habilitar un “Espejo a DCIM/Pictures/InspectW” más adelante.
- UI minimal para: crear proyectos/ubicaciones, tomar fotos (flash, zoom, resolución, cambio de lente trasera), escribir descripción con sugerencias y editar luego.
