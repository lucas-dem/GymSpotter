import 'package:flutter/material.dart';
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

String _hoy() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

FakeStepSource _preparar({
  bool salud = true,
  bool activado = true,
  StepPermission permiso = StepPermission.granted,
  int? pasos,
  String route = 'home',
}) {
  final fuente = (salud ? FakeHealthConnectStepSource() : FakeStepSource())
    ..permissionValue = permiso
    ..days = [if (pasos != null) StepDayReading(_hoy(), pasos)];
  fit.stepSource = fuente;
  fit.stepsOn = activado;
  fit.stepsAskedAt = activado ? 1 : null;
  fit.stepsStatus = StepsStatus.unread;
  fit.steps.clear();
  fit.stepsFrom.clear();
  StepsCardPref.hidden.value = false;
  fit.route = route;
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
}

Future<void> _cerrar(WidgetTester tester) async {
  fit.saveAndExit();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

Finder _enTarjeta(String texto) => find.descendant(of: find.byType(StepsCard), matching: find.text(texto));

bool _hay(String texto) => find.text(texto).evaluate().isNotEmpty;

void main() {
  setUpAll(cargarNunito);
  late List<String> sistema;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fit.saveAndExit();
    fit.onboarded = true;
    fit.startCountdown = false;
    fit.setLanguage('es');
    sistema = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _ajustesDelSistema,
      (call) async {
        sistema.add(call.method);
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

  testWidgets('permiso negado en la tarjeta: lo dice y "Abrir Health Connect" abre Health Connect', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    final fuente = _preparar(permiso: StepPermission.denied) as FakeHealthConnectStepSource;
    await _abrir(tester);
    final dice = _enTarjeta(t.stepsDeniedBodyHc).evaluate().length;
    final viejo = _hay(t.stepsDeniedBody);
    final boton = find.text(titleCase(t.openHealthConnect));
    final hayBoton = boton.evaluate().length;
    await tester.tap(boton);
    await _pasar(tester);
    final abiertas = fuente.opened;
    final ajustes = List.of(sistema);
    await _cerrar(tester);
    expect(dice, 1);
    expect(viejo, isFalse);
    expect(hayBoton, 1);
    expect(abiertas, 1);
    expect(ajustes, isEmpty, reason: 'no se mandan a los ajustes de la app si Health Connect abrio');
  });

  testWidgets('si Health Connect no abre, se abren los ajustes de la app', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    final fuente = _preparar(permiso: StepPermission.denied) as FakeHealthConnectStepSource;
    fuente.opens = false;
    await _abrir(tester);
    await tester.tap(find.text(titleCase(t.openHealthConnect)));
    await _pasar(tester);
    final ajustes = List.of(sistema);
    await _cerrar(tester);
    expect(fuente.opened, 1);
    expect(ajustes, hasLength(1));
  });

  testWidgets('con el sensor, el permiso negado sigue con "Abrir ajustes"', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    _preparar(salud: false, permiso: StepPermission.denied);
    await _abrir(tester);
    final viejo = find.text(titleCase(t.openSettings)).evaluate().length;
    final nuevo = _hay(titleCase(t.openHealthConnect));
    await _cerrar(tester);
    expect(viejo, 1);
    expect(nuevo, isFalse);
  });

  testWidgets('"desde las HH:MM" solo con el sensor: con Health Connect, el dia del cambio no lo muestra', (
    tester,
  ) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    final desde = t.stepsCountingSince('14:32');
    _preparar(salud: false, pasos: 900);
    fit.steps[_hoy()] = 1234;
    fit.stepsFrom[_hoy()] = 14 * 60 + 32;
    await _abrir(tester);
    final conSensor = _enTarjeta(desde).evaluate().length;
    await _cerrar(tester);
    _preparar(pasos: 900);
    fit.steps[_hoy()] = 1234;
    fit.stepsFrom[_hoy()] = 14 * 60 + 32;
    await _abrir(tester);
    final conSalud = _enTarjeta(desde).evaluate().length;
    final pasos = fit.steps[_hoy()];
    await _cerrar(tester);
    expect(conSensor, 1);
    expect(conSalud, 0);
    expect(pasos, 1234, reason: 'el dia guardado no baja');
  });

  testWidgets('la invitacion y la explicacion hablan de Health Connect', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    final fuente = _preparar(activado: false, permiso: StepPermission.notDetermined);
    fit.stepsAskedAt = null;
    await _abrir(tester);
    final invita = _enTarjeta(t.stepsEnableBodyHc).evaluate().length;
    await tester.tap(find.text(titleCase(t.stepsEnable)));
    await _pasar(tester);
    final explica = _hay(t.stepsPermissionBodyHc);
    final sensor = _hay(t.stepsPermissionBody);
    await _cerrar(tester);
    expect(invita, 1);
    expect(explica, isTrue);
    expect(sensor, isFalse);
    expect(fuente.permissionValue, StepPermission.notDetermined, reason: 'sin Continuar no se pide');
  });

  testWidgets('la ayuda de la tarjeta explica Health Connect y no la suma entre lecturas', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    _preparar(pasos: 6412);
    await _abrir(tester);
    showStepsHelp(tester.element(find.byType(StepsCard)));
    await _pasar(tester);
    final hc = _hay(t.stepsHcHint);
    final sensor = _hay(t.stepsAndroidHint);
    await _cerrar(tester);
    expect(hc, isTrue);
    expect(sensor, isFalse);
  });

  testWidgets('Ajustes: la nota nombra Health Connect y el permiso negado ofrece abrirlo', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    final fuente = _preparar(permiso: StepPermission.denied, route: 'preferences') as FakeHealthConnectStepSource;
    await _abrir(tester);
    await tester.ensureVisible(find.text(t.countSteps));
    await _pasar(tester, 3);
    final nota = _hay(t.stepsSettingsHintHc);
    final notaSensor = _hay(t.stepsSettingsHint);
    final dice = _hay(t.stepsDeniedBodyHc);
    final boton = find.text(titleCase(t.openHealthConnect));
    await tester.ensureVisible(boton);
    await _pasar(tester, 2);
    await tester.tap(boton);
    await _pasar(tester);
    final abiertas = fuente.opened;
    await _cerrar(tester);
    expect(nota, isTrue);
    expect(notaSensor, isFalse);
    expect(dice, isTrue);
    expect(abiertas, 1);
  });

  testWidgets('permiso negado y vuelto a dar en Health Connect: al volver a la app cuenta', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    final fuente = _preparar(permiso: StepPermission.denied, pasos: 3000);
    await _abrir(tester);
    final negado = fit.stepsStatus;
    fuente.permissionValue = StepPermission.granted;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _pasar(tester, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _pasar(tester);
    final estado = fit.stepsStatus;
    final pasos = fit.steps[_hoy()];
    await _cerrar(tester);
    expect(negado, StepsStatus.denied);
    expect(estado, StepsStatus.counting);
    expect(pasos, 3000);
  });
}
