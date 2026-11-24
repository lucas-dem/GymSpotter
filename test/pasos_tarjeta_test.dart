import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/app/infyter_app.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/services/step_source.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:infyter/widgets/steps_card.dart';
import 'package:infyter/widgets/charts.dart';
import 'package:infyter/widgets/svg_icon.dart';
import 'package:infyter/widgets/ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'letra_grande_util.dart';

String _hoy() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

FakeStepSource _preparar({
  bool activado = true,
  StepPermission permiso = StepPermission.granted,
  int? pasos,
  int? pidioEn,
  bool oculta = false,
}) {
  final fuente = FakeStepSource()
    ..permissionValue = permiso
    ..days = [if (pasos != null) StepDayReading(_hoy(), pasos)];
  fit.stepSource = fuente;
  fit.stepsOn = activado;
  fit.stepsAskedAt = pidioEn;
  fit.stepsStatus = StepsStatus.unread;
  fit.stepGoal = kDefaultStepGoal;
  fit.steps.clear();
  fit.stepsFrom.clear();
  StepsCardPref.hidden.value = oculta;
  fit.route = 'home';
  return fuente;
}

Future<void> _abrir(WidgetTester tester) async {
  await tester.pumpWidget(const InfyterApp());
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _pasar(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _cerrar(WidgetTester tester) async {
  fit.saveAndExit();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

int _tildes() =>
    find.descendant(of: find.byType(StepsCard), matching: find.byType(SvgPathIcon)).evaluate().length;

void main() {
  setUpAll(cargarNunito);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fit.saveAndExit();
    fit.onboarded = true;
    fit.startCountdown = false;
    fit.setLanguage('es');
  });
  tearDown(() {
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

  testWidgets('meta cumplida: el aro lleva el tilde; contando, no', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    _preparar(pasos: 9876);
    await _abrir(tester);
    final conTilde = _tildes();
    await _cerrar(tester);
    _preparar(pasos: 6412);
    await _abrir(tester);
    final sinTilde = _tildes();
    await _cerrar(tester);
    expect(conTilde, greaterThan(sinTilde));
  });

  testWidgets('Activar abre la explicacion y el permiso se pide solo tras Continuar', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    final fuente = _preparar(activado: false, permiso: StepPermission.notDetermined);
    await _abrir(tester);
    await tester.tap(find.text(t.stepsEnable));
    await _pasar(tester);
    expect(find.text(t.stepsContinue), findsOneWidget);
    expect(fuente.permissionValue, StepPermission.notDetermined);
    expect(fit.stepsOn, isFalse);
    await tester.tap(find.text(t.stepsContinue));
    await _pasar(tester);
    final activado = fit.stepsOn;
    final estado = fit.stepsStatus;
    await _cerrar(tester);
    expect(activado, isTrue);
    expect(estado, StepsStatus.counting);
    expect(fuente.permissionValue, StepPermission.granted);
  });

  testWidgets('cerrar la explicacion deslizando no pide el permiso', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    final fuente = _preparar(activado: false, permiso: StepPermission.notDetermined);
    await _abrir(tester);
    await tester.tap(find.text(t.stepsEnable));
    await _pasar(tester);
    await tester.fling(find.text(t.stepsContinue), const Offset(0, 600), 2000);
    await _pasar(tester);
    final visible = find.text(t.stepsContinue).evaluate().isNotEmpty;
    final activado = fit.stepsOn;
    await _cerrar(tester);
    expect(visible, isFalse);
    expect(activado, isFalse);
    expect(fuente.permissionValue, StepPermission.notDetermined);
  });

  testWidgets('la x de la invitacion oculta la tarjeta y se guarda', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    _preparar(activado: false, permiso: StepPermission.notDetermined);
    await _abrir(tester);
    await tester.tap(find.bySemanticsLabel(t.stepsHide));
    await _pasar(tester);
    final visible = find.text(t.stepsEnableTitle).evaluate().isNotEmpty;
    final prefs = await SharedPreferences.getInstance();
    await _cerrar(tester);
    expect(visible, isFalse);
    expect(StepsCardPref.hidden.value, isTrue);
    expect(prefs.getBool('infyter_steps_card_hidden_v1'), isTrue);
  });

  testWidgets('con el permiso pendiente tras un rechazo, la x apaga el conteo y avisa a la fuente', (
    tester,
  ) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    final fuente = _preparar(permiso: StepPermission.notDetermined);
    await _abrir(tester);
    expect(find.text(t.stepsEnableTitle), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(t.stepsHide));
    await _pasar(tester);
    final activado = fit.stepsOn;
    final visible = find.text(t.stepsEnableTitle).evaluate().isNotEmpty;
    await _cerrar(tester);
    expect(activado, isFalse);
    expect(visible, isFalse);
    expect(fuente.stopped, 1);
  });

  testWidgets('con el permiso pendiente y un pedido anterior, sigue ofreciendo Activar con la x', (
    tester,
  ) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    _preparar(permiso: StepPermission.notDetermined, pidioEn: 1);
    await _abrir(tester);
    final activar = find.text(t.stepsEnable).evaluate().isNotEmpty;
    final negado = find.text(t.stepsDeniedTitle).evaluate().isNotEmpty;
    final cruz = find.bySemanticsLabel(t.stepsHide).evaluate().isNotEmpty;
    await _cerrar(tester);
    expect(activar, isTrue);
    expect(negado, isFalse);
    expect(cruz, isTrue);
  });

  testWidgets('antes de leer la fuente la tarjeta no dibuja nada', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    _preparar(activado: false, permiso: StepPermission.notDetermined);
    await tester.pumpWidget(const InfyterApp());
    final alPrincipio = find.text(t.stepsEnableTitle).evaluate().isNotEmpty;
    await _cerrar(tester);
    expect(alPrincipio, isFalse);
  });

  testWidgets('negado en iPhone: la tarjeta nombra Movimiento y forma física', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      _preparar(permiso: StepPermission.denied);
      await _abrir(tester);
      final ios = find.text(t.stepsDeniedBodyIos).evaluate().isNotEmpty;
      final android = find.text(t.stepsDeniedBody).evaluate().isNotEmpty;
      await _cerrar(tester);
      expect(ios, isTrue);
      expect(android, isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('tocar el aro abre la hoja de meta', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    _preparar(pasos: 6412);
    await _abrir(tester);
    await tester.tap(find.byType(GoalRing).last);
    await _pasar(tester);
    final hoja = find.byType(StepperControl).evaluate().isNotEmpty;
    await _cerrar(tester);
    expect(hoja, isTrue);
  });

  testWidgets('tocar la nota abre la ayuda', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    _preparar(pasos: 6412);
    await _abrir(tester);
    await tester.tap(find.textContaining('75 kg'));
    await _pasar(tester);
    final ayuda = find.text(t.stepsHelpTitle).evaluate().isNotEmpty;
    await _cerrar(tester);
    expect(ayuda, isTrue);
  });

  test('setStepGoal normaliza y notifica; el mismo valor no hace nada', () {
    _preparar();
    var avisos = 0;
    void oyente() => avisos++;
    fit.addListener(oyente);
    addTearDown(() => fit.removeListener(oyente));
    fit.setStepGoal(10260);
    expect(fit.stepGoal, 10500);
    expect(avisos, 1);
    fit.setStepGoal(10500);
    expect(avisos, 1);
    fit.setStepGoal(999999);
    expect(fit.stepGoal, kMaxStepGoal);
  });

  test('disableSteps apaga, avisa a la fuente y conserva el historial', () async {
    final fuente = _preparar(pasos: 500);
    await fit.refreshSteps();
    expect(fit.stepsStatus, StepsStatus.counting);
    fit.disableSteps();
    await fit.refreshSteps();
    expect(fit.stepsOn, isFalse);
    expect(fit.stepsStatus, StepsStatus.off);
    expect(fuente.stopped, 1);
    expect(fit.steps[_hoy()], 500);
    fit.disableSteps();
    expect(fuente.stopped, 1);
  });

  test('enableSteps y borrar los datos reinician la preferencia de ocultar', () async {
    _preparar(activado: false, permiso: StepPermission.notDetermined);
    StepsCardPref.hidden.value = true;
    await fit.enableSteps();
    expect(StepsCardPref.hidden.value, isFalse);
    StepsCardPref.hidden.value = true;
    fit.resetAllData();
    expect(StepsCardPref.hidden.value, isFalse);
  });

  testWidgets('las zonas tocables de la tarjeta miden 48 dp y tienen nombre', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    final semantica = tester.ensureSemantics();
    _preparar(pasos: 6412);
    await _abrir(tester);
    final nota = tester.getSize(find.bySemanticsLabel(RegExp('75 kg')));
    final aro = tester.getSize(find.bySemanticsLabel(RegExp(t.stepGoal)));
    await _cerrar(tester);
    usarPantalla(tester, ancho: 360, alto: 780);
    _preparar(activado: false, permiso: StepPermission.notDetermined);
    await _abrir(tester);
    final cruz = tester.getSize(find.bySemanticsLabel(t.stepsHide));
    await _cerrar(tester);
    semantica.dispose();
    expect(nota.height, greaterThanOrEqualTo(48));
    expect(aro.shortestSide, greaterThanOrEqualTo(48));
    expect(cruz.width, greaterThanOrEqualTo(48));
    expect(cruz.height, greaterThanOrEqualTo(48));
  });

  for (final idioma in const ['es', 'en']) {
    testWidgets(
      'cada accion de la tarjeta tiene nombre, pista, tocar y 48 dp, sin lecturas duplicadas en $idioma',
      (tester) async {
        final semantica = tester.ensureSemantics();
        final miles = idioma == 'es' ? '6.412' : '6,412';
        final escenarios = <String, void Function()>{
          'contando': () => _preparar(pasos: 6412),
          'meta cumplida': () => _preparar(pasos: 9876),
          'sin activar': () => _preparar(activado: false, permiso: StepPermission.notDetermined),
          'negado': () => _preparar(permiso: StepPermission.denied),
        };
        for (final MapEntry(key: nombre, value: preparar) in escenarios.entries) {
          usarPantalla(tester, ancho: 360, alto: 780);
          fit.setLanguage(idioma);
          preparar();
          await _abrir(tester);
          final caja = tester.getRect(find.byType(StepsCard));
          final nodos = <({String etiqueta, String valor, String pista, bool tocar, Rect rect})>[];
          void visitar(SemanticsNode nodo, Matrix4 acumulada) {
            final m = acumulada.clone();
            if (nodo.transform != null) m.multiply(nodo.transform!);
            final rect = MatrixUtils.transformRect(m, nodo.rect);
            final datos = nodo.getSemanticsData();
            if (caja.contains(rect.center)) {
              nodos.add((
                etiqueta: datos.label,
                valor: datos.value,
                pista: datos.hint,
                tocar: datos.hasAction(SemanticsAction.tap),
                rect: rect,
              ));
            }
            nodo.visitChildren((hijo) {
              visitar(hijo, m);
              return true;
            });
          }

          visitar(
            tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
            Matrix4.diagonal3Values(1 / tester.view.devicePixelRatio, 1 / tester.view.devicePixelRatio, 1),
          );
          final acciones = [
            for (final n in nodos)
              if (n.tocar) n,
          ];
          final donde = '$idioma $nombre';
          expect(acciones, isNotEmpty, reason: donde);
          for (final n in acciones) {
            expect(n.etiqueta.trim(), isNotEmpty, reason: '$donde ${n.rect}');
            final minimo = {t.stepsEnable, t.openSettings}.contains(n.etiqueta) ? 44.0 : 48.0;
            expect(
              n.rect.width >= minimo - 0.5 && n.rect.height >= minimo - 0.5,
              isTrue,
              reason: '$donde "${n.etiqueta}" ${n.rect}',
            );
          }
          expect({for (final n in acciones) n.etiqueta}.length, acciones.length, reason: donde);
          if (nombre == 'contando' || nombre == 'meta cumplida') {
            final progreso = acciones.where((n) => n.etiqueta == t.stepsToday);
            expect(
              progreso,
              hasLength(1),
              reason: '$donde: la etiqueta de Progreso es exactamente "${t.stepsToday}"',
            );
            expect(progreso.single.pista, t.stepsOpenProgress, reason: donde);
            final aro = acciones.singleWhere((n) => n.etiqueta == t.stepGoal);
            expect(aro.pista, t.stepsChangeGoal, reason: donde);
            expect(aro.valor.contains(t.stepsGoalReached), nombre == 'meta cumplida', reason: donde);
            final nota = acciones.where((n) => n.pista == t.stepsShowEstimate);
            expect(nota, hasLength(1), reason: donde);
          }
          if (nombre == 'contando') {
            final lectura = [for (final n in nodos) '${n.etiqueta} ${n.valor} ${n.pista}'].join(' | ');
            expect(
              miles.allMatches(lectura).length,
              1,
              reason: '$donde: el numero de pasos se lee una sola vez en "$lectura"',
            );
          }
          await _cerrar(tester);
        }
        semantica.dispose();
      },
    );
  }

  test('borrar los datos deja la fuente sin sensor como no disponible tras releerla', () async {
    fit.stepSource = const UnavailableStepSource();
    fit.stepsOn = true;
    fit.resetAllData();
    expect(fit.stepsStatus, StepsStatus.unread);
    await fit.refreshSteps();
    expect(fit.stepsStatus, StepsStatus.unavailable);
  });

  test('borrar los datos con sensor deja la tarjeta en "off" tras releer', () async {
    final fuente = _preparar(permiso: StepPermission.notDetermined);
    fit.resetAllData();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fit.stepsStatus, StepsStatus.off);
    expect(fuente.forgotten, 1);
  });

  testWidgets('el aro y la nota ofrecen la accion tocar y abren su hoja', (tester) async {
    usarPantalla(tester, ancho: 360, alto: 780);
    final semantica = tester.ensureSemantics();
    _preparar(pasos: 6412);
    await _abrir(tester);
    final aro = find.semantics.byLabel(RegExp(t.stepGoal));
    expect(aro.evaluate().single.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.performAction(aro, SemanticsAction.tap);
    await _pasar(tester);
    final meta = find.byType(StepperControl).evaluate().isNotEmpty;
    await tester.tapAt(const Offset(180, 20));
    await _pasar(tester);
    final nota = find.semantics.byLabel(RegExp('75 kg'));
    expect(nota.evaluate().single.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.performAction(nota, SemanticsAction.tap);
    await _pasar(tester);
    final ayuda = find.text(t.stepsHelpTitle).evaluate().isNotEmpty;
    await _cerrar(tester);
    semantica.dispose();
    expect(meta, isTrue);
    expect(ayuda, isTrue);
  });

  for (final (ancho, escala) in const [(360.0, 1.0), (360.0, 1.5), (360.0, 2.0), (320.0, 1.3), (320.0, 2.0)]) {
    for (final pasos in const [6412, 9876]) {
      testWidgets('la tarjeta $pasos se ajusta a su contenido y el aro no queda solo a ${ancho.toInt()} dp x$escala', (
        tester,
      ) async {
        usarPantalla(tester, ancho: ancho, alto: 780, escala: escala);
        _preparar(pasos: pasos);
        await _abrir(tester);
        Finder enTarjeta(Finder f) => find.descendant(of: find.byType(StepsCard), matching: f);
        final tarjeta = tester.getRect(enTarjeta(find.byType(SoftCard)));
        final aro = tester.getRect(enTarjeta(find.byType(GoalRing)));
        expect(enTarjeta(find.text(t.stepsGoalUnit('8.000'))), findsOneWidget);
        final nota = tester.getRect(enTarjeta(find.textContaining('75 kg')));
        final textos = enTarjeta(find.byType(RichText)).evaluate().map((e) {
          final caja = e.renderObject! as RenderBox;
          return caja.localToGlobal(Offset.zero) & caja.size;
        }).toList();
        final alLado = textos.any((r) => r.left >= aro.right && r.top < aro.bottom && r.bottom > aro.top);
        final arriba = textos
            .where((r) => r.bottom <= nota.top)
            .fold(aro.bottom, (double fondo, r) => r.bottom > fondo ? r.bottom : fondo);
        await _cerrar(tester);
        expect(alLado, isTrue, reason: 'el aro queda solo en su renglon');
        expect(nota.top - arriba, lessThanOrEqualTo(16), reason: 'hueco entre los numeros y la nota');
        expect(tarjeta.bottom - nota.bottom, lessThanOrEqualTo(22), reason: 'hueco debajo de la nota');
      });
    }
  }
}
