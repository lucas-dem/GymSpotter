import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/app/infyter_app.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/services/media_store.dart';
import 'package:infyter/services/progress_reminder.dart';
import 'package:infyter/services/step_anchor.dart';
import 'package:infyter/services/step_source.dart';
import 'package:infyter/services/step_source_android.dart';
import 'package:infyter/services/update_check.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:infyter/state/update_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int _minute = 60 * 1000;
const int _hour = 60 * _minute;
const _methods = MethodChannel(StepChannel.name);
const _events = EventChannel(StepChannel.eventsName);
const _lifecycleOrder = [
  AppLifecycleState.resumed,
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = binding.defaultBinaryMessenger;

  StepLocalTime clock(int wallMs) {
    final t = DateTime.fromMillisecondsSinceEpoch(wallMs, isUtc: true).subtract(const Duration(hours: 3));
    final day = '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    return StepLocalTime(day, t.hour * 60 + t.minute, -180);
  }

  int local(int day, int hour, [int minute = 0]) =>
      DateTime.utc(2026, 11, day, hour + 3, minute).millisecondsSinceEpoch;

  Map<String, int> raw(int counter, int wallMs, int elapsedMs, {int boot = 7}) => {
    'counter': counter,
    'wallMs': wallMs,
    'elapsedMs': elapsedMs,
    'bootCount': boot,
  };

  late List<Object?> counterAnswers;
  late List<String> calls;
  late Completer<void>? counterGate;
  late MockStreamHandlerEventSink? sink;
  late int listens;
  late int cancels;
  late Map<String, Object> native;

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

  AndroidStepSource source({Duration interval = kStepUpdateInterval}) =>
      AndroidStepSource(localTime: clock, updateInterval: interval);

  Future<Map<String, Object?>?> savedAnchor() async {
    await Future<void>.delayed(Duration.zero);
    final text = native[kStepAnchorKey] as String?;
    return text == null ? null : jsonDecode(text) as Map<String, Object?>;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    counterAnswers = [];
    calls = [];
    counterGate = null;
    sink = null;
    listens = 0;
    cancels = 0;
    native = {'permission_asked': true};
    goTo(AppLifecycleState.paused);
    messenger.setMockMethodCallHandler(_methods, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case StepChannel.readCounter:
          await counterGate?.future;
          return counterAnswers.isEmpty ? null : counterAnswers.removeAt(0);
        case StepChannel.isAvailable:
          return true;
        case StepChannel.permissionStatus:
        case StepChannel.requestPermission:
          return 'granted';
        case StepChannel.loadAnchor:
          return native[kStepAnchorKey];
        case StepChannel.saveAnchor:
          native[kStepAnchorKey] = (call.arguments as Map)['anchor'] as String;
        case StepChannel.clearAnchor:
          native.remove(kStepAnchorKey);
        case StepChannel.forget:
          native.clear();
      }
      return null;
    });
    messenger.setMockStreamHandler(
      _events,
      MockStreamHandler.inline(
        onListen: (_, events) {
          listens++;
          sink = events;
        },
        onCancel: (_) {
          cancels++;
          sink = null;
        },
      ),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_methods, null);
    messenger.setMockStreamHandler(_events, null);
  });

  group('lecturas', () {
    test('sin lectura y sin ancla: ningun dia, ni siquiera en 0', () async {
      expect(await source().readDays(), isEmpty);
      expect(await savedAnchor(), isNull);
    });

    test('la primera lectura abre el dia parcial y guarda el ancla aparte', () async {
      counterAnswers.add(raw(5000, local(20, 8, 30), 10 * _hour));
      final days = await source().readDays();
      expect(days.single.day, '2026-11-20');
      expect(days.single.steps, 0);
      expect(days.single.fromMinute, 8 * 60 + 30);
      final saved = (await savedAnchor())!;
      expect(saved['c'], 5000);
      expect(saved['acc'], 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), isEmpty);
    });

    test('el ancla sobrevive a cerrar la app y la siguiente lectura suma', () async {
      counterAnswers.add(raw(5000, local(20, 8), 10 * _hour));
      await source().readDays();
      counterAnswers.add(raw(6200, local(20, 9), 11 * _hour));
      final days = await source().readDays();
      expect(days.single.steps, 1200);
      expect(days.single.fromMinute, 8 * 60);
    });

    test('si el sensor no responde, devuelve lo que ya sabia sin cambiarlo', () async {
      counterAnswers.add(raw(5000, local(20, 8), 10 * _hour));
      final s = source();
      await s.readDays();
      counterAnswers.add(raw(5400, local(20, 9), 11 * _hour));
      await s.readDays();
      final days = await source().readDays();
      expect(days.single.steps, 400);
      expect((await savedAnchor())!['c'], 5400);
    });

    test('un ancla guardada rota se descarta y empieza un tramo nuevo', () async {
      native[kStepAnchorKey] = '{no es json';
      counterAnswers.add(raw(5000, local(20, 8), 10 * _hour));
      final days = await source().readDays();
      expect(days.single.steps, 0);
      expect(days.single.fromMinute, 8 * 60);
    });

    test('estado, pedido y disponibilidad pasan por el canal', () async {
      final s = source();
      expect(await s.isAvailable(), isTrue);
      expect(await s.permission(), StepPermission.granted);
      expect(await s.requestPermission(), StepPermission.granted);
      expect(calls, [StepChannel.isAvailable, StepChannel.permissionStatus, StepChannel.requestPermission]);
    });
  });

  group('forget', () {
    test('borra el ancla y la marca nativa; la lectura siguiente empieza de cero', () async {
      final s = source();
      counterAnswers.add(raw(5000, local(20, 8), 10 * _hour));
      await s.readDays();
      counterAnswers.add(raw(5600, local(20, 9), 11 * _hour));
      await s.readDays();
      await s.forget();
      expect(await savedAnchor(), isNull);
      expect(native.containsKey('permission_asked'), isFalse);
      expect(s.anchor, isNull);
      expect(calls, contains(StepChannel.forget));
      counterAnswers.add(raw(5900, local(20, 10), 12 * _hour));
      final days = await s.readDays();
      expect(days.single.steps, 0);
      expect(days.single.fromMinute, 10 * 60);
    });

    test('una lectura en curso durante forget no vuelve a guardar el ancla', () async {
      final s = source();
      counterGate = Completer<void>();
      counterAnswers.add(raw(5000, local(20, 8), 10 * _hour));
      final pending = s.readDays();
      await Future<void>.delayed(Duration.zero);
      await s.forget();
      counterGate!.complete();
      expect(await pending, isEmpty);
      expect(await savedAnchor(), isNull);
      expect(s.anchor, isNull);
    });
  });

  group('stopCounting', () {
    test(
      'borra solo el ancla: la marca del permiso queda y lo caminado con el conteo apagado no se suma',
      () async {
        goTo(AppLifecycleState.resumed);
        final s = source();
        counterAnswers.add(raw(5000, local(20, 8), 10 * _hour));
        await s.readDays();
        sink!.success(raw(5300, local(20, 8, 5), 10 * _hour + 5 * _minute));
        await Future<void>.delayed(Duration.zero);
        await s.stopCounting();
        expect(s.watching, isFalse);
        expect(cancels, 1);
        expect(s.anchor, isNull);
        expect(await savedAnchor(), isNull);
        expect(native['permission_asked'], isTrue);
        expect(calls, contains(StepChannel.clearAnchor));
        expect(calls, isNot(contains(StepChannel.forget)));
        counterAnswers.add(raw(9000, local(20, 11), 13 * _hour));
        final days = await s.readDays();
        expect(days.single.steps, 0);
        expect(days.single.fromMinute, 11 * 60);
        goTo(AppLifecycleState.paused);
      },
    );

    test('una lectura en curso al apagar no vuelve a guardar el ancla', () async {
      final s = source();
      counterGate = Completer<void>();
      counterAnswers.add(raw(5000, local(20, 8), 10 * _hour));
      final pending = s.readDays();
      await Future<void>.delayed(Duration.zero);
      await s.stopCounting();
      counterGate!.complete();
      expect(await pending, isEmpty);
      expect(await savedAnchor(), isNull);
    });
  });

  group('escucha en primer plano', () {
    test('con la app en segundo plano no escucha', () async {
      counterAnswers.add(raw(5000, local(20, 8), 10 * _hour));
      final s = source();
      await s.readDays();
      expect(s.watching, isFalse);
      expect(listens, 0);
    });

    test('en primer plano escucha, suma cada evento y deja de escuchar al pasar a segundo plano', () async {
      goTo(AppLifecycleState.resumed);
      final s = source();
      counterAnswers.add(raw(5000, local(20, 8), 10 * _hour));
      await s.readDays();
      expect(listens, 1);
      sink!.success(raw(5100, local(20, 8, 1), 10 * _hour + _minute));
      sink!.success(raw(5300, local(20, 8, 2), 10 * _hour + 2 * _minute));
      await Future<void>.delayed(Duration.zero);
      expect(s.anchor!.steps, 300);
      final callsBefore = calls.where((c) => c == StepChannel.readCounter).length;
      final days = await s.readDays();
      expect(days.single.steps, 300);
      expect(calls.where((c) => c == StepChannel.readCounter).length, callsBefore);
      sink!.success(raw(5450, local(20, 8, 3), 10 * _hour + 3 * _minute));
      await Future<void>.delayed(Duration.zero);
      expect((await savedAnchor())!['acc'], 300);
      goTo(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);
      expect(cancels, 1);
      expect(s.watching, isFalse);
      expect((await savedAnchor())!['acc'], 450);
    });

    test('un evento de otro dia no pierde lo del dia anterior', () async {
      goTo(AppLifecycleState.resumed);
      final s = source();
      var updates = 0;
      final sub = s.updates.listen((_) => updates++);
      counterAnswers.add(raw(5000, local(20, 23, 50), 10 * _hour));
      await s.readDays();
      sink!.success(raw(5200, local(20, 23, 55), 10 * _hour + 5 * _minute));
      sink!.success(raw(5250, local(21, 0, 5), 10 * _hour + 15 * _minute));
      await Future<void>.delayed(Duration.zero);
      expect(updates, 2);
      expect((await savedAnchor())!['day'], '2026-11-20');
      final days = await s.readDays();
      expect(days.map((d) => (d.day, d.steps, d.fromMinute)), [
        ('2026-11-20', 200, 23 * 60 + 50),
        ('2026-11-21', 0, 5),
      ]);
      expect((await savedAnchor())!['day'], '2026-11-21');
      await sub.cancel();
      goTo(AppLifecycleState.paused);
    });

    test('avisa de pasos nuevos como mucho una vez por intervalo', () async {
      goTo(AppLifecycleState.resumed);
      final s = source(interval: const Duration(milliseconds: 80));
      var updates = 0;
      final sub = s.updates.listen((_) => updates++);
      counterAnswers.add(raw(5000, local(20, 8), 10 * _hour));
      await s.readDays();
      for (var i = 1; i <= 5; i++) {
        sink!.success(raw(5000 + i * 10, local(20, 8, i), 10 * _hour + i * _minute));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(updates, 1);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(updates, 2);
      await sub.cancel();
      goTo(AppLifecycleState.paused);
    });

    test('forget deja de escuchar', () async {
      goTo(AppLifecycleState.resumed);
      final s = source();
      counterAnswers.add(raw(5000, local(20, 8), 10 * _hour));
      await s.readDays();
      await s.forget();
      expect(s.watching, isFalse);
      expect(cancels, 1);
      goTo(AppLifecycleState.paused);
    });
  });

  group('con el estado de la app', () {
    late Directory tmp;
    late AndroidStepSource android;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('infyter_android_steps');
      Store.rescueDirectory = '${tmp.path}/data_rescue';
      MediaStore.directory = '${tmp.path}/media';
      ProgressReminder.instance.enabled = false;
      Store.instance.debugReset();
      await Store.instance.init();
      android = source();
      fit.stepSource = android;
      fit.resetAllData();
      fit.stepsOn = true;
    });

    tearDown(() async {
      fit.saveAndExit();
      fit.stepSource = createStepSource();
      Store.instance.debugReset();
      Store.rescueDirectory = null;
      MediaStore.directory = null;
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    test('despues de restaurar una copia vieja, la lectura siguiente vuelve a subir el dia', () async {
      counterAnswers.add(raw(5000, local(20, 8), 10 * _hour));
      await fit.refreshSteps();
      counterAnswers.add(raw(7000, local(20, 9), 11 * _hour));
      await fit.refreshSteps();
      expect(fit.steps, {'2026-11-20': 2000});
      expect(fit.stepsFrom, {'2026-11-20': 8 * 60});
      final old = fit.backupJson()
        ..['steps'] = {'2026-11-20': 50}
        ..['stepsFrom'] = <String, int>{};
      counterAnswers.add(raw(7000, local(20, 9, 5), 11 * _hour + 5 * _minute));
      expect(fit.importJson(jsonEncode(old)), isTrue);
      expect(fit.steps, {'2026-11-20': 50});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await fit.refreshSteps();
      expect(fit.steps, {'2026-11-20': 2000});
      expect(fit.stepsFrom, {'2026-11-20': 8 * 60});
    });

    test('una copia de otro telefono con mas pasos gana sin sumarse', () async {
      counterAnswers.add(raw(5000, local(20, 8), 10 * _hour));
      await fit.refreshSteps();
      fit.steps['2026-11-20'] = 9000;
      counterAnswers.add(raw(6000, local(20, 9), 11 * _hour));
      await fit.refreshSteps();
      expect(fit.steps['2026-11-20'], 9000);
    });

    test('borrar todos los datos borra el ancla', () async {
      counterAnswers.add(raw(5000, local(20, 8), 10 * _hour));
      await fit.refreshSteps();
      expect(await savedAnchor(), isNotNull);
      fit.resetAllData();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await savedAnchor(), isNull);
      expect(calls, contains(StepChannel.forget));
    });
  });

  group('en la app abierta', () {
    late FakeStepSource fake;

    setUp(() async {
      Store.instance.debugReset();
      await Store.instance.init();
      ProgressReminder.instance.enabled = false;
      updateGate = UpdateGate(source: () async => const UpdateCheck(UpdateReason.equal));
      fake = FakeStepSource();
      fit.stepSource = fake;
      fit.resetAllData();
      fit.onboarded = true;
      fit.stepsOn = true;
      await fit.refreshSteps();
      goTo(AppLifecycleState.resumed);
    });

    tearDown(() {
      goTo(AppLifecycleState.paused);
      fit.resetAllData();
      fit.stepSource = createStepSource();
      updateGate = UpdateGate();
      Store.instance.debugReset();
    });

    testWidgets('un aviso de pasos nuevos de la fuente vuelve a leer, y deja de hacerlo al cerrar la app', (
      tester,
    ) async {
      await tester.pumpWidget(const InfyterApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final before = fake.reads;
      fake.days = [const StepDayReading('2026-11-20', 1234)];
      fake.updatesController.add(null);
      await tester.pump(const Duration(milliseconds: 100));
      expect(fake.reads, before + 1);
      expect(fit.steps['2026-11-20'], 1234);
      await tester.pumpWidget(const SizedBox());
      fake.updatesController.add(null);
      await tester.pump(const Duration(milliseconds: 100));
      expect(fake.reads, before + 1);
      fit.persistNow();
    });
  });
}
