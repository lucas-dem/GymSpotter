import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/services/alarm_store.dart';
import 'package:infyter/services/backup_zip.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/services/media_store.dart';
import 'package:infyter/services/progress_reminder.dart';
import 'package:infyter/services/step_source.dart';
import 'package:infyter/services/step_source_ios.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
// La interfaz de plataforma de shared_preferences (dependencia transitiva) permite simular el disco lleno.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _methods = MethodChannel(StepChannel.name);
const _storeBlob = 'flutter.gymmane_v1';

/// Un disco que guarda todo menos el blob principal, como commit() sin espacio.
class _FullDisk extends InMemorySharedPreferencesStore {
  _FullDisk(super.data) : super.withData();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key != _storeBlob) return super.setValue(valueType, key, value);
    return false;
  }
}

const _lifecycleOrder = [
  AppLifecycleState.resumed,
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late Object? available;
  late Object? status;
  late Object? requested;
  late List<Object?> dayAnswers;
  late Completer<void>? readGate;
  late Object? readError;
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

  IosStepSource source({Duration interval = const Duration(minutes: 1), Duration? timeout}) =>
      IosStepSource(clock: () => now, updateInterval: interval, readTimeout: timeout ?? kIosReadTimeout);

  List<int> askedDays() => [
    for (final call in calls)
      if (call.method == StepChannel.readDays) (call.arguments as Map)['days'] as int,
  ];

  List<Object?> askedFrom() => [
    for (final call in calls)
      if (call.method == StepChannel.readDays) (call.arguments as Map)['fromMs'],
  ];

  Future<int?> storedStart() async => (await SharedPreferences.getInstance()).getInt(kIosStepStartKey);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    available = true;
    status = 'granted';
    requested = 'granted';
    dayAnswers = [];
    readGate = null;
    readError = null;
    now = DateTime(2026, 11, 20, 10);
    goTo(AppLifecycleState.paused);
    messenger.setMockMethodCallHandler(_methods, (call) async {
      calls.add(call);
      switch (call.method) {
        case StepChannel.isAvailable:
          return available;
        case StepChannel.permissionStatus:
          return status;
        case StepChannel.requestPermission:
          return status = requested;
        case StepChannel.readDays:
          await readGate?.future;
          final error = readError;
          if (error != null) throw error;
          return dayAnswers.isEmpty ? <Object?>[] : dayAnswers.removeAt(0);
      }
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_methods, null);
    goTo(AppLifecycleState.paused);
  });

  group('disponibilidad y permiso', () {
    test('disponible segun Core Motion; sin respuesta, no disponible', () async {
      expect(await source().isAvailable(), isTrue);
      available = false;
      expect(await source().isAvailable(), isFalse);
      available = null;
      expect(await source().isAvailable(), isFalse);
    });

    test('los tres textos del canal llegan como permiso; sin respuesta, negado', () async {
      final ios = source();
      for (final entry in {
        'granted': StepPermission.granted,
        'notDetermined': StepPermission.notDetermined,
        'denied': StepPermission.denied,
        null: StepPermission.denied,
      }.entries) {
        status = entry.key;
        expect(await ios.permission(), entry.value, reason: '${entry.key}');
      }
    });

    test('pedir el permiso devuelve la respuesta de la persona', () async {
      requested = 'denied';
      expect(await source().requestPermission(), StepPermission.denied);
      requested = 'granted';
      expect(await source().requestPermission(), StepPermission.granted);
      expect(calls.where((c) => c.method == StepChannel.requestPermission), hasLength(2));
    });

    test('un fallo del pedido sale como error, sin conceder nada', () async {
      messenger.setMockMethodCallHandler(_methods, (call) async => throw PlatformException(code: 'x'));
      await expectLater(source().requestPermission(), throwsA(isA<PlatformException>()));
    });
  });

  group('lecturas', () {
    test('la primera lectura pide los 7 dias y devuelve dias enteros, sin "desde"', () async {
      dayAnswers.add([
        {'day': '2026-11-18', 'steps': 4000},
        {'day': '2026-11-19', 'steps': 9000, 'fromMinute': 300},
        {'day': '2026-11-20', 'steps': 1200},
      ]);
      final days = await source().readDays();
      expect(askedDays(), [7]);
      expect(askedFrom(), [null]);
      expect(await storedStart(), 0);
      expect(
        [for (final d in days) '${d.day}=${d.steps}'],
        ['2026-11-18=4000', '2026-11-19=9000', '2026-11-20=1200'],
      );
      expect(days.every((d) => d.fromMinute == null), isTrue);
    });

    test('las entradas malas se descartan y no se inventan dias', () async {
      dayAnswers.add([
        {'day': '2026-11-20', 'steps': -5},
        {'day': '20-11-2026', 'steps': 10},
        {'day': '2026-11-19'},
        'basura',
        {'day': '2026-11-18', 'steps': 30.0},
      ]);
      final days = await source().readDays();
      expect(days.single.day, '2026-11-18');
      expect(days.single.steps, 30);
    });

    test('dentro de los 5 minutos solo se consulta hoy; despues, otra vez los 7 dias', () async {
      final ios = source();
      await ios.readDays();
      now = now.add(const Duration(minutes: 1));
      await ios.readDays();
      now = now.add(const Duration(minutes: 3, seconds: 59));
      await ios.readDays();
      now = now.add(const Duration(seconds: 1));
      await ios.readDays();
      await ios.readDays();
      expect(askedDays(), [7, 1, 1, 7, 1]);
    });

    test('al pasar la medianoche se vuelven a consultar los 7 dias, para cerrar ayer', () async {
      now = DateTime(2026, 11, 20, 23, 58);
      final ios = source();
      await ios.readDays();
      now = DateTime(2026, 11, 20, 23, 59, 30);
      await ios.readDays();
      now = DateTime(2026, 11, 21, 0, 0, 30);
      await ios.readDays();
      expect(askedDays(), [7, 1, 7]);
    });

    test('si el reloj vuelve atras se consultan los 7 dias', () async {
      final ios = source();
      await ios.readDays();
      now = now.subtract(const Duration(minutes: 1));
      await ios.readDays();
      expect(askedDays(), [7, 7]);
    });

    test('una consulta que falla sale como error y la siguiente vuelve a pedir los 7 dias', () async {
      final ios = source();
      readError = PlatformException(code: 'x');
      await expectLater(ios.readDays(), throwsA(isA<PlatformException>()));
      readError = null;
      await ios.readDays();
      expect(askedDays(), [7, 7]);
    });

    test('sin respuesta del Swift no hay dias y la siguiente vuelve a pedir los 7', () async {
      messenger.setMockMethodCallHandler(_methods, (call) async {
        calls.add(call);
        return null;
      });
      final ios = source();
      expect(await ios.readDays(), isEmpty);
      expect(await ios.readDays(), isEmpty);
      expect(askedDays(), [7, 7]);
    });

    test('una consulta colgada corta a tiempo, sin dias, y no bloquea la siguiente', () async {
      final ios = source(timeout: const Duration(milliseconds: 30));
      readGate = Completer<void>();
      expect(await ios.readDays(), isEmpty);
      readGate!.complete();
      readGate = null;
      dayAnswers.add([
        {'day': '2026-11-20', 'steps': 700},
      ]);
      dayAnswers.insert(0, <Object?>[]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final days = await ios.readDays();
      expect(days.single.steps, 700);
      expect(askedDays(), [7, 7]);
    });
  });

  group('forget y stopCounting', () {
    const week = [
      {'day': '2026-11-17', 'steps': 7000},
      {'day': '2026-11-18', 'steps': 8000},
      {'day': '2026-11-19', 'steps': 9000},
      {'day': '2026-11-20', 'steps': 1200},
    ];

    test('no llaman al Swift: Core Motion es del sistema', () async {
      final ios = source();
      await ios.forget();
      await ios.stopCounting();
      expect(calls, isEmpty);
    });

    test('apagar y volver a contar dias despues no rellena el hueco: cuenta desde ese momento', () async {
      now = DateTime(2026, 11, 16, 10);
      final ios = source();
      await ios.readDays();
      expect(askedFrom(), [null]);
      await ios.stopCounting();
      expect(await storedStart(), -1);
      now = DateTime(2026, 11, 19, 15, 30);
      dayAnswers.add(week);
      final days = await ios.readDays();
      final startMs = now.millisecondsSinceEpoch;
      expect(askedDays(), [7, 7]);
      expect(askedFrom(), [null, startMs]);
      expect(await storedStart(), startMs);
      expect(
        [for (final d in days) '${d.day}=${d.steps}@${d.fromMinute}'],
        ['2026-11-19=9000@${15 * 60 + 30}', '2026-11-20=1200@null'],
      );
    });

    test('el limite queda guardado: otra lectura, o la app reabierta, siguen desde la misma hora', () async {
      final ios = source();
      await ios.stopCounting();
      await ios.readDays();
      final startMs = now.millisecondsSinceEpoch;
      now = now.add(const Duration(hours: 2));
      await ios.readDays();
      await source().readDays();
      expect(askedFrom(), [startMs, startMs, startMs]);
    });

    test('despues de borrar los datos, al volver a contar no vuelven los dias de Core Motion', () async {
      final ios = source();
      dayAnswers.add(week);
      expect(await ios.readDays(), hasLength(4));
      await ios.forget();
      expect(await storedStart(), -1);
      now = DateTime(2026, 11, 20, 18);
      dayAnswers.add(week);
      final days = await source().readDays();
      expect(days.single.day, '2026-11-20');
      expect(days.single.fromMinute, 18 * 60);
    });

    test('si se vuelve a contar justo a medianoche el dia no queda parcial', () async {
      final ios = source();
      await ios.stopCounting();
      now = DateTime(2026, 11, 20);
      dayAnswers.add(week);
      final days = await ios.readDays();
      expect(days.single.day, '2026-11-20');
      expect(days.single.fromMinute, isNull);
    });

    test('un limite en el futuro (reloj atrasado) pasa a ser ahora', () async {
      SharedPreferences.setMockInitialValues({
        kIosStepStartKey: DateTime(2026, 11, 22).millisecondsSinceEpoch,
      });
      await source().readDays();
      expect(askedFrom(), [now.millisecondsSinceEpoch]);
    });

    test('apagar vuelve a pedir los 7 dias a Core Motion, aunque desde el limite', () async {
      final ios = source();
      await ios.readDays();
      await ios.stopCounting();
      await ios.readDays();
      await ios.forget();
      await ios.readDays();
      expect(askedDays(), [7, 7, 7]);
    });

    test('un permiso revocado y vuelto a dar no trae los dias del periodo revocado', () async {
      now = DateTime(2026, 11, 16, 10);
      final ios = source();
      await ios.readDays();
      status = 'denied';
      expect(await ios.permission(), StepPermission.denied);
      expect(await storedStart(), -1);
      status = 'granted';
      expect(await ios.permission(), StepPermission.granted);
      expect(await storedStart(), -1);
      now = DateTime(2026, 11, 19, 15, 30);
      dayAnswers.add(week);
      final days = await ios.readDays();
      expect(askedFrom(), [null, now.millisecondsSinceEpoch]);
      expect([for (final d in days) d.day], ['2026-11-19', '2026-11-20']);
      expect(days.first.fromMinute, 15 * 60 + 30);
    });

    test('un permiso sin decidir no deja la marca: la primera activacion trae los 7 dias', () async {
      final ios = source();
      status = 'notDetermined';
      expect(await ios.permission(), StepPermission.notDetermined);
      expect(await storedStart(), isNull);
      status = 'granted';
      dayAnswers.add(week);
      expect(await ios.readDays(), hasLength(4));
      expect(askedDays(), [7]);
      expect(askedFrom(), [null]);
    });

    test(
      'negar primero y conceder despues desde Ajustes trae igual los 7 dias de la primera activacion',
      () async {
        final ios = source();
        status = 'denied';
        expect(await ios.permission(), StepPermission.denied);
        expect(await storedStart(), isNull);
        status = 'granted';
        expect(await ios.permission(), StepPermission.granted);
        dayAnswers.add(week);
        final days = await ios.readDays();
        expect([for (final d in days) d.day], ['2026-11-17', '2026-11-18', '2026-11-19', '2026-11-20']);
        expect(days.every((d) => d.fromMinute == null), isTrue);
        expect(askedFrom(), [null]);
        expect(await storedStart(), 0);
      },
    );

    test('una lectura en curso al apagar no entrega nada', () async {
      final ios = source();
      readGate = Completer<void>();
      dayAnswers.add([
        {'day': '2026-11-20', 'steps': 500},
      ]);
      final pending = ios.readDays();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await ios.stopCounting();
      readGate!.complete();
      expect(await pending, isEmpty);
    });
  });

  group('aviso cada minuto en primer plano', () {
    // Timers reales con margenes holgados: espera la condicion hasta 10 s en vez de medir un tiempo fijo.
    Future<void> waitFor(bool Function() done) async {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!done() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    test('con la app abierta avisa cada intervalo y deja de hacerlo al pasar a segundo plano', () async {
      goTo(AppLifecycleState.resumed);
      final ios = source(interval: const Duration(milliseconds: 50));
      var ticks = 0;
      final sub = ios.updates.listen((_) => ticks++);
      await ios.readDays();
      expect(ios.ticking, isTrue);
      await waitFor(() => ticks >= 2);
      expect(ticks, greaterThanOrEqualTo(2));
      goTo(AppLifecycleState.inactive);
      expect(ios.ticking, isTrue);
      expect(ios.listening, isTrue);
      goTo(AppLifecycleState.paused);
      expect(ios.ticking, isFalse);
      expect(ios.listening, isFalse);
      final stopped = ticks;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(ticks, stopped);
      await sub.cancel();
    });

    test('el aviso no llega antes del intervalo', () async {
      goTo(AppLifecycleState.resumed);
      final ios = source(interval: const Duration(hours: 1));
      var ticks = 0;
      final sub = ios.updates.listen((_) => ticks++);
      await ios.readDays();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(ticks, 0);
      await ios.stopCounting();
      await sub.cancel();
    });

    test('en segundo plano una lectura no arranca el aviso', () async {
      final ios = source();
      await ios.readDays();
      expect(ios.ticking, isFalse);
    });

    test('apagar el conteo corta el aviso', () async {
      goTo(AppLifecycleState.resumed);
      final ios = source();
      await ios.readDays();
      expect(ios.ticking, isTrue);
      await ios.stopCounting();
      expect(ios.ticking, isFalse);
      expect(ios.listening, isFalse);
      goTo(AppLifecycleState.paused);
      goTo(AppLifecycleState.resumed);
      await ios.readDays();
      expect(ios.listening, isTrue);
      await ios.stopCounting();
    });

    test('una lectura fallida no arranca el aviso', () async {
      goTo(AppLifecycleState.resumed);
      final ios = source();
      readError = PlatformException(code: 'x');
      await expectLater(ios.readDays(), throwsA(isA<PlatformException>()));
      expect(ios.ticking, isFalse);
    });
  });

  group('con el estado de la app', () {
    late Directory tmp;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = await Directory.systemTemp.createTemp('infyter_ios_steps');
      Store.rescueDirectory = '${tmp.path}/data_rescue';
      MediaStore.directory = '${tmp.path}/media';
      AlarmStore.directory = '${tmp.path}/alarm';
      ProgressReminder.instance.enabled = false;
      Store.instance.debugReset();
      await Store.instance.init();
      fit.stepSource = const UnavailableStepSource();
      fit.resetAllData();
      await fit.refreshSteps();
      fit.stepSource = source();
      fit.stepsOn = true;
    });

    tearDown(() async {
      fit.saveAndExit();
      fit.stepSource = createStepSource();
      Store.rescueDirectory = null;
      MediaStore.directory = null;
      AlarmStore.directory = null;
      Store.instance.debugReset();
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('los 7 dias entran enteros, releer no cambia y una correccion hacia arriba entra', () async {
      dayAnswers.add([
        {'day': '2026-11-19', 'steps': 9000},
        {'day': '2026-11-20', 'steps': 1200},
      ]);
      await fit.refreshSteps();
      expect(fit.stepsStatus, StepsStatus.counting);
      expect(fit.steps, {'2026-11-19': 9000, '2026-11-20': 1200});
      expect(fit.stepsFrom, isEmpty);
      dayAnswers.add([
        {'day': '2026-11-20', 'steps': 1100},
      ]);
      await fit.refreshSteps();
      expect(fit.steps['2026-11-20'], 1200);
      now = now.add(const Duration(minutes: 1));
      dayAnswers.add([
        {'day': '2026-11-20', 'steps': 1500},
      ]);
      await fit.refreshSteps();
      expect(fit.steps, {'2026-11-19': 9000, '2026-11-20': 1500});
      expect(askedDays(), [7, 1, 1]);
    });

    test('sin permiso no se consulta Core Motion', () async {
      status = 'denied';
      await fit.refreshSteps();
      expect(fit.stepsStatus, StepsStatus.denied);
      expect(askedDays(), isEmpty);
      status = 'notDetermined';
      await fit.refreshSteps();
      expect(fit.stepsStatus, StepsStatus.needsPermission);
      expect(askedDays(), isEmpty);
    });

    test(
      'si el Swift corta la espera del dialogo a los 60 s queda en "Activar", y se puede volver a pedir',
      () async {
        status = 'notDetermined';
        requested = 'notDetermined';
        fit.stepsOn = false;
        await fit.enableSteps();
        expect(fit.stepsOn, isTrue);
        expect(fit.stepsStatus, StepsStatus.needsPermission);
        expect(askedDays(), isEmpty);
        requested = 'granted';
        await fit.enableSteps();
        expect(calls.where((c) => c.method == StepChannel.requestPermission), hasLength(2));
        expect(fit.stepsStatus, StepsStatus.counting);
        expect(askedDays(), [7]);
      },
    );

    test('borrar todos los datos y volver a contar no trae los dias viejos de Core Motion', () async {
      dayAnswers.add([
        {'day': '2026-11-19', 'steps': 9000},
        {'day': '2026-11-20', 'steps': 1200},
      ]);
      await fit.refreshSteps();
      expect(fit.steps, hasLength(2));
      fit.resetAllData();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fit.steps, isEmpty);
      now = now.add(const Duration(hours: 1));
      dayAnswers.add([
        {'day': '2026-11-19', 'steps': 9000},
        {'day': '2026-11-20', 'steps': 1500},
      ]);
      await fit.enableSteps();
      expect(fit.steps, {'2026-11-20': 1500});
      expect(fit.stepsFrom, {'2026-11-20': 11 * 60});
    });

    test(
      'restaurar una copia con el conteo apagado avisa a la fuente, y una con el conteo prendido no',
      () async {
        final fake = FakeStepSource();
        fit.stepSource = fake;
        expect(fit.importJson(jsonEncode(fit.backupJson()..['stepsOn'] = true)), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(fake.stopped, 0);
        expect(fit.importJson(jsonEncode(fit.backupJson()..['stepsOn'] = false)), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(fit.stepsOn, isFalse);
        expect(fake.stopped, 1);
        expect(fit.importJson(jsonEncode(fit.backupJson()..['stepsOn'] = false)), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(fake.stopped, 1);
      },
    );

    test(
      'en iOS, restaurar una copia con el conteo apagado y reactivar dias despues no trae los dias previos',
      () async {
        now = DateTime(2026, 11, 16, 10);
        dayAnswers.add([
          {'day': '2026-11-16', 'steps': 3000},
        ]);
        await fit.refreshSteps();
        expect(fit.steps, {'2026-11-16': 3000});
        expect(fit.importJson(jsonEncode(fit.backupJson()..['stepsOn'] = false)), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(fit.stepsOn, isFalse);
        expect(await storedStart(), -1);
        now = DateTime(2026, 11, 19, 15, 30);
        dayAnswers.add([
          {'day': '2026-11-16', 'steps': 3500},
          {'day': '2026-11-17', 'steps': 7000},
          {'day': '2026-11-18', 'steps': 8000},
          {'day': '2026-11-19', 'steps': 9000},
        ]);
        await fit.enableSteps();
        expect(fit.steps, {'2026-11-16': 3000, '2026-11-19': 9000});
        expect(fit.stepsFrom, {'2026-11-19': 15 * 60 + 30});
      },
    );

    test('en la app, negar al activar y conceder despues desde Ajustes trae los 7 dias', () async {
      fit.stepsOn = false;
      status = 'notDetermined';
      requested = 'denied';
      await fit.enableSteps();
      expect(fit.stepsOn, isTrue);
      expect(fit.stepsStatus, StepsStatus.denied);
      expect(await storedStart(), isNull);
      status = 'granted';
      dayAnswers.add([
        {'day': '2026-11-17', 'steps': 7000},
        {'day': '2026-11-20', 'steps': 1200},
      ]);
      await fit.refreshSteps();
      expect(fit.steps, {'2026-11-17': 7000, '2026-11-20': 1200});
      expect(fit.stepsFrom, isEmpty);
    });

    Uint8List zipOf(Map<String, dynamic> json) {
      final archive = Archive()..addFile(ArchiveFile.string(kBackupJsonEntry, jsonEncode(json)));
      return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
    }

    test(
      'una restauracion que se deshace por un error al guardar deja el conteo, la marca y la fuente intactos',
      () async {
        dayAnswers.add([
          {'day': '2026-11-20', 'steps': 1200},
        ]);
        await fit.refreshSteps();
        fit.persistNow();
        await pumpEventQueue();
        expect(await storedStart(), 0);
        final ios = fit.stepSource;
        final fake = FakeStepSource();
        final disk = await SharedPreferencesStorePlatform.instance.getAll();
        SharedPreferencesStorePlatform.instance = _FullDisk(disk);

        fit.stepSource = fake;
        expect(await restoreBackupZip(zipOf(fit.backupJson()..['stepsOn'] = false)), isFalse);
        await pumpEventQueue();
        expect(fit.stepsOn, isTrue);
        expect(fake.stopped, 0, reason: 'en Android el ancla no se borra');
        fit.confirmRestoredSteps();
        await pumpEventQueue();
        expect(fake.stopped, 0, reason: 'la vuelta atras descarta el aviso pendiente');

        fit.stepSource = ios;
        expect(await restoreBackupZip(zipOf(fit.backupJson()..['stepsOn'] = false)), isFalse);
        await pumpEventQueue();
        expect(fit.stepsOn, isTrue);
        expect(await storedStart(), 0, reason: 'en iOS la marca no pasa a arranque nuevo');
      },
    );

    test('una restauracion por ZIP que se guarda bien con el conteo apagado avisa a la fuente', () async {
      final fake = FakeStepSource();
      fit.stepSource = fake;
      expect(await restoreBackupZip(zipOf(fit.backupJson()..['stepsOn'] = false)), isTrue);
      await pumpEventQueue();
      expect(fit.stepsOn, isFalse);
      expect(fake.stopped, 1);
    });

    // Abre la app con [blob] sobre lo que quedo en disco, como al arrancar.
    Future<void> reopen(String blob) async {
      final prefs = await SharedPreferences.getInstance();
      final disk = {for (final key in prefs.getKeys()) key: prefs.get(key)!};
      final dir = Directory('${tmp.path}/data_rescue');
      final files = {
        if (dir.existsSync())
          for (final f in dir.listSync())
            if (f is File) f.path: f.readAsStringSync(),
      };
      final source = fit.stepSource;
      fit.resetAllData();
      fit.stepSource = source;
      dir.createSync(recursive: true);
      files.forEach((path, raw) => File(path).writeAsStringSync(raw));
      SharedPreferences.setMockInitialValues({...disk, 'gymmane_v1': blob});
      Store.instance.debugReset();
      await Store.instance.init();
      fit.loadFromStore();
    }

    // Una apertura con un item ilegible deja una copia de rescate (sin stepsOn) y la siguiente, ilegible, la ofrece.
    Future<void> offerRescue() async {
      await reopen(
        jsonEncode({
          'profile': {'name': 'Persona Prueba'},
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
      await reopen('{roto');
      expect(fit.rescueOffer, isNotNull);
    }

    test('restaurar un rescate con el conteo apagado avisa a la fuente cuando quedo guardado', () async {
      await offerRescue();
      final fake = FakeStepSource();
      fit.stepSource = fake;
      fit.stepsOn = true;
      expect(fit.restoreRescue(), isTrue);
      await pumpEventQueue();
      expect(fit.stepsOn, isFalse);
      expect(fake.stopped, 1);
    });

    test('restaurar un rescate que no se pudo guardar no avisa a la fuente', () async {
      await offerRescue();
      final fake = FakeStepSource();
      fit.stepSource = fake;
      fit.stepsOn = true;
      final disk = await SharedPreferencesStorePlatform.instance.getAll();
      SharedPreferencesStorePlatform.instance = _FullDisk(disk);
      expect(fit.restoreRescue(), isTrue);
      await pumpEventQueue();
      expect(fit.stepsOn, isFalse);
      expect(fake.stopped, 0);
    });

    test('restaurar un rescate sin cambiar el conteo no avisa a la fuente', () async {
      await offerRescue();
      final fake = FakeStepSource();
      fit.stepSource = fake;
      fit.stepsOn = false;
      expect(fit.restoreRescue(), isTrue);
      await pumpEventQueue();
      expect(fake.stopped, 0);
    });

    test('un iPad sin chip de movimiento queda como no disponible', () async {
      available = false;
      await fit.refreshSteps();
      expect(fit.stepsStatus, StepsStatus.unavailable);
      expect(askedDays(), isEmpty);
    });
  });
}
