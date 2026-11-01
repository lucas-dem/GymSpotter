// Restaurar un backup ZIP cuando no se puede guardar el estado restaurado (sesión 27, decisión 2b de Braian).
// En Android, SharedPreferences escribe con commit(): si el disco está lleno devuelve false y lo guardado sigue siendo
// lo anterior. Antes, Store.save se tragaba ese false y la restauración borraba igual las fotos y la alarma anteriores,
// que son justo las que usa lo guardado. Ahora se vuelve todo atrás: el estado anterior en memoria, sus archivos y su
// alarma; los archivos nuevos se borran y restoreBackupZip devuelve false. Fixtures en carpetas temporales.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/catalog/exercise_catalog.dart';
import 'package:infyter/services/alarm_store.dart';
import 'package:infyter/services/backup_zip.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/services/media_store.dart';
import 'package:infyter/services/progress_reminder.dart';
import 'package:infyter/services/train_reminder.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
// La interfaz de plataforma de shared_preferences (dependencia transitiva) permite simular el disco lleno.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const kBlob = 'flutter.gymmane_v1';

/// El disco: guarda todo menos el blob principal, que falla como commit() sin espacio ([lanza] = con excepción).
class _DiscoLleno extends InMemorySharedPreferencesStore {
  _DiscoLleno(super.data, {this.lanza = false}) : super.withData();

  final bool lanza;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key != kBlob) return super.setValue(valueType, key, value);
    if (lanza) throw PlatformException(code: 'disk-full');
    return false;
  }
}

/// Un disco que falla a ratos: la primera escritura del blob tarda más que los 400 ms de un guardado diferido y falla,
/// la segunda sale bien y las demás fallan.
class _DiscoIntermitente extends InMemorySharedPreferencesStore {
  _DiscoIntermitente(super.data) : super.withData();

  var _escrituras = 0;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key != kBlob) return super.setValue(valueType, key, value);
    switch (++_escrituras) {
      case 1:
        await Future<void>.delayed(const Duration(milliseconds: 700));
        return false;
      case 2:
        return super.setValue(valueType, key, value);
      default:
        return false;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory media;
  late Directory alarms;
  final vieja = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 1, 1, 1]);
  final nueva = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 2, 2, 2, 2]);
  final bench = kExercises.firstWhere((e) => e.name == 'Barbell Bench Press');
  final squat = kExercises.firstWhere((e) => e.name == 'Barbell Front Squat');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Store.instance.debugReset();
    await Store.instance.init();
    media = await Directory.systemTemp.createTemp('infyter_zip_guardado_media');
    alarms = await Directory.systemTemp.createTemp('infyter_zip_guardado_alarm');
    MediaStore.directory = media.path;
    AlarmStore.directory = alarms.path;
    ProgressReminder.instance.enabled = false;
    TrainReminder.instance.enabled = false;
    fit.resetAllData();
  });

  tearDown(() async {
    MediaStore.directory = null;
    AlarmStore.directory = null;
    SharedPreferences.setMockInitialValues({});
    for (final d in [media, alarms]) {
      if (d.existsSync()) await d.delete(recursive: true);
    }
  });

  List<String> archivos(Directory d) => [
    for (final f in d.listSync())
      if (f is File) f.uri.pathSegments.last,
  ]..sort();

  Uint8List zip(Map<String, dynamic> json, Map<String, Uint8List> files) {
    final archive = Archive();
    files.forEach((path, bytes) => archive.addFile(ArchiveFile.noCompress(path, bytes.length, bytes)));
    archive.addFile(ArchiveFile.string(kBackupJsonEntry, jsonEncode(json)));
    return ZipEncoder().encodeBytes(archive);
  }

  // Lo que la persona tenía antes de restaurar, ya guardado en disco: una foto, una alarma y una rutina.
  Future<({String foto, String alarma})> estadoAnterior() async {
    final foto = (await MediaStore.saveBytes(bench.id, 'png', vieja))!;
    fit.exerciseMedia[bench.id] = foto;
    final alarma = (await AlarmStore.saveBytes('mia.mp3', Uint8List.fromList([7, 7, 7])))!;
    fit.setAlarmSound(alarma, 'Mi alarma');
    fit.createRoutine('Empuje');
    fit.persistNow();
    await pumpEventQueue();
    return (foto: foto, alarma: alarma);
  }

  // A partir de acá el disco no acepta el blob principal.
  Future<void> llenarDisco({bool lanza = false}) async {
    final disco = await SharedPreferencesStorePlatform.instance.getAll();
    SharedPreferencesStorePlatform.instance = _DiscoLleno(disco, lanza: lanza);
  }

  Future<String?> blobEnDisco() async =>
      (await SharedPreferencesStorePlatform.instance.getAll())[kBlob] as String?;

  final completo = zip(
    {
      'media': {squat.id: 'media/images/sentadilla.png'},
      'alarmSound': 'otra.mp3',
      'alarmSoundName': 'Otra',
      'routines': [
        {
          'id': 'r9',
          'n': 'Pierna',
          'ex': [squat.id],
        },
      ],
    },
    {
      'media/images/sentadilla.png': nueva,
      'alarm/otra.mp3': Uint8List.fromList([5, 5]),
    },
  );

  test('Store.save avisa si no se pudo guardar', () async {
    await llenarDisco();
    expect(await Store.instance.save({'units': 'kg'}), isFalse);
    await llenarDisco(lanza: true);
    expect(await Store.instance.save({'units': 'kg'}), isFalse);
    SharedPreferences.setMockInitialValues({});
    Store.instance.debugReset();
    await Store.instance.init();
    expect(await Store.instance.save({'units': 'kg'}), isTrue);
  });

  for (final lanza in [false, true]) {
    final como = lanza ? 'con una excepción' : 'devolviendo false';
    test('si guardar falla ($como), no se borra nada de lo anterior y todo vuelve atrás', () async {
      final antes = await estadoAnterior();
      final blobAntes = await blobEnDisco();
      await llenarDisco(lanza: lanza);

      expect(await restoreBackupZip(completo), isFalse, reason: 'lo restaurado no quedó guardado');

      expect(archivos(media), [antes.foto], reason: 'la foto anterior sigue y la nueva no quedó');
      expect(await MediaStore.readBytes(antes.foto), vieja);
      expect(archivos(alarms), [antes.alarma], reason: 'la alarma anterior sigue y la nueva no quedó');
      expect(fit.exerciseMedia, {bench.id: antes.foto}, reason: 'en memoria, el estado de antes');
      expect(fit.alarmSound, antes.alarma);
      expect(fit.alarmSoundName, 'Mi alarma');
      expect(fit.routines.map((r) => r.name), ['Empuje']);
      expect(await blobEnDisco(), blobAntes, reason: 'en disco sigue lo de antes, que usa esos archivos');
    });
  }

  test('si guardar falla, el aviso de rescate que había sigue', () async {
    // Datos ilegibles al abrir: el inicio avisa que se guardó una copia (sesión 27, tema a).
    SharedPreferences.setMockInitialValues({'gymmane_v1': '{roto'});
    Store.instance.debugReset();
    await Store.instance.init();
    fit.loadFromStore();
    final aviso = fit.rescueSaved;
    expect(aviso, isNotNull);
    await estadoAnterior();
    await llenarDisco();

    expect(await restoreBackupZip(completo), isFalse);

    expect(fit.rescueSaved, aviso, reason: 'el backup no quedó: el aviso no se da por cerrado');
    expect(Store.instance.rescue!.handled, isNull);
  });

  test('si guardar falla, un entrenamiento abierto sigue abierto', () async {
    await estadoAnterior();
    fit.sessionPicks
      ..clear()
      ..add(squat.id);
    fit.startSession();
    expect(fit.session, isNotNull);
    await llenarDisco();

    expect(await restoreBackupZip(completo), isFalse);

    expect(fit.session, isNotNull);
  });

  test('si guardar falla, los widgets de la pantalla de inicio vuelven a lo de antes', () async {
    await estadoAnterior();
    final vistas = <List<String>>[];
    fit.onWidgetsShouldUpdate = () => vistas.add([for (final r in fit.routines) r.name]);
    addTearDown(() => fit.onWidgetsShouldUpdate = null);
    await llenarDisco();

    expect(await restoreBackupZip(completo), isFalse);

    expect(vistas, isNotEmpty);
    expect(vistas.last, [
      'Empuje',
    ], reason: 'la última actualización de los widgets es con el estado de antes');
  });

  test('si guardar falla, un guardado diferido no deja en disco lo que no se pudo guardar', () async {
    final antes = await estadoAnterior();
    final disco = await SharedPreferencesStorePlatform.instance.getAll();
    SharedPreferencesStorePlatform.instance = _DiscoIntermitente(disco);

    expect(await restoreBackupZip(completo), isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 600));

    final guardado = jsonDecode((await blobEnDisco())!) as Map<String, dynamic>;
    expect([for (final r in guardado['routines'] as List) (r as Map)['n']], ['Empuje']);
    expect(guardado['alarmSound'], antes.alarma, reason: 'lo guardado usa los archivos de antes, que siguen');
  });

  test('si se restaura bien, el aviso de rescate se cierra y la pantalla se entera', () async {
    SharedPreferences.setMockInitialValues({'gymmane_v1': '{roto'});
    Store.instance.debugReset();
    await Store.instance.init();
    fit.loadFromStore();
    expect(fit.rescueSaved, isNotNull);
    await estadoAnterior();
    final avisos = <String?>[];
    void escuchar() => avisos.add(fit.rescueSaved);
    fit.addListener(escuchar);
    addTearDown(() => fit.removeListener(escuchar));

    expect(await restoreBackupZip(completo), isTrue);

    expect(fit.rescueSaved, isNull);
    expect(Store.instance.rescue!.handled, isNotNull);
    expect(avisos, isNotEmpty);
    expect(avisos.last, isNull, reason: 'la última notificación ya es sin aviso: el inicio lo saca');
  });

  test('guardia: con el disco bien, la misma restauración reemplaza todo', () async {
    final antes = await estadoAnterior();

    expect(await restoreBackupZip(completo), isTrue);

    expect(fit.routines.map((r) => r.name), ['Pierna']);
    expect(archivos(media), [fit.exerciseMedia[squat.id]!]);
    expect(archivos(alarms), [fit.alarmSound!]);
    expect(archivos(alarms), isNot(contains(antes.alarma)));
  });
}
