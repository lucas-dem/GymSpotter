import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/services/media_store.dart';
import 'package:infyter/services/progress_reminder.dart';
import 'package:infyter/services/step_source.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late FakeStepSource source;
  late SharedPreferences prefs;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('infyter_fuente');
    Store.rescueDirectory = '${tmp.path}/data_rescue';
    MediaStore.directory = '${tmp.path}/media';
    ProgressReminder.instance.enabled = false;
    SharedPreferences.setMockInitialValues({});
    Store.instance.debugReset();
    await Store.instance.init();
    prefs = await SharedPreferences.getInstance();
    source = FakeStepSource();
    fit.stepSource = source;
    fit.resetAllData();
    await fit.refreshSteps();
    source.forgotten = 0;
    source.reads = 0;
  });

  tearDown(() async {
    fit.saveAndExit();
    fit.stepSource = createStepSource();
    Store.instance.debugReset();
    Store.rescueDirectory = null;
    MediaStore.directory = null;
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('estados', () {
    test('sin activar: no lee y queda en off', () async {
      source.days = [const StepDayReading('2026-11-20', 500)];
      await fit.refreshSteps();
      expect(fit.stepsStatus, StepsStatus.off);
      expect(fit.steps, isEmpty);
      expect(source.reads, 0);
    });

    test('no disponible, aunque no este activada', () async {
      source.available = false;
      await fit.refreshSteps();
      expect(fit.stepsStatus, StepsStatus.unavailable);
      fit.stepsOn = true;
      await fit.refreshSteps();
      expect(fit.stepsStatus, StepsStatus.unavailable);
      expect(source.reads, 0);
    });

    test('activada sin permiso pedido: necesita permiso y no lee', () async {
      fit.stepsOn = true;
      source.permissionValue = StepPermission.notDetermined;
      await fit.refreshSteps();
      expect(fit.stepsStatus, StepsStatus.needsPermission);
      expect(source.reads, 0);
    });

    test('negado: queda en denied y no lee', () async {
      fit.stepsOn = true;
      source.permissionValue = StepPermission.denied;
      await fit.refreshSteps();
      expect(fit.stepsStatus, StepsStatus.denied);
      expect(source.reads, 0);
    });

    test('contando: lee y guarda', () async {
      fit.stepsOn = true;
      source.permissionValue = StepPermission.granted;
      source.days = [const StepDayReading('2026-11-20', 1200, fromMinute: 872)];
      await fit.refreshSteps();
      expect(fit.stepsStatus, StepsStatus.counting);
      expect(fit.steps, {'2026-11-20': 1200});
      expect(fit.stepsFrom, {'2026-11-20': 872});
    });

    test('volver de ajustes con el permiso dado pasa de denied a counting', () async {
      fit.stepsOn = true;
      source.permissionValue = StepPermission.denied;
      await fit.refreshSteps();
      source.permissionValue = StepPermission.granted;
      source.days = [const StepDayReading('2026-11-20', 10)];
      await fit.refreshSteps();
      expect(fit.stepsStatus, StepsStatus.counting);
      expect(fit.steps['2026-11-20'], 10);
    });

    test('un error de la fuente no rompe ni cambia lo guardado', () async {
      fit.stepsOn = true;
      source.permissionValue = StepPermission.granted;
      fit.steps['2026-11-20'] = 300;
      source.fail = true;
      await fit.refreshSteps();
      expect(fit.steps, {'2026-11-20': 300});
    });
  });

  group('activar', () {
    test('concedido: activa, anota cuando pidio y cuenta', () async {
      source.permissionValue = StepPermission.notDetermined;
      source.requestResult = StepPermission.granted;
      source.days = [const StepDayReading('2026-11-20', 40)];
      await fit.enableSteps();
      expect(fit.stepsOn, isTrue);
      expect(fit.stepsAskedAt, isNotNull);
      expect(fit.stepsStatus, StepsStatus.counting);
      expect(fit.steps['2026-11-20'], 40);
    });

    test('negado: queda activada y en denied', () async {
      source.permissionValue = StepPermission.notDetermined;
      source.requestResult = StepPermission.denied;
      await fit.enableSteps();
      expect(fit.stepsOn, isTrue);
      expect(fit.stepsAskedAt, isNotNull);
      expect(fit.stepsStatus, StepsStatus.denied);
      expect(fit.steps, isEmpty);
    });

    test('sin fuente disponible no activa', () async {
      source.available = false;
      await fit.enableSteps();
      expect(fit.stepsOn, isFalse);
      expect(fit.stepsStatus, StepsStatus.unavailable);
    });
  });

  group('mezcla con el maximo', () {
    setUp(() {
      fit.stepsOn = true;
      source.permissionValue = StepPermission.granted;
    });

    test('lectura repetida sin cambios no cambia nada ni avisa', () async {
      source.days = [const StepDayReading('2026-11-20', 1200, fromMinute: 872)];
      await fit.refreshSteps();
      var avisos = 0;
      fit.addListener(() => avisos++);
      await fit.refreshSteps();
      await fit.refreshSteps();
      expect(fit.steps, {'2026-11-20': 1200});
      expect(fit.stepsFrom, {'2026-11-20': 872});
      expect(avisos, 0);
    });

    test('una correccion hacia arriba entra', () async {
      source.days = [const StepDayReading('2026-11-20', 1200)];
      await fit.refreshSteps();
      source.days = [const StepDayReading('2026-11-20', 1500)];
      await fit.refreshSteps();
      expect(fit.steps['2026-11-20'], 1500);
    });

    test('un valor menor no baja lo guardado ni toca stepsFrom', () async {
      fit.steps['2026-11-20'] = 5000;
      fit.stepsFrom['2026-11-20'] = 600;
      source.days = [const StepDayReading('2026-11-20', 900, fromMinute: 800)];
      await fit.refreshSteps();
      expect(fit.steps['2026-11-20'], 5000);
      expect(fit.stepsFrom['2026-11-20'], 600);
    });

    test('copia de otro telefono con mas pasos gana y no se suma', () async {
      fit.steps['2026-11-20'] = 9000;
      source.days = [const StepDayReading('2026-11-20', 3000, fromMinute: 700)];
      await fit.refreshSteps();
      expect(fit.steps['2026-11-20'], 9000);
      expect(fit.stepsFrom, isEmpty);
    });

    test('al ganar el valor leido, stepsFrom lo acompana', () async {
      fit.steps['2026-11-20'] = 100;
      fit.stepsFrom['2026-11-20'] = 600;
      source.days = [const StepDayReading('2026-11-20', 400)];
      await fit.refreshSteps();
      expect(fit.steps['2026-11-20'], 400);
      expect(fit.stepsFrom, isEmpty);
      source.days = [const StepDayReading('2026-11-20', 700, fromMinute: 90)];
      await fit.refreshSteps();
      expect(fit.stepsFrom['2026-11-20'], 90);
    });

    test('los dias que la fuente no devuelve quedan sin clave: hueco, no cero', () async {
      source.days = [const StepDayReading('2026-11-18', 4000), const StepDayReading('2026-11-20', 800)];
      await fit.refreshSteps();
      expect(fit.steps.containsKey('2026-11-19'), isFalse);
      expect(fit.steps.keys, ['2026-11-18', '2026-11-20']);
    });

    test('un dia con 0 pasos se guarda como 0 solo si la fuente lo informa', () async {
      source.days = [const StepDayReading('2026-11-20', 0)];
      await fit.refreshSteps();
      expect(fit.steps, {'2026-11-20': 0});
    });

    test('lecturas invalidas se ignoran', () async {
      source.days = [
        const StepDayReading('mal', 10),
        const StepDayReading('2026-11-20', -5),
        const StepDayReading('2026-11-21', 7),
      ];
      await fit.refreshSteps();
      expect(fit.steps, {'2026-11-21': 7});
    });

    test('cambio de zona horaria: los dias guardados no se reescriben ni bajan', () async {
      fit.steps['2026-11-20'] = 8000;
      source.days = [
        const StepDayReading('2026-11-20', 6500),
        const StepDayReading('2026-11-21', 120, fromMinute: 5),
      ];
      await fit.refreshSteps();
      expect(fit.steps, {'2026-11-20': 8000, '2026-11-21': 120});
      expect(fit.stepsFrom, {'2026-11-21': 5});
    });

    test('lo leido sale en el JSON que se guarda', () async {
      source.days = [const StepDayReading('2026-11-20', 321)];
      await fit.refreshSteps();
      expect(fit.toJson()['steps'], {'2026-11-20': 321});
    });
  });

  group('concurrencia y guardado', () {
    setUp(() {
      fit.stepsOn = true;
      source.permissionValue = StepPermission.granted;
    });

    test('dos refrescos a la vez se serializan y no cuentan dos veces', () async {
      source.readGate = Completer<void>();
      source.days = [const StepDayReading('2026-11-20', 100)];
      final a = fit.refreshSteps();
      final b = fit.refreshSteps();
      await Future<void>.delayed(Duration.zero);
      expect(source.reads, 1);
      source.readGate!.complete();
      await Future.wait([a, b]);
      expect(source.reads, 2);
      expect(fit.steps, {'2026-11-20': 100});
    });

    test('resetAllData en medio de una lectura no repuebla', () async {
      source.readGate = Completer<void>();
      source.days = [const StepDayReading('2026-11-20', 100)];
      final run = fit.refreshSteps();
      await Future<void>.delayed(Duration.zero);
      fit.resetAllData();
      source.readGate!.complete();
      await run;
      await fit.refreshSteps();
      expect(fit.steps, isEmpty);
      expect(fit.stepsStatus, StepsStatus.off);
    });

    test('la pausa durante una lectura guarda al momento', () async {
      source.readGate = Completer<void>();
      source.days = [const StepDayReading('2026-11-20', 250)];
      final first = fit.refreshSteps();
      final paused = fit.refreshSteps(saveNow: true);
      source.readGate!.complete();
      await Future.wait([first, paused]);
      expect(prefs.getString('gymmane_v1'), contains('"2026-11-20":250'));
    });

    test('sin cambios no se guarda de mas', () async {
      source.days = [const StepDayReading('2026-11-20', 250)];
      await fit.refreshSteps(saveNow: true);
      await prefs.remove('gymmane_v1');
      await fit.refreshSteps();
      await fit.refreshSteps(saveNow: true);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(prefs.getString('gymmane_v1'), isNull);
    });

    test('con cambios y sin saveNow el guardado es el diferido', () async {
      source.days = [const StepDayReading('2026-11-20', 250)];
      await fit.refreshSteps();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(prefs.getString('gymmane_v1'), contains('"2026-11-20":250'));
    });

    test('restaurar una copia invalida la lectura en curso y vuelve a leer', () async {
      source.readGate = Completer<void>();
      source.days = [const StepDayReading('2026-11-20', 100)];
      final run = fit.refreshSteps();
      await Future<void>.delayed(Duration.zero);
      final backup = fit.backupJson()
        ..['steps'] = {'2026-11-19': 7}
        ..['stepsOn'] = true;
      expect(fit.importJson(jsonEncode(backup)), isTrue);
      expect(fit.stepsStatus, StepsStatus.unread);
      source.readGate!.complete();
      await run;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fit.steps, {'2026-11-19': 7, '2026-11-20': 100});
      expect(fit.stepsStatus, StepsStatus.counting);
    });

    test('dos zonas horarias seguidas: los dias nuevos entran y los viejos no bajan', () async {
      source.days = [const StepDayReading('2026-11-20', 8000)];
      await fit.refreshSteps();
      source.days = [
        const StepDayReading('2026-11-20', 5200),
        const StepDayReading('2026-11-21', 90, fromMinute: 15),
      ];
      await fit.refreshSteps();
      source.days = [const StepDayReading('2026-11-21', 400)];
      await fit.refreshSteps();
      expect(fit.steps, {'2026-11-20': 8000, '2026-11-21': 400});
      expect(fit.stepsFrom.containsKey('2026-11-21'), isFalse);
    });

    test('tope por dia: lo que pasa de 345600 se descarta', () async {
      source.days = [
        const StepDayReading('2026-11-19', 345600),
        const StepDayReading('2026-11-20', 345601),
        const StepDayReading('1999-11-20', 5),
        StepDayReading('${DateTime.now().year + 2}-01-01', 5),
      ];
      await fit.refreshSteps();
      expect(fit.steps, {'2026-11-19': 345600});
    });

    test('enableSteps: si el pedido falla no activa nada', () async {
      fit.stepsOn = false;
      source.permissionValue = StepPermission.notDetermined;
      source.fail = true;
      await fit.enableSteps();
      expect(fit.stepsOn, isFalse);
      expect(fit.stepsAskedAt, isNull);
    });

    test('enableSteps: un resetAllData durante el pedido no reactiva', () async {
      fit.stepsOn = false;
      source.permissionValue = StepPermission.notDetermined;
      source.requestGate = Completer<void>();
      final run = fit.enableSteps();
      await Future<void>.delayed(Duration.zero);
      fit.resetAllData();
      source.requestGate!.complete();
      await run;
      expect(fit.stepsOn, isFalse);
      expect(fit.stepsAskedAt, isNull);
    });
  });

  group('borrar todo', () {
    test('resetAllData llama a forget y deja el estado en off', () async {
      fit.stepsOn = true;
      source.permissionValue = StepPermission.granted;
      source.days = [const StepDayReading('2026-11-20', 321)];
      await fit.refreshSteps();
      fit.resetAllData();
      expect(source.forgotten, 1);
      expect(fit.steps, isEmpty);
      expect(fit.stepsStatus, StepsStatus.unread);
      await fit.refreshSteps();
      expect(fit.stepsStatus, StepsStatus.off);
    });
  });

  group('fuente real sin canales nativos', () {
    test('se comporta como no disponible y no lanza', () async {
      final real = createStepSource();
      expect(await real.isAvailable(), isFalse);
      expect(await real.permission(), StepPermission.denied);
      expect(await real.requestPermission(), StepPermission.denied);
      expect(await real.readDays(), isEmpty);
      await real.forget();
    });
  });

  group('contrato del canal', () {
    test('nombres', () {
      expect(StepChannel.name, 'infyter/steps');
      expect(StepChannel.eventsName, 'infyter/steps/events');
      expect(StepChannel.isAvailable, 'isAvailable');
      expect(StepChannel.permissionStatus, 'permissionStatus');
      expect(StepChannel.requestPermission, 'requestPermission');
      expect(StepChannel.readCounter, 'readCounter');
      expect(StepChannel.readDays, 'readDays');
    });

    test('permisos en texto', () {
      expect(StepChannel.parsePermission('granted'), StepPermission.granted);
      expect(StepChannel.parsePermission('denied'), StepPermission.denied);
      expect(StepChannel.parsePermission('notDetermined'), StepPermission.notDetermined);
      expect(StepChannel.parsePermission('otra'), StepPermission.denied);
      expect(StepChannel.parsePermission(null), StepPermission.denied);
    });

    test('dias desde la respuesta del canal', () {
      final days = StepChannel.parseDays([
        {'day': '2026-11-19', 'steps': 6412},
        {'day': '2026-11-20', 'steps': 1200, 'fromMinute': 872},
        {'day': 'mal', 'steps': 3},
        {'day': '2026-11-21', 'steps': -1},
        'basura',
      ]);
      expect(days.map((d) => d.day), ['2026-11-19', '2026-11-20']);
      expect(days.last.fromMinute, 872);
      expect(days.first.fromMinute, isNull);
      expect(StepChannel.parseDays(null), isEmpty);
      expect(
        StepChannel.parseDays([
          {'day': '1999-12-31', 'steps': 1},
        ]),
        isEmpty,
      );
    });

    test('lectura cruda del sensor', () {
      final raw = StepCounterReading.fromMap({'counter': 120, 'wallMs': 5, 'elapsedMs': 3, 'bootCount': -1});
      expect(raw!.counter, 120);
      expect(raw.wallMs, 5);
      expect(raw.elapsedMs, 3);
      expect(raw.bootCount, -1);
      expect(StepCounterReading.fromMap(null), isNull);
      expect(StepCounterReading.fromMap({'counter': 1}), isNull);
    });
  });
}
