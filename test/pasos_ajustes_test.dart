import 'dart:ui' show Tristate;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/app/infyter_app.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/services/step_source.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:infyter/widgets/steps_card.dart';
import 'package:infyter/widgets/ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'letra_grande_util.dart';

const _ajustesDelSistema = MethodChannel('com.spencerccf.app_settings/methods');

const _ciclo = [
  AppLifecycleState.detached,
  AppLifecycleState.resumed,
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];

String _hoy() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

FakeStepSource _preparar({
  bool disponible = true,
  bool activado = false,
  StepPermission permiso = StepPermission.notDetermined,
  StepPermission respuesta = StepPermission.granted,
}) {
  final fuente = FakeStepSource()
    ..available = disponible
    ..permissionValue = permiso
    ..requestResult = respuesta
    ..days = [StepDayReading(_hoy(), 6412)];
  fit.stepSource = fuente;
  fit.stepsOn = activado;
  fit.stepsAskedAt = activado ? 1 : null;
  fit.stepsStatus = StepsStatus.unread;
  fit.stepGoal = kDefaultStepGoal;
  fit.steps.clear();
  fit.stepsFrom.clear();
  StepsCardPref.hidden.value = false;
  fit.route = 'preferences';
  return fuente;
}

Future<void> _pasar(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _abrir(WidgetTester tester) async {
  await tester.pumpWidget(const InfyterApp());
  await _pasar(tester, 12);
  await tester.ensureVisible(find.text(t.countSteps));
  await _pasar(tester, 3);
}

Future<void> _cerrar(WidgetTester tester) async {
  fit.saveAndExit();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await _pasar(tester, 2);
  await tester.tap(f);
  await _pasar(tester);
}

Future<void> _irYVolver(WidgetTester tester) async {
  final binding = tester.binding;
  void ir(AppLifecycleState destino) {
    var i = _ciclo.indexOf(binding.lifecycleState ?? AppLifecycleState.resumed);
    final fin = _ciclo.indexOf(destino);
    while (i != fin) {
      i += i < fin ? 1 : -1;
      binding.handleAppLifecycleStateChanged(_ciclo[i]);
    }
  }

  ir(AppLifecycleState.paused);
  await _pasar(tester, 2);
  ir(AppLifecycleState.resumed);
  await _pasar(tester);
}

bool _hay(String texto) => find.text(texto).evaluate().isNotEmpty;

bool _hayBoton(String texto) => find.text(titleCase(texto)).evaluate().isNotEmpty;

void main() {
  setUpAll(cargarNunito);
  late List<String> llamadas;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fit.saveAndExit();
    fit.onboarded = true;
    fit.startCountdown = false;
    fit.setLanguage('es');
    llamadas = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _ajustesDelSistema,
      (call) async {
        llamadas.add(call.method);
        return null;
      },
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_ajustesDelSistema, null);
    fit.saveAndExit();
    fit.startCountdown = true;
    fit.stepSource = const UnavailableStepSource();
    fit.stepsStatus = StepsStatus.off;
    fit.stepsOn = false;
    fit.stepsAskedAt = null;
    fit.stepGoal = kDefaultStepGoal;
    fit.steps.clear();
    fit.stepsFrom.clear();
    StepsCardPref.hidden.value = false;
  });

  testWidgets('conceder: el interruptor explica, pide el permiso tras Continuar y muestra la meta', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    final fuente = _preparar();
    await _abrir(tester);
    final metaAntes = _hay(t.stepGoal);
    await _tocar(tester, find.text(t.countSteps));
    final explica = _hay(t.stepsContinue);
    final sinPedir = fuente.permissionValue;
    await tester.tap(find.text(t.stepsContinue));
    await _pasar(tester);
    final activado = fit.stepsOn;
    final estado = fit.stepsStatus;
    final meta = _hay(t.stepGoal);
    final abrirAjustes = _hayBoton(t.openSettings);
    final pasos = fit.steps[_hoy()];
    await _cerrar(tester);
    expect(metaAntes, isFalse);
    expect(explica, isTrue);
    expect(sinPedir, StepPermission.notDetermined);
    expect(activado, isTrue);
    expect(estado, StepsStatus.counting);
    expect(meta, isTrue);
    expect(abrirAjustes, isFalse);
    expect(pasos, 6412);
  });

  testWidgets('cerrar la explicacion sin Continuar no activa ni pide nada', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    final fuente = _preparar();
    await _abrir(tester);
    await _tocar(tester, find.text(t.countSteps));
    await tester.tapAt(const Offset(180, 20));
    await _pasar(tester);
    final activado = fit.stepsOn;
    await _cerrar(tester);
    expect(activado, isFalse);
    expect(fuente.permissionValue, StepPermission.notDetermined);
  });

  testWidgets('negar una vez: queda Activar para volver a pedir, sin Abrir ajustes', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    final fuente = _preparar(respuesta: StepPermission.notDetermined);
    await _abrir(tester);
    await _tocar(tester, find.text(t.countSteps));
    await tester.tap(find.text(t.stepsContinue));
    await _pasar(tester);
    final estado = fit.stepsStatus;
    final aviso = _hay(t.stepsNeedsPermission);
    final abrirAjustes = _hayBoton(t.openSettings);
    final meta = _hay(t.stepGoal);
    fuente.requestResult = StepPermission.granted;
    final boton = _hayBoton(t.stepsAllow);
    await _tocar(tester, find.text(titleCase(t.stepsAllow)));
    await tester.tap(find.text(t.stepsContinue));
    await _pasar(tester);
    final despues = fit.stepsStatus;
    final avisoDespues = _hay(t.stepsNeedsPermission);
    await _cerrar(tester);
    expect(estado, StepsStatus.needsPermission);
    expect(aviso, isTrue);
    expect(boton, isTrue);
    expect(abrirAjustes, isFalse);
    expect(meta, isTrue);
    expect(despues, StepsStatus.counting);
    expect(avisoDespues, isFalse);
  });

  testWidgets('negar para siempre: Abrir ajustes abre el sistema y al volver con permiso cuenta', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    final fuente = _preparar(respuesta: StepPermission.denied);
    await _abrir(tester);
    await _tocar(tester, find.text(t.countSteps));
    await tester.tap(find.text(t.stepsContinue));
    await _pasar(tester);
    final estado = fit.stepsStatus;
    final aviso = _hay(t.stepsDeniedBody);
    await _tocar(tester, find.text(titleCase(t.openSettings)));
    final abrio = List.of(llamadas);
    fuente.permissionValue = StepPermission.granted;
    await _irYVolver(tester);
    final despues = fit.stepsStatus;
    final abrirAjustes = _hayBoton(t.openSettings);
    await _cerrar(tester);
    expect(estado, StepsStatus.denied);
    expect(aviso, isTrue);
    expect(abrio, isNotEmpty);
    expect(despues, StepsStatus.counting);
    expect(abrirAjustes, isFalse);
  });

  testWidgets('negar para siempre en iPhone: el aviso nombra Movimiento y forma física', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      _preparar(respuesta: StepPermission.denied);
      await _abrir(tester);
      await _tocar(tester, find.text(t.countSteps));
      await tester.tap(find.text(t.stepsContinue));
      await _pasar(tester);
      final ios = _hay(t.stepsDeniedBodyIos);
      final android = _hay(t.stepsDeniedBody);
      await _cerrar(tester);
      expect(t.stepsDeniedBodyIos, contains('Movimiento y forma física'));
      expect(ios, isTrue);
      expect(android, isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('revocar desde el sistema: al volver a la app aparece Abrir ajustes', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    final fuente = _preparar(activado: true, permiso: StepPermission.granted);
    await _abrir(tester);
    final antes = fit.stepsStatus;
    final abrirAntes = _hayBoton(t.openSettings);
    fuente.permissionValue = StepPermission.denied;
    await _irYVolver(tester);
    final despues = fit.stepsStatus;
    final abrirDespues = _hayBoton(t.openSettings);
    final activado = fit.stepsOn;
    await _cerrar(tester);
    expect(antes, StepsStatus.counting);
    expect(abrirAntes, isFalse);
    expect(despues, StepsStatus.denied);
    expect(abrirDespues, isTrue);
    expect(activado, isTrue);
  });

  testWidgets('apagar deja de contar, borra el ancla y conserva el historial', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    final fuente = _preparar(activado: true, permiso: StepPermission.granted);
    await _abrir(tester);
    final contando = fit.stepsStatus;
    await _tocar(tester, find.text(t.countSteps));
    final explica = _hay(t.stepsContinue);
    final activado = fit.stepsOn;
    final estado = fit.stepsStatus;
    final meta = _hay(t.stepGoal);
    final historial = fit.steps[_hoy()];
    await _cerrar(tester);
    expect(contando, StepsStatus.counting);
    expect(explica, isFalse);
    expect(activado, isFalse);
    expect(estado, StepsStatus.off);
    expect(fuente.stopped, 1);
    expect(fuente.forgotten, 0);
    expect(meta, isFalse);
    expect(historial, 6412);
  });

  testWidgets('sin sensor: dice que no esta disponible y no ofrece interruptor ni meta', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    final fuente = _preparar(disponible: false);
    await _abrir(tester);
    final aviso = _hay(t.stepsUnavailable);
    final pista = _hay(t.stepsSettingsHint);
    final meta = _hay(t.stepGoal);
    await tester.tap(find.text(t.countSteps));
    await _pasar(tester);
    final explica = _hay(t.stepsContinue);
    await _cerrar(tester);
    expect(aviso, isTrue);
    expect(pista, isFalse);
    expect(meta, isFalse);
    expect(explica, isFalse);
    expect(fuente.permissionValue, StepPermission.notDetermined);
  });

  testWidgets('sin sensor y con el conteo encendido por una copia: se puede apagar y no se vuelve a encender', (
    tester,
  ) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    final fuente = _preparar(disponible: false, activado: true);
    await _abrir(tester);
    final estado = fit.stepsStatus;
    final aviso = _hay(t.stepsUnavailable);
    final interruptor = find.byType(TinySwitch).evaluate().length;
    await _tocar(tester, find.text(t.countSteps));
    final apagado = !fit.stepsOn;
    final paro = fuente.stopped;
    final interruptorDespues = find.byType(TinySwitch).evaluate().length;
    await tester.tap(find.text(t.countSteps));
    await _pasar(tester);
    final explica = _hay(t.stepsContinue);
    final sigueApagado = !fit.stepsOn;
    await _cerrar(tester);
    expect(estado, StepsStatus.unavailable);
    expect(aviso, isTrue);
    expect(apagado, isTrue);
    expect(paro, 1);
    expect(interruptorDespues, interruptor - 1);
    expect(explica, isFalse);
    expect(sigueApagado, isTrue);
  });

  testWidgets('sin sensor la fila se anuncia como no disponible y no ofrece tocar', (tester) async {
    final semantica = tester.ensureSemantics();
    usarPantalla(tester, ancho: 360, alto: 780);
    _preparar(disponible: false);
    await _abrir(tester);
    final datos = find.semantics.byLabel(t.countSteps).evaluate().single.getSemanticsData();
    await _cerrar(tester);
    semantica.dispose();
    expect(datos.value, t.stepsUnavailable);
    expect(datos.hasAction(SemanticsAction.tap), isFalse);
    expect(datos.flagsCollection.isToggled, Tristate.none);
  });

  testWidgets('la meta diaria abre la hoja de la tarjeta y cambia de a 500', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    _preparar(activado: true, permiso: StepPermission.granted);
    await _abrir(tester);
    await _tocar(tester, find.text(t.stepGoal));
    final hoja = find.byType(StepperControl).evaluate().isNotEmpty;
    await tester.tap(find.descendant(of: find.byType(StepperControl).last, matching: find.text('+')));
    await _pasar(tester);
    await tester.tap(find.text(titleCase(t.done)).last);
    await _pasar(tester);
    final meta = fit.stepGoal;
    final fila = _hay('8.500 pasos');
    await _cerrar(tester);
    expect(hoja, isTrue);
    expect(meta, 8500);
    expect(fila, isTrue);
  });

  for (final idioma in const ['es', 'en']) {
    testWidgets('los controles de pasos en Ajustes tienen nombre, accion y 48 dp en $idioma', (tester) async {
      final semantica = tester.ensureSemantics();
      usarPantalla(tester, ancho: 360, alto: 780);
      fit.setLanguage(idioma);
      _preparar(activado: true, permiso: StepPermission.denied);
      await _abrir(tester);
      await tester.ensureVisible(find.text(t.stepGoal));
      await _pasar(tester, 3);
      SemanticsData datos(FinderBase<SemanticsNode> f) => f.evaluate().single.getSemanticsData();
      final interruptor = find.semantics.byLabel(t.countSteps);
      final meta = find.semantics.byLabel(t.stepGoal);
      final abrir = find.semantics.byLabel(t.openSettings);
      final dInterruptor = datos(interruptor);
      final dMeta = datos(meta);
      final dAbrir = datos(abrir);
      final tamanos = [
        tester.getSize(find.bySemanticsLabel(t.countSteps)),
        tester.getSize(find.bySemanticsLabel(t.stepGoal)),
        tester.getSize(find.bySemanticsLabel(t.openSettings)),
      ];
      await _cerrar(tester);
      usarPantalla(tester, ancho: 360, alto: 780);
      _preparar(activado: true, permiso: StepPermission.notDetermined);
      await _abrir(tester);
      await tester.ensureVisible(find.text(t.stepGoal));
      await _pasar(tester, 3);
      final dPermitir = datos(find.semantics.byLabel(t.stepsAllow));
      tamanos.add(tester.getSize(find.bySemanticsLabel(t.stepsAllow)));
      await _cerrar(tester);
      semantica.dispose();
      expect(dPermitir.hasAction(SemanticsAction.tap), isTrue);
      expect(dPermitir.flagsCollection.isButton, isTrue);
      expect(dInterruptor.flagsCollection.isToggled, Tristate.isTrue);
      expect(dInterruptor.hasAction(SemanticsAction.tap), isTrue);
      expect(dMeta.hasAction(SemanticsAction.tap), isTrue);
      expect(dMeta.flagsCollection.isButton, isTrue);
      expect(dMeta.value, isNotEmpty);
      expect(dMeta.hint, t.stepsChangeGoal);
      expect(dAbrir.hasAction(SemanticsAction.tap), isTrue);
      expect(dAbrir.flagsCollection.isButton, isTrue);
      for (final s in tamanos) {
        expect(s.height, greaterThanOrEqualTo(48));
        expect(s.width, greaterThanOrEqualTo(48));
      }
    });
  }
}
