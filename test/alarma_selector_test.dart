// El selector de alarma de Ajustes (AlarmStore.importSound) copia el sonido nuevo antes de borrar el anterior
// (sesión 27, decisión 2c de Braian). Antes borraba primero: si la copia fallaba, la persona se quedaba sin su alarma.
// Fixtures en carpetas temporales.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/services/alarm_store.dart';

void main() {
  late Directory alarms;
  late Directory origen;

  setUp(() async {
    alarms = await Directory.systemTemp.createTemp('infyter_alarma');
    origen = await Directory.systemTemp.createTemp('infyter_alarma_origen');
    AlarmStore.directory = alarms.path;
  });

  tearDown(() async {
    AlarmStore.directory = null;
    for (final d in [alarms, origen]) {
      if (d.existsSync()) await d.delete(recursive: true);
    }
  });

  List<String> archivos() => [
    for (final f in alarms.listSync())
      if (f is File) f.uri.pathSegments.last,
  ]..sort();

  // La alarma propia que la persona ya tenía elegida.
  String alarmaActual() {
    File('${alarms.path}/alarm-1.mp3').writeAsBytesSync([7, 7, 7]);
    return 'alarm-1.mp3';
  }

  test('si no se puede copiar el sonido nuevo, la alarma anterior sigue', () async {
    final actual = alarmaActual();

    final nueva = await AlarmStore.importSound('${origen.path}/no-existe.mp3');

    expect(nueva, isNull);
    expect(archivos(), [actual]);
    expect(File('${alarms.path}/$actual').readAsBytesSync(), [7, 7, 7]);
  });

  test('si la copia sale bien, queda solo el sonido nuevo', () async {
    alarmaActual();
    final src = File('${origen.path}/campana.ogg')..writeAsBytesSync([1, 2, 3, 4]);

    final nueva = await AlarmStore.importSound(src.path);

    expect(nueva, isNotNull);
    expect(nueva, endsWith('.ogg'));
    expect(archivos(), [nueva]);
    expect(File(AlarmStore.pathFor(nueva)!).readAsBytesSync(), [1, 2, 3, 4]);
  });
}
