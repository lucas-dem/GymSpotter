import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/services/alarm_store.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/services/media_store.dart';
import 'package:infyter/services/progress_reminder.dart';
import 'package:infyter/services/step_source.dart';
import 'package:infyter/services/step_source_android.dart';
import 'package:infyter/services/step_source_health.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _health = MethodChannel(kHealthStepsChannel);
const _sensor = MethodChannel(StepChannel.name);

const _lifecycleOrder = [
  AppLifecycleState.resumed,
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late List<MethodCall> sensorCalls;
  late Object? supported;
  late Object? status;
  late Object? requested;
  late List<Object?> dayAnswers;
  late Object? opens;
  late DateTime now;

  void goTo(AppLifecycleState target) {
    var at = binding.lifecycleState;
    if (at == null || !_lifecycleOrder.contains(at)) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      at = AppLifecycleState.resumed;
    }
    var i = _lifecycleOrder.indexOf(at);
    final end = _lifecycleOrder.indexOf(target);
    while (i != end) {
      i += i < end ? 1 : -1;
      binding.handleAppLifecycleStateChanged(_lifecycleOrder[i]);
    }
  }

  HealthConnectStepSource source() => HealthConnectStepSource(clock: () => now);

  List<Map<dynamic, dynamic>> reads() => [
    for (final call in calls)
      if (call.method == 'readDays') call.arguments as Map,
  ];

  Future<int?> storedStart() async => (await SharedPreferences.getInstance()).getInt(kHealthStepStartKey);

  /// Los 7 dias que terminan en [now], del mas viejo a hoy; null deja ese dia sin dato.
  List<Map<String, Object>> week(List<int?> steps) {
    final out = <Map<String, Object>>[];
    for (var i = 0; i < steps.length; i++) {
      final value = steps[i];
      if (value == null) continue;
      out.add({'day': _key(DateTime(now.year, now.month, now.day - (steps.length - 1 - i))), 'steps': value});
    }
    return out;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    sensorCalls = [];
    supported = true;
    status = 'granted';
    requested = 'granted';
    dayAnswers = [];
    opens = true;
    now = DateTime(2026, 11, 24, 10);
    goTo(AppLifecycleState.resumed);
    messenger.setMockMethodCallHandler(_health, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'supported':
          return supported;
        case 'permissionStatus':
          return status;
        case 'requestPermission':
          return status = requested;
        case 'readDays':
          return dayAnswers.isEmpty ? <Object?>[] : dayAnswers.removeAt(0);
        case 'openSettings':
          return opens;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_sensor, (call) async {
      sensorCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_health, null);
    messenger.setMockMethodCallHandler(_sensor, null);
    goTo(AppLifecycleState.paused);
  });

  group('eleccion de fuente', () {
    test('con conteo propio de Health Connect elige Health Connect', () async {
      final chosen = await chooseStepSource(android: true);
      expect(chosen, isA<HealthConnectStepSource>());
      expect(readsHealthConnect(chosen), isTrue);
    });

    test('sin conteo propio (Android 13 o anterior, extension menor que 20) queda el sensor', () async {
      supported = false;
      final chosen = await chooseStepSource(android: true);
      expect(chosen, isA<AndroidStepSource>());
      expect(readsHealthConnect(chosen), isFalse);
    });

    test('si la consulta falla o no responde, queda el sensor', () async {
      messenger.setMockMethodCallHandler(_health, (call) async => throw PlatformException(code: 'x'));
      expect(await chooseStepSource(android: true), isA<AndroidStepSource>());
      messenger.setMockMethodCallHandler(_health, null);
      expect(await chooseStepSource(android: true), isA<AndroidStepSource>(), reason: 'sin canal');
      final never = Completer<Object?>();
      messenger.setMockMethodCallHandler(_health, (call) => never.future);
      final chosen = await chooseStepSource(android: true, timeout: const Duration(milliseconds: 50));
      expect(chosen, isA<AndroidStepSource>());
    });

    test('fuera de Android no consulta Health Connect', () async {
      final chosen = await chooseStepSource(android: false);
      expect(readsHealthConnect(chosen), isFalse);
      expect(calls, isEmpty);
    });
  });

  group('la fuente', () {
    test('lee los 7 dias sin limite la primera vez, sin "desde" y sin dias vacios', () async {
      dayAnswers.add(week([4000, null, 7000, 0, 8000, 9000, 1200]));
      final hc = source();
      final days = await hc.readDays();
      expect(reads().single, {'days': 7});
      expect(days.map((d) => d.day), [
        for (final back in [6, 4, 2, 1, 0]) _key(DateTime(2026, 11, 24 - back)),
      ], reason: 'un dia sin dato o con 0 queda hueco');
      expect(days.every((d) => d.fromMinute == null), isTrue);
      expect(await storedStart(), 0);
      expect(hc.ticking, isTrue);
    });

    test('entre lecturas pide solo hoy; a los 5 minutos o al cambiar el dia, los 7', () async {
      final hc = source();
      await hc.readDays();
      now = now.add(const Duration(minutes: 1));
      await hc.readDays();
      now = now.add(const Duration(minutes: 5));
      await hc.readDays();
      now = DateTime(2026, 11, 24, 23, 59);
      await hc.readDays();
      now = DateTime(2026, 11, 25, 0, 1);
      await hc.readDays();
      expect(reads().map((r) => r['days']), [7, 1, 7, 7, 7]);
    });

    test('con la app en segundo plano no lee', () async {
      goTo(AppLifecycleState.paused);
      expect(await source().readDays(), isEmpty);
      expect(reads(), isEmpty);
    });

    test(
      'apagar deja arranque nuevo: la siguiente lectura cuenta desde ahora y descarta los dias previos',
      () async {
        final hc = source();
        await hc.readDays();
        await hc.stopCounting();
        expect(await storedStart(), -1);
        expect(hc.ticking, isFalse);
        now = DateTime(2026, 11, 26, 15);
        dayAnswers.add(week([null, null, null, null, 7000, 8000, 300]));
        final days = await hc.readDays();
        final from = now.millisecondsSinceEpoch;
        expect(reads().last, {'days': 7, 'fromMs': from});
        expect(await storedStart(), from);
        expect(days.map((d) => d.day), ['2026-11-26']);
      },
    );

    test('borrar todo marca arranque nuevo y borra el ancla vieja del sensor', () async {
      final hc = source();
      await hc.readDays();
      await hc.forget();
      expect(await storedStart(), -1);
      expect(sensorCalls.map((c) => c.method), [StepChannel.clearAnchor]);
    });

    test('un permiso negado despues de contar marca arranque nuevo; antes de contar nunca, no', () async {
      status = 'denied';
      final hc = source();
      expect(await hc.permission(), StepPermission.denied);
      expect(await storedStart(), isNull, reason: 'la primera activacion conserva sus 7 dias');
      status = 'granted';
      await hc.readDays();
      expect(await storedStart(), 0);
      status = 'denied';
      expect(await hc.permission(), StepPermission.denied);
      expect(await storedStart(), -1);
    });

    test('revocado desde Health Connect llega como notDetermined y tambien marca arranque nuevo', () async {
      final hc = source();
      await hc.readDays();
      expect(await storedStart(), 0);
      status = 'notDetermined';
      expect(await hc.permission(), StepPermission.notDetermined);
      expect(await storedStart(), -1);
    });

    test('estrenar Health Connect sin historia deja los 7 dias; con historia ajusta desde cuando', () async {
      final since = DateTime(2026, 11, 22, 8).millisecondsSinceEpoch;
      final hc = source();
      await hc.adoptHistory(counting: true, hasHistory: false, since: since);
      expect(await storedStart(), isNull, reason: 'primera activacion de la historia');
      await hc.adoptHistory(counting: true, hasHistory: true, since: since);
      expect(await storedStart(), since, reason: 'contando desde la ultima activacion');
      await hc.adoptHistory(counting: false, hasHistory: true, since: since);
      expect(await storedStart(), since, reason: 'una marca ya puesta no se toca');
      SharedPreferences.setMockInitialValues({});
      await hc.adoptHistory(counting: false, hasHistory: true, since: since);
      expect(await storedStart(), -1, reason: 'apagado: desde la proxima lectura');
      SharedPreferences.setMockInitialValues({});
      await hc.adoptHistory(counting: true, hasHistory: true);
      expect(await storedStart(), -1, reason: 'contando sin saber desde cuando');
    });

    test('abrir Health Connect usa el canal y dice si se abrio', () async {
      final hc = source();
      expect(await hc.openHealthConnect(), isTrue);
      opens = false;
      expect(await hc.openHealthConnect(), isFalse);
      expect(calls.where((c) => c.method == 'openSettings'), hasLength(2));
    });
  });

  group('con el estado de la app', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('infyter_hc_steps');
      Store.rescueDirectory = '${tmp.path}/data_rescue';
      MediaStore.directory = '${tmp.path}/media';
      AlarmStore.directory = '${tmp.path}/alarm';
      ProgressReminder.instance.enabled = false;
      Store.instance.debugReset();
      await Store.instance.init();
      fit.stepSource = const UnavailableStepSource();
      fit.resetAllData();
      await fit.refreshSteps();
      await pumpEventQueue();
      fit.stepSource = source();
    });

    tearDown(() async {
      fit.saveAndExit();
      fit.stepSource = const UnavailableStepSource();
      fit.resetAllData();
      await pumpEventQueue();
      Store.rescueDirectory = null;
      MediaStore.directory = null;
      AlarmStore.directory = null;
      await tmp.delete(recursive: true);
    });

    test('al activar trae los 7 dias y los dias sin dato quedan como hueco', () async {
      status = 'notDetermined';
      dayAnswers.add(week([4000, null, 7000, 6000, null, 9000, 1200]));
      await fit.enableSteps();
      expect(calls.where((c) => c.method == 'requestPermission'), hasLength(1));
      expect(fit.stepsStatus, StepsStatus.counting);
      expect(fit.steps, {
        '2026-11-18': 4000,
        '2026-11-20': 7000,
        '2026-11-21': 6000,
        '2026-11-23': 9000,
        '2026-11-24': 1200,
      });
      expect(fit.stepsFrom, isEmpty);
    });

    test('el dia del cambio de metodo nunca baja un dia guardado y no suma los dos metodos', () async {
      fit.stepsOn = true;
      fit.steps
        ..['2026-11-22'] = 5000
        ..['2026-11-24'] = 1234;
      fit.stepsFrom['2026-11-24'] = 14 * 60 + 32;
      dayAnswers.add(week([null, null, null, null, 4000, null, 900]));
      await fit.refreshSteps();
      expect(fit.steps['2026-11-22'], 5000);
      expect(fit.steps['2026-11-24'], 1234);
      expect(fit.stepsFrom['2026-11-24'], 14 * 60 + 32, reason: 'gana el valor del sensor y su "desde"');
      now = now.add(const Duration(minutes: 1));
      dayAnswers.add(week([2000]));
      await fit.refreshSteps();
      expect(fit.steps['2026-11-24'], 2000, reason: 'cuando Health Connect pasa al sensor, gana su numero');
      expect(fit.stepsFrom.containsKey('2026-11-24'), isFalse);
      expect(fit.steps['2026-11-22'], 5000);
    });

    test('permiso negado: lo dice, no lee ni cae al sensor; vuelto a dar cuenta desde ese momento', () async {
      fit.stepsOn = true;
      dayAnswers.add(week([null, null, null, null, null, 3000, 500]));
      await fit.refreshSteps();
      expect(fit.steps, {'2026-11-23': 3000, '2026-11-24': 500});

      status = 'denied';
      await fit.refreshSteps();
      expect(fit.stepsStatus, StepsStatus.denied);
      expect(readsHealthConnect(fit.stepSource), isTrue);
      expect(reads(), hasLength(1));
      expect(sensorCalls, isEmpty);

      now = DateTime(2026, 11, 25, 9);
      status = 'granted';
      dayAnswers.add(week([null, null, null, null, null, 9000, 40]));
      await fit.refreshSteps();
      expect(fit.stepsStatus, StepsStatus.counting);
      expect(reads().last['fromMs'], now.millisecondsSinceEpoch);
      expect(fit.steps, {'2026-11-23': 3000, '2026-11-24': 500, '2026-11-25': 40});
    });

    test('permiso revocado desde Health Connect y vuelto a dar no trae el periodo revocado', () async {
      fit.stepsOn = true;
      dayAnswers.add(week([null, null, null, null, null, null, 500]));
      await fit.refreshSteps();
      status = 'notDetermined';
      await fit.refreshSteps();
      expect(fit.stepsStatus, StepsStatus.needsPermission);
      now = DateTime(2026, 11, 26, 9);
      status = 'granted';
      dayAnswers.add(week([null, null, null, null, 7000, 8000, 60]));
      await fit.refreshSteps();
      expect(reads().last['fromMs'], now.millisecondsSinceEpoch);
      expect(fit.steps, {'2026-11-24': 500, '2026-11-26': 60});
    });

    test('quien contaba con el sensor: al estrenar Health Connect entra solo lo de despues de su activacion', () async {
      final since = DateTime(2026, 11, 22, 8).millisecondsSinceEpoch;
      fit.stepsOn = true;
      fit.stepsAskedAt = since;
      fit.steps['2026-11-22'] = 3000;
      await fit.useStepSource(source());
      dayAnswers.add(week([4000, 5000, 6000, 7000, 8000, 9000, 100]));
      await fit.refreshSteps();
      expect(reads().single['fromMs'], since);
      expect(fit.steps, {'2026-11-22': 8000, '2026-11-23': 9000, '2026-11-24': 100});
    });

    test('quien habia apagado el conteo con el sensor: al reactivar con Health Connect no entra lo apagado', () async {
      fit.stepsOn = false;
      fit.stepsAskedAt = DateTime(2026, 11, 10).millisecondsSinceEpoch;
      fit.steps['2026-11-10'] = 3000;
      await fit.useStepSource(source());
      expect(await storedStart(), -1);
      dayAnswers.add(week([4000, 5000, 6000, 7000, 8000, 9000, 100]));
      await fit.enableSteps();
      expect(reads().single['fromMs'], now.millisecondsSinceEpoch);
      expect(fit.steps, {'2026-11-10': 3000, '2026-11-24': 100});
    });

    test('apagar y prender el conteo no suma lo caminado con el conteo apagado', () async {
      fit.stepsOn = true;
      dayAnswers.add(week([null, null, null, null, null, null, 800]));
      await fit.refreshSteps();
      fit.disableSteps();
      await pumpEventQueue();
      expect(fit.stepsOn, isFalse);
      expect(await storedStart(), -1);
      expect(fit.steps, {'2026-11-24': 800}, reason: 'apagar conserva el historial');

      now = DateTime(2026, 11, 26, 18);
      dayAnswers.add(week([null, null, null, null, 6000, 7000, 150]));
      await fit.enableSteps();
      expect(fit.stepsOn, isTrue);
      expect(reads().last['fromMs'], now.millisecondsSinceEpoch);
      expect(fit.steps, {'2026-11-24': 800, '2026-11-26': 150});
    });

    test('borrar todos los datos vacia los pasos y al volver a contar no trae los dias viejos', () async {
      fit.stepsOn = true;
      dayAnswers.add(week([null, null, null, null, null, 9000, 1200]));
      await fit.refreshSteps();
      fit.resetAllData();
      await pumpEventQueue();
      expect(fit.steps, isEmpty);
      expect(fit.stepsOn, isFalse);
      expect(await storedStart(), -1);
      expect(sensorCalls.map((c) => c.method), [StepChannel.clearAnchor]);

      now = now.add(const Duration(hours: 1));
      dayAnswers.add(week([null, null, null, null, null, 9000, 1500]));
      await fit.enableSteps();
      expect(fit.steps, {'2026-11-24': 1500});
      expect(fit.stepsFrom, isEmpty);
    });

    test(
      'restaurar una copia mezcla con el maximo y una copia con el conteo apagado deja arranque nuevo',
      () async {
        fit.stepsOn = true;
        dayAnswers.add(week([null, null, null, null, null, 3000, 1000]));
        await fit.refreshSteps();
        final copy = fit.backupJson()
          ..['steps'] = {'2026-11-20': 8000, '2026-11-23': 2500, '2026-11-24': 4000}
          ..['stepsOn'] = true;
        dayAnswers.add(week([null, null, null, null, null, 3000, 1100]));
        expect(fit.importJson(jsonEncode(copy)), isTrue);
        await pumpEventQueue();
        await fit.refreshSteps();
        expect(fit.steps, {'2026-11-20': 8000, '2026-11-23': 3000, '2026-11-24': 4000});

        expect(fit.importJson(jsonEncode(fit.backupJson()..['stepsOn'] = false)), isTrue);
        await pumpEventQueue();
        expect(fit.stepsOn, isFalse);
        expect(await storedStart(), -1);
      },
    );
  });
}
