# Infyter

Infyter es una aplicación móvil local para registrar entrenamientos, rutinas,
progreso y recuperación sin cuentas, publicidad, analítica ni dependencia de un
servidor.

## Funciones principales

- Registro de ejercicios, series, repeticiones, peso, RPE y RIR.
- Rutinas, sesiones activas y seguimiento del progreso.
- Catálogo de ejercicios y mapa corporal.
- Perfil, medidas, notas, logros y estadísticas.
- Temporizadores, recordatorios y widgets de inicio.
- Importación, exportación y copias de seguridad locales.
- Interfaz en español y soporte para varios idiomas.
- Aplicación Android e iOS construida con Flutter.

## Desarrollo local

Requiere Flutter 3.41 o posterior y Dart 3.11 o posterior.

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Para generar un APK de Android:

```bash
flutter build apk
```

El APK resultante se genera dentro de `build/app/outputs/flutter-apk/` y no se
versiona en el repositorio.

## Estructura

```text
lib/       aplicación Flutter
assets/    iconos, ilustraciones, audio, fuentes y shaders
android/   proyecto nativo de Android
ios/       proyecto nativo de iOS
test/      pruebas automatizadas
docs/      documentación y recursos de distribución
```

## Privacidad

Infyter guarda los datos de entrenamiento en el dispositivo. Consultá
[`PRIVACY.md`](PRIVACY.md) para conocer el alcance completo.

## Licencia y procedencia

Infyter es una modificación de GymMane y se distribuye bajo GNU GPL v3.
La atribución, las modificaciones materiales y las licencias de recursos se
detallan en [`NOTICE.md`](NOTICE.md), [`MODIFICATIONS.md`](MODIFICATIONS.md),
[`CREDITS.md`](CREDITS.md) y [`LICENSE`](LICENSE).
