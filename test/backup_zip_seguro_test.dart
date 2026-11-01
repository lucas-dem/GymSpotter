// Restaurar un backup ZIP no borra fotos, videos ni la alarma que no haya reemplazado con éxito (sesión 26).
// Antes, restoreBackupZip borraba todos los medios (MediaStore.clearAll) ANTES de aplicar el backup: si el backup
// fallaba, el estado volvía atrás pero los archivos ya no estaban. Todo con fixtures en carpetas temporales.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory media;
  late Directory alarms;
  final vieja = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1, 1, 1, 1]);
  final nueva = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 2, 2, 2, 2]);
  final bench = kExercises.firstWhere((e) => e.name == 'Barbell Bench Press');
  final squat = kExercises.firstWhere((e) => e.name == 'Barbell Front Squat');
  final pushUp = kExercises.firstWhere((e) => e.equipment == 'Bodyweight');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    media = await Directory.systemTemp.createTemp('infyter_zip_media');
    alarms = await Directory.systemTemp.createTemp('infyter_zip_alarm');
    MediaStore.directory = media.path;
    AlarmStore.directory = alarms.path;
    ProgressReminder.instance.enabled = false;
    TrainReminder.instance.enabled = false;
    fit.resetAllData();
  });

  tearDown(() async {
    MediaStore.directory = null;
    AlarmStore.directory = null;
    for (final d in [media, alarms]) {
      if (d.existsSync()) await d.delete(recursive: true);
    }
  });

  List<String> archivos(Directory d) => [
    for (final f in d.listSync())
      if (f is File) f.uri.pathSegments.last,
  ]..sort();

  // La foto que el usuario ya tenía antes de restaurar.
  Future<String> fotoVieja() async {
    final base = (await MediaStore.saveBytes(bench.id, 'png', vieja))!;
    fit.exerciseMedia[bench.id] = base;
    return base;
  }

  // Un backup ZIP de fixture: el JSON y los archivos que trae (ruta dentro del ZIP -> bytes).
  Uint8List zip(Map<String, dynamic> json, Map<String, Uint8List> files) {
    final archive = Archive();
    files.forEach((path, bytes) => archive.addFile(ArchiveFile.noCompress(path, bytes.length, bytes)));
    archive.addFile(ArchiveFile.string(kBackupJsonEntry, jsonEncode(json)));
    return ZipEncoder().encodeBytes(archive);
  }

  // La alarma que el usuario ya tenía elegida.
  Future<String> alarmaActual() async {
    final actual = (await AlarmStore.saveBytes('mia.mp3', Uint8List.fromList([7, 7, 7])))!;
    fit.setAlarmSound(actual, 'Mi alarma');
    return actual;
  }

  test('si el backup falla al aplicarse, no se borra ninguna foto y no quedan archivos nuevos', () async {
    final base = await fotoVieja();
    final alarma = await alarmaActual();
    final roto = zip(
      {
        'media': {squat.id: 'media/images/sentadilla.png'},
        'alarmSound': 'otra.mp3',
        'alarmSoundName': 'Otra',
        'sessions': [42], // applyBackup lo rechaza: una sesión que no es un objeto
      },
      {
        'media/images/sentadilla.png': nueva,
        'alarm/otra.mp3': Uint8List.fromList([5, 5]),
      },
    );

    bool? ok;
    Object? error;
    try {
      ok = await restoreBackupZip(roto);
    } catch (e) {
      error = e;
    }

    expect(error, isNull, reason: 'restoreBackupZip devuelve false, no lanza');
    expect(ok, isFalse);
    expect(archivos(media), [base], reason: 'la foto vieja sigue y la nueva no quedó');
    expect(await MediaStore.readBytes(base), vieja);
    expect(fit.exerciseMedia[bench.id], base);
    expect(archivos(alarms), [alarma], reason: 'la alarma actual sigue y la del backup no quedó');
    expect(fit.alarmSound, alarma);
  });

  test('si el backup sale bien, quedan solo los archivos del backup', () async {
    await fotoVieja();
    final bueno = zip(
      {
        'media': {squat.id: 'media/images/sentadilla.png'},
      },
      {'media/images/sentadilla.png': nueva},
    );

    expect(await restoreBackupZip(bueno), isTrue);

    final restaurada = fit.exerciseMedia[squat.id]!;
    expect(fit.exerciseMedia.containsKey(bench.id), isFalse);
    expect(archivos(media), [restaurada]);
    expect(await MediaStore.readBytes(restaurada), nueva);
  });

  test('si al backup le falta un archivo, no se borran las fotos que había', () async {
    final base = await fotoVieja();
    final incompleto = zip(
      {
        'media': {squat.id: 'media/images/sentadilla.png', pushUp.id: 'media/videos/no-esta.mp4'},
      },
      {'media/images/sentadilla.png': nueva},
    );

    expect(await restoreBackupZip(incompleto), isTrue);

    expect(archivos(media), containsAll([base, fit.exerciseMedia[squat.id]!]));
    expect(await MediaStore.readBytes(base), vieja);
  });

  test('la alarma actual no se borra si la del backup no se pudo restaurar', () async {
    final actual = await alarmaActual();
    final sinArchivo = zip({'alarmSound': 'otra.mp3', 'alarmSoundName': 'Otra'}, const {});

    expect(await restoreBackupZip(sinArchivo), isTrue);

    expect(fit.alarmSound, actual);
    expect(fit.alarmSoundName, 'Mi alarma');
    expect(archivos(alarms), [actual]);
  });

  test(
    'un backup sin alarma, o con un nombre de alarma que no es texto, no borra la alarma actual',
    () async {
      final actual = await alarmaActual();
      for (final json in <Map<String, dynamic>>[
        {},
        {'alarmSound': 5, 'alarmSoundName': 7},
      ]) {
        expect(await restoreBackupZip(zip(json, const {})), isTrue, reason: '$json');
        expect(fit.alarmSound, actual, reason: '$json');
        expect(fit.alarmSoundName, 'Mi alarma', reason: '$json');
        expect(archivos(alarms), [actual], reason: '$json');
      }
    },
  );

  test('cuando se borran los archivos anteriores, el estado restaurado ya está guardado', () async {
    await fotoVieja();
    final bueno = zip(
      {
        'media': {squat.id: 'media/images/sentadilla.png'},
      },
      {'media/images/sentadilla.png': nueva},
    );

    expect(await restoreBackupZip(bueno), isTrue);

    final prefs = await SharedPreferences.getInstance();
    final guardado = jsonDecode(prefs.getString('gymmane_v1')!) as Map<String, dynamic>;
    expect(
      (guardado['media'] as Map)[squat.id],
      fit.exerciseMedia[squat.id],
      reason: 'guardado sin esperar al guardado diferido de 400 ms',
    );
  });

  test('si la alarma del backup se restaura, reemplaza a la actual', () async {
    await alarmaActual();
    final conAlarma = zip(
      {'alarmSound': 'otra.mp3', 'alarmSoundName': 'Otra'},
      {
        'alarm/otra.mp3': Uint8List.fromList([5, 5]),
      },
    );

    expect(await restoreBackupZip(conAlarma), isTrue);

    final nueva = fit.alarmSound!;
    expect(fit.alarmSoundName, 'Otra');
    expect(archivos(alarms), [nueva]);
    expect(File(AlarmStore.pathFor(nueva)!).readAsBytesSync(), [5, 5]);
  });
}
