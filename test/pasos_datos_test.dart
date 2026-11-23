// Los blobs de 1.3.2 son los que la app escribió en el emulador en la sesión 32 (datos inventados).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/services/backup_zip.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/services/media_store.dart';
import 'package:infyter/services/progress_reminder.dart';
import 'package:infyter/services/step_source.dart';
import 'package:infyter/services/store_migrations.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
// La interfaz de plataforma de shared_preferences (dependencia transitiva) permite simular el disco lleno.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const kKey = 'gymmane_v1';

/// Guarda todo menos el blob principal, como commit() sin espacio.
class _DiscoLleno extends InMemorySharedPreferencesStore {
  _DiscoLleno(super.data) : super.withData();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key != 'flutter.$kKey') return super.setValue(valueType, key, value);
    return false;
  }
}

Future<void> _llenarDisco() async {
  SharedPreferencesStorePlatform.instance = _DiscoLleno(await SharedPreferencesStorePlatform.instance.getAll());
}

/// Una lectura de días que la fuente retiene hasta liberar [FakeStepSource.readGate].
const _diaRetenido = StepDayReading('2026-11-21', 9999);

const String kBlobInicio132 = r'''
{"profile":{"name":"Atleta","sex":"male","age":28,"h":175.0,"w":75.0,"act":1.55,"goal":4,"badge":"blue"},"dark":true,"theme":"dark","units":"kg","language":"es","rest":90,"alarmSound":null,"alarmSoundName":null,"bg":"dynamic","gymBranch":"junin","heatTone":"ember","bgDim":0.55,"showFocus":true,"autoAdvance":true,"keepAwake":true,"countdown":false,"gamify":true,"rpe":false,"effort":"rpe","demo":"large","alarmStyle":"quiet","noSuggest":[],"exMode":{},"trainAt":null,"trainSmart":false,"trainerMode":false,"alarmAskedAt":null,"onboarded":true,"favorites":{},"notes":[],"places":[],"place":"","checkins":[],"routines":[{"id":"r1795055573049771-0","n":"Pecho y espalda pesado","ex":["EIeI8Vf","SpYC0Kp","3TZduzM","ns0SIbU"]}],"weeklyPlan":{},"athletes":[],"athleteWeeklyPlans":{},"custom":[],"media":{},"exRest":{},"progress":{},"warmup":[],"repsOnly":[],"repsOnlyOff":[],"sessions":[{"d":"2026-11-17T23:32:53.042369","dur":3725,"ex":[{"id":"EIeI8Vf","n":"Barbell Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]},{"id":"SpYC0Kp","n":"Dumbbell Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]},{"id":"3TZduzM","n":"Barbell Incline Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]}]},{"d":"2026-11-15T23:32:53.042369","dur":3725,"ex":[{"id":"EIeI8Vf","n":"Barbell Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]},{"id":"SpYC0Kp","n":"Dumbbell Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]},{"id":"3TZduzM","n":"Barbell Incline Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]}]},{"d":"2026-11-13T23:32:53.042369","dur":3725,"ex":[{"id":"EIeI8Vf","n":"Barbell Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]},{"id":"SpYC0Kp","n":"Dumbbell Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]},{"id":"3TZduzM","n":"Barbell Incline Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]}]},{"d":"2026-11-11T23:32:53.042369","dur":3725,"ex":[{"id":"EIeI8Vf","n":"Barbell Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]},{"id":"SpYC0Kp","n":"Dumbbell Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]},{"id":"3TZduzM","n":"Barbell Incline Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]}]},{"d":"2026-11-09T23:32:53.042369","dur":3725,"ex":[{"id":"EIeI8Vf","n":"Barbell Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]},{"id":"SpYC0Kp","n":"Dumbbell Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]},{"id":"3TZduzM","n":"Barbell Incline Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]}]}],"bodyweight":[],"measures":[],"shots":[],"awards":{"firstStep":"2026-11-18T23:32:53.051772","firstWorkout":"2026-11-18T23:32:53.051772","firstRoutine":"2026-11-18T23:32:53.051772","firstRecord":"2026-11-18T23:32:53.052770","tonne1":"2026-11-18T23:32:53.054912","tonnes10":"2026-11-18T23:32:53.055428"},"awardsSeen":["firstStep","firstWorkout","firstRoutine","firstRecord","tonne1","tonnes10"],"moments":[],"photoEvery":30,"bodyTl":false}
''';

const String kBlobEntreno132 = r'''
{"profile":{"name":"Atleta","sex":"male","age":28,"h":175.0,"w":75.0,"act":1.55,"goal":4,"badge":"blue"},"dark":true,"theme":"dark","units":"kg","language":"es","rest":90,"alarmSound":null,"alarmSoundName":null,"bg":"dynamic","gymBranch":"junin","heatTone":"ember","bgDim":0.55,"showFocus":true,"autoAdvance":true,"keepAwake":true,"countdown":false,"gamify":true,"rpe":false,"effort":"rpe","demo":"large","alarmStyle":"quiet","noSuggest":[],"exMode":{},"trainAt":null,"trainSmart":false,"trainerMode":false,"alarmAskedAt":null,"onboarded":true,"favorites":{},"notes":[],"places":[],"place":"","checkins":[],"routines":[{"id":"r1795055573079621-1","n":"Pecho y espalda pesado","ex":["EIeI8Vf","SpYC0Kp","3TZduzM","ns0SIbU"]}],"weeklyPlan":{},"athletes":[],"athleteWeeklyPlans":{},"custom":[],"media":{},"exRest":{},"progress":{},"warmup":[],"repsOnly":[],"repsOnlyOff":[],"sessions":[{"d":"2026-11-17T23:32:53.078109","dur":3725,"ex":[{"id":"EIeI8Vf","n":"Barbell Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]},{"id":"SpYC0Kp","n":"Dumbbell Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]},{"id":"3TZduzM","n":"Barbell Incline Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]}]},{"d":"2026-11-15T23:32:53.078109","dur":3725,"ex":[{"id":"EIeI8Vf","n":"Barbell Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]},{"id":"SpYC0Kp","n":"Dumbbell Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]},{"id":"3TZduzM","n":"Barbell Incline Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]}]},{"d":"2026-11-13T23:32:53.078109","dur":3725,"ex":[{"id":"EIeI8Vf","n":"Barbell Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]},{"id":"SpYC0Kp","n":"Dumbbell Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]},{"id":"3TZduzM","n":"Barbell Incline Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]}]},{"d":"2026-11-11T23:32:53.078109","dur":3725,"ex":[{"id":"EIeI8Vf","n":"Barbell Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]},{"id":"SpYC0Kp","n":"Dumbbell Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]},{"id":"3TZduzM","n":"Barbell Incline Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]}]},{"d":"2026-11-09T23:32:53.078109","dur":3725,"ex":[{"id":"EIeI8Vf","n":"Barbell Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]},{"id":"SpYC0Kp","n":"Dumbbell Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]},{"id":"3TZduzM","n":"Barbell Incline Bench Press","p":"chest","s":[{"r":10,"w":100.0},{"r":8,"w":102.5}]}]}],"bodyweight":[],"measures":[],"shots":[],"awards":{"firstStep":"2026-11-18T23:32:53.051772","firstWorkout":"2026-11-18T23:32:53.051772","firstRoutine":"2026-11-18T23:32:53.051772","firstRecord":"2026-11-18T23:32:53.052770","tonne1":"2026-11-18T23:32:53.054912","tonnes10":"2026-11-18T23:32:53.055428"},"awardsSeen":["firstStep","firstWorkout","firstRoutine","firstRecord","tonne1","tonnes10"],"moments":[],"photoEvery":30,"bodyTl":false,"live":{"ex":[{"id":"EIeI8Vf","n":"Barbell Bench Press","p":"chest","s":[{"r":12,"w":102.5,"d":false},{"r":10,"w":105.0,"d":false},{"r":10,"w":105.0,"d":false}]},{"id":"SpYC0Kp","n":"Dumbbell Bench Press","p":"chest","s":[{"r":10,"w":100.0,"d":false},{"r":8,"w":102.5,"d":false},{"r":8,"w":102.5,"d":false}]},{"id":"3TZduzM","n":"Barbell Incline Bench Press","p":"chest","s":[{"r":10,"w":100.0,"d":false},{"r":8,"w":102.5,"d":false},{"r":8,"w":102.5,"d":false}]},{"id":"ns0SIbU","n":"Dumbbell Incline Bench Press","p":"chest","s":[{"r":10,"w":20.0,"d":false},{"r":10,"w":20.0,"d":false},{"r":10,"w":20.0,"d":false}]}],"i":0,"c":false,"at":null,"sv":null,"ss":null,"sd":null},"liveStart":"2026-11-18T23:32:53.085393","liveElapsed":0,"livePaused":false}
''';

const Map<String, Object?> kNuevasPorDefecto = {
  'steps': <String, Object?>{},
  'stepsFrom': <String, Object?>{},
  'stepGoal': 8000,
  'stepsOn': false,
  'stepsAskedAt': null,
};

Map<String, dynamic> _json(String raw) => jsonDecode(raw) as Map<String, dynamic>;

/// Diferencias entre dos JSON; una clave que solo está en [b] se marca "apareció".
List<String> _diff(Object? a, Object? b, [String path = r'$']) {
  if (a is Map && b is Map) {
    return [
      for (final k in {...a.keys, ...b.keys})
        if (!b.containsKey(k))
          '$path.$k: se perdió'
        else if (!a.containsKey(k))
          '$path.$k: apareció'
        else
          ..._diff(a[k], b[k], '$path.$k'),
    ];
  }
  if (a is List && b is List) {
    return [
      if (a.length != b.length) '$path: largo ${a.length} -> ${b.length}',
      for (var i = 0; i < math.min(a.length, b.length); i++) ..._diff(a[i], b[i], '$path[$i]'),
    ];
  }
  return a == b ? const [] : ['$path: ${jsonEncode(a)} -> ${jsonEncode(b)}'];
}

Uint8List _zipCon(Map<String, dynamic> data) {
  final archive = Archive()..addFile(ArchiveFile.string(kBackupJsonEntry, jsonEncode(data)));
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

Map<String, dynamic> _jsonDelZip(Uint8List zip) {
  final entry = ZipDecoder().decodeBytes(zip).findFile(kBackupJsonEntry)!;
  return jsonDecode(utf8.decode(entry.readBytes()!)) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late SharedPreferences prefs;

  Future<void> abrir(String raw) async {
    fit.saveAndExit();
    SharedPreferences.setMockInitialValues({kKey: raw});
    Store.instance.debugReset();
    await Store.instance.init();
    prefs = await SharedPreferences.getInstance();
    fit.loadFromStore();
  }

  Map<String, dynamic> guardado() {
    fit.persistNow();
    return _json(prefs.getString(kKey)!);
  }

  void conPasos() {
    fit.steps
      ..clear()
      ..addAll({'2026-11-19': 6412, '2026-11-20': 1200});
    fit.stepsFrom
      ..clear()
      ..addAll({'2026-11-20': 872});
    fit.stepGoal = 10000;
    fit.stepsOn = true;
    fit.stepsAskedAt = 1763600000000;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('infyter_pasos');
    Store.rescueDirectory = '${tmp.path}/data_rescue';
    MediaStore.directory = '${tmp.path}/media';
    ProgressReminder.instance.enabled = false;
    SharedPreferences.setMockInitialValues({});
    Store.instance.debugReset();
    await Store.instance.init();
    prefs = await SharedPreferences.getInstance();
    fit.resetAllData();
  });

  tearDown(() async {
    fit.saveAndExit();
    Store.instance.debugReset();
    Store.rescueDirectory = null;
    MediaStore.directory = null;
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('la versión de formato sigue en 1', () {
    expect(kStoreSchemaVersion, 1);
  });

  group('blob de 1.3.2', () {
    for (final (nombre, raw) in [('inicio', kBlobInicio132), ('entreno en curso', kBlobEntreno132)]) {
      test('$nombre: carga sin cambiar los datos viejos y vuelve con las claves nuevas por defecto', () async {
        await abrir(raw);

        expect(fit.steps, isEmpty);
        expect(fit.stepsFrom, isEmpty);
        expect(fit.stepGoal, 8000);
        expect(fit.stepsOn, isFalse);
        expect(fit.stepsAskedAt, isNull);
        expect(Store.instance.rescue, isNull, reason: 'no se salteó nada');

        final antes = _json(raw);
        final despues = guardado()..remove(kSchemaVersionKey);
        for (final entry in kNuevasPorDefecto.entries) {
          expect(despues, containsPair(entry.key, entry.value));
        }
        final cambios = _diff(antes, despues);
        expect(
          cambios,
          unorderedEquals([
            for (final k in kNuevasPorDefecto.keys) '\$.$k: apareció',
            r'$.profile.since: apareció',
          ]),
        );
      });
    }

    test('la segunda carga del blob ya guardado da exactamente lo mismo', () async {
      await abrir(kBlobInicio132);
      final primera = guardado();
      await abrir(jsonEncode(primera));
      expect(guardado(), primera);
    });
  });

  group('carga tolerante', () {
    test('lee las claves nuevas', () async {
      await abrir(
        jsonEncode({
          ..._json(kBlobInicio132),
          'steps': {'2026-11-19': 6412, '2026-11-20': 1200},
          'stepsFrom': {'2026-11-20': 872},
          'stepGoal': 10000,
          'stepsOn': true,
          'stepsAskedAt': 1763600000000,
        }),
      );

      expect(fit.steps, {'2026-11-19': 6412, '2026-11-20': 1200});
      expect(fit.stepsFrom, {'2026-11-20': 872});
      expect(fit.stepGoal, 10000);
      expect(fit.stepsOn, isTrue);
      expect(fit.stepsAskedAt, 1763600000000);
      expect(fit.sessions, hasLength(5));
      expect(Store.instance.rescue, isNull);
    });

    test('una entrada ilegible se saltea y el resto se carga', () async {
      await abrir(
        jsonEncode({
          ..._json(kBlobInicio132),
          'steps': {'2026-11-18': 300, '2026-11-19': 'muchos', 'ayer': 50, '2026-11-20': -4},
          'stepsFrom': {'2026-11-20': 'tarde', '2026-11-18': 600},
        }),
      );

      expect(fit.steps, {'2026-11-18': 300});
      expect(fit.stepsFrom, {'2026-11-18': 600});
      expect(fit.sessions, hasLength(5));
      expect(Store.instance.rescue!.reason, 'itemsSkipped', reason: 'el original queda en una copia');
    });

    test('una meta con otro tipo vuelve a 8000 y una fuera de rango queda en el rango, de a 500', () async {
      final base = _json(kBlobInicio132);
      await abrir(jsonEncode({...base, 'stepGoal': 'mucho', 'stepsOn': 'sí'}));
      expect(fit.stepGoal, 8000);
      expect(fit.stepsOn, isFalse);

      await abrir(jsonEncode({...base, 'stepGoal': 50000}));
      expect(fit.stepGoal, 30000);
      await abrir(jsonEncode({...base, 'stepGoal': 200}));
      expect(fit.stepGoal, 1000);
      await abrir(jsonEncode({...base, 'stepGoal': 12345}));
      expect(fit.stepGoal, 12500);
    });

    test('stepsAskedAt queda guardado en el teléfono', () async {
      await abrir(kBlobInicio132);
      fit.stepsAskedAt = 1763600000000;
      expect(guardado()['stepsAskedAt'], 1763600000000);
    });
  });

  group('carga estricta (restaurar una copia)', () {
    test('lee las claves nuevas y no toca stepsAskedAt, que es de este teléfono', () async {
      await abrir(kBlobInicio132);
      fit.stepsAskedAt = 1700000000000;

      fit.applyBackup({
        ..._json(kBlobInicio132),
        'steps': {'2026-11-19': 6412},
        'stepsFrom': {'2026-11-19': 540},
        'stepGoal': 9500,
        'stepsOn': true,
        'stepsAskedAt': 1763600000000,
      });

      expect(fit.steps, {'2026-11-19': 6412});
      expect(fit.stepsFrom, {'2026-11-19': 540});
      expect(fit.stepGoal, 9500);
      expect(fit.stepsOn, isTrue);
      expect(fit.stepsAskedAt, 1700000000000);
    });

    test('una entrada ilegible rechaza la copia y no cambia nada', () async {
      await abrir(kBlobInicio132);
      conPasos();
      final antes = fit.backupSnapshot();

      expect(
        () => fit.applyBackup({
          ..._json(kBlobInicio132),
          'steps': {'2026-11-19': 'muchos'},
        }),
        throwsA(anything),
      );

      expect(fit.backupSnapshot(), antes);
      expect(fit.steps, {'2026-11-19': 6412, '2026-11-20': 1200});
    });
  });

  group('copia ZIP', () {
    test('ida y vuelta: viajan pasos, días parciales, meta y activación, pero no stepsAskedAt', () async {
      await abrir(kBlobInicio132);
      conPasos();

      final zip = await buildBackupZip();
      final data = _jsonDelZip(zip);
      expect(data['steps'], {'2026-11-19': 6412, '2026-11-20': 1200});
      expect(data['stepsFrom'], {'2026-11-20': 872});
      expect(data['stepGoal'], 10000);
      expect(data['stepsOn'], isTrue);
      expect(data.containsKey('stepsAskedAt'), isFalse);
      expect(fit.stepsAskedAt, 1763600000000, reason: 'armar la copia no cambia el estado');

      fit.resetAllData();
      fit.stepsAskedAt = 1700000000000;
      expect(await restoreBackupZip(zip), isTrue);

      expect(fit.steps, {'2026-11-19': 6412, '2026-11-20': 1200});
      expect(fit.stepsFrom, {'2026-11-20': 872});
      expect(fit.stepGoal, 10000);
      expect(fit.stepsOn, isTrue);
      expect(fit.stepsAskedAt, 1700000000000);
      expect(fit.sessions, hasLength(5));
      expect(_json(prefs.getString(kKey)!)['steps'], {'2026-11-19': 6412, '2026-11-20': 1200});
    });

    test('una copia de 1.3.x conserva los pasos, la meta y el conteo de este teléfono', () async {
      await abrir(kBlobInicio132);
      conPasos();

      expect(await restoreBackupZip(_zipCon(_json(kBlobInicio132))), isTrue);

      expect(fit.steps, {'2026-11-19': 6412, '2026-11-20': 1200});
      expect(fit.stepsFrom, {'2026-11-20': 872});
      expect(fit.stepGoal, 10000);
      expect(fit.stepsOn, isTrue);
      expect(fit.stepsAskedAt, 1763600000000);
      expect(fit.sessions, hasLength(5));
      expect(fit.routines.single.name, 'Pecho y espalda pesado');
      expect(_json(prefs.getString(kKey)!)['steps'], {'2026-11-19': 6412, '2026-11-20': 1200});
    });

    test('un JSON de 1.3.x también conserva los pasos y la meta de este teléfono', () async {
      await abrir(kBlobInicio132);
      conPasos();

      expect(fit.importJson(kBlobInicio132), isTrue);

      expect(fit.steps, {'2026-11-19': 6412, '2026-11-20': 1200});
      expect(fit.stepsFrom, {'2026-11-20': 872});
      expect(fit.stepGoal, 10000);
      expect(fit.stepsOn, isTrue);
      expect(fit.sessions, hasLength(5));
    });

    test('una copia de 1.4.0 con los pasos vacíos manda: vacía el historial y trae su meta', () async {
      await abrir(kBlobInicio132);
      conPasos();

      final copia = {
        ..._json(kBlobInicio132),
        'steps': <String, Object?>{},
        'stepsFrom': <String, Object?>{},
        'stepGoal': 12000,
        'stepsOn': false,
      };
      expect(await restoreBackupZip(_zipCon(copia)), isTrue);

      expect(fit.steps, isEmpty);
      expect(fit.stepsFrom, isEmpty);
      expect(fit.stepGoal, 12000);
      expect(fit.stepsOn, isFalse);
      expect(fit.stepsAskedAt, 1763600000000);
    });

    test('una copia que trae solo algunas claves de pasos reemplaza esas y deja las demás', () async {
      await abrir(kBlobInicio132);
      conPasos();

      fit.applyBackup({..._json(kBlobInicio132), 'steps': <String, Object?>{}});

      expect(fit.steps, isEmpty);
      expect(fit.stepsFrom, {'2026-11-20': 872});
      expect(fit.stepGoal, 10000);
    });

    test('una clave de pasos presente con null manda: vacía o vuelve al valor por defecto', () async {
      await abrir(kBlobInicio132);
      conPasos();

      fit.applyBackup({..._json(kBlobInicio132), 'steps': null, 'stepGoal': null});

      expect(fit.steps, isEmpty);
      expect(fit.stepsFrom, {'2026-11-20': 872});
      expect(fit.stepGoal, 8000);
    });

    test('una copia que no se pudo guardar corta la lectura en curso y vuelve a leer con el estado del teléfono', () async {
      await abrir(kBlobInicio132);
      final previa = fit.stepSource;
      addTearDown(() => fit.stepSource = previa);
      final fuente = FakeStepSource();
      fit.stepSource = fuente;
      conPasos();
      fit.stepsOn = false;
      await fit.refreshSteps();
      expect(fit.stepsStatus, StepsStatus.off);
      fuente
        ..readGate = Completer<void>()
        ..days = [_diaRetenido];
      await _llenarDisco();

      final copia = {
        ..._json(kBlobInicio132),
        'steps': {'2026-11-18': 3000},
        'stepGoal': 12000,
        'stepsOn': true,
      };
      expect(await restoreBackupZip(_zipCon(copia)), isFalse);
      expect(fuente.reads, 1, reason: 'la lectura de la copia quedó retenida');
      fuente.readGate!.complete();
      await pumpEventQueue();

      expect(fit.steps, {'2026-11-19': 6412, '2026-11-20': 1200});
      expect(fit.stepGoal, 10000);
      expect(fit.stepsOn, isFalse);
      expect(fit.stepsStatus, StepsStatus.off);
      expect(fuente.stopped, 0);
    });

    test('el JSON exportado tampoco lleva stepsAskedAt', () async {
      await abrir(kBlobInicio132);
      conPasos();
      final data = _json(fit.exportJson());
      expect(data['steps'], {'2026-11-19': 6412, '2026-11-20': 1200});
      expect(data.containsKey('stepsAskedAt'), isFalse);
    });
  });

  group('rescate y borrado', () {
    Future<void> ofrecerRescateSinPasos() async {
      await abrir(
        jsonEncode({
          'onboarded': true,
          'routines': [
            {
              'id': 'r1',
              'n': 'Empuje',
              'ex': ['EIeI8Vf'],
            },
            42,
          ],
        }),
      );
      fit.persistNow();
      await pumpEventQueue();
      final disco = {for (final k in prefs.getKeys()) k: prefs.get(k)!};
      final copias = {
        for (final f in Directory('${tmp.path}/data_rescue').listSync())
          if (f is File) f.path: f.readAsStringSync(),
      };
      fit.resetAllData();
      Directory('${tmp.path}/data_rescue').createSync(recursive: true);
      copias.forEach((path, raw) => File(path).writeAsStringSync(raw));
      fit.saveAndExit();
      SharedPreferences.setMockInitialValues({...disco, kKey: '{roto'});
      Store.instance.debugReset();
      await Store.instance.init();
      prefs = await SharedPreferences.getInstance();
      fit.loadFromStore();
    }

    test('los pasos no cuentan como registros propios: el rescate se sigue ofreciendo', () async {
      await ofrecerRescateSinPasos();
      expect(fit.rescueOffer, isNotNull);

      conPasos();

      expect(fit.rescueOffer, isNotNull);
    });

    test('restaurar un rescate sin claves de pasos conserva el historial y la meta de este teléfono', () async {
      await ofrecerRescateSinPasos();
      final previa = fit.stepSource;
      addTearDown(() => fit.stepSource = previa);
      final fuente = FakeStepSource();
      fit.stepSource = fuente;
      conPasos();
      await fit.refreshSteps();
      expect(fit.stepsStatus, StepsStatus.counting);

      expect(fit.restoreRescue(), isTrue);
      await pumpEventQueue();

      expect(fit.stepsStatus, StepsStatus.off);
      expect(fuente.stopped, 1);

      expect(fit.routines.single.name, 'Empuje');
      expect(fit.steps, {'2026-11-19': 6412, '2026-11-20': 1200});
      expect(fit.stepsFrom, {'2026-11-20': 872});
      expect(fit.stepGoal, 10000);
      expect(fit.stepsOn, isFalse, reason: 'el rescate es este teléfono: sin stepsOn, el conteo queda apagado');
    });

    for (final discoLleno in [false, true]) {
      test(
        'restaurar un rescate ${discoLleno ? 'que no se pudo guardar ' : ''}corta la lectura en curso y no queda contando',
        () async {
          await ofrecerRescateSinPasos();
          final previa = fit.stepSource;
          addTearDown(() => fit.stepSource = previa);
          final fuente = FakeStepSource();
          fit.stepSource = fuente;
          conPasos();
          await fit.refreshSteps();
          expect(fit.stepsStatus, StepsStatus.counting);
          fuente
            ..readGate = Completer<void>()
            ..days = [_diaRetenido];
          final enCurso = fit.refreshSteps();
          await pumpEventQueue();
          expect(fuente.reads, 2);
          if (discoLleno) await _llenarDisco();

          expect(fit.restoreRescue(), isTrue);
          fuente.readGate!.complete();
          await enCurso;
          await pumpEventQueue();

          expect(fit.steps, {'2026-11-19': 6412, '2026-11-20': 1200});
          expect(fit.stepsOn, isFalse);
          expect(fit.stepsStatus, StepsStatus.off);
          expect(fuente.stopped, discoLleno ? 0 : 1);
        },
      );
    }

    test('un refresco que termina después de descartar el estado no notifica ni escribe', () async {
      final fuente = FakeStepSource()
        ..readGate = Completer<void>()
        ..days = [const StepDayReading('2026-11-20', 5000)];
      final estado = FitState()
        ..stepSource = fuente
        ..stepsOn = true;
      var avisos = 0;
      estado.addListener(() => avisos++);
      final antes = prefs.getString(kKey);

      final refresco = estado.refreshSteps();
      await pumpEventQueue();
      expect(fuente.reads, 1);
      estado.setStepGoal(12000);
      avisos = 0;
      estado.dispose();
      fuente.readGate!.complete();
      await refresco;
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(avisos, 0);
      expect(estado.steps, isEmpty);
      expect(prefs.getString(kKey), antes);
    });

    test('Borrar todos los datos vacía los pasos, apaga el conteo y vuelve la meta a 8000', () async {
      await abrir(kBlobInicio132);
      conPasos();

      fit.resetAllData();

      expect(fit.steps, isEmpty);
      expect(fit.stepsFrom, isEmpty);
      expect(fit.stepsOn, isFalse);
      expect(fit.stepGoal, 8000);
      final disco = _json(prefs.getString(kKey)!);
      expect(disco['steps'], isEmpty);
      expect(disco['stepsOn'], isFalse);
    });
  });
}
