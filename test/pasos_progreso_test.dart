import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/app/app_shell.dart';
import 'package:infyter/app/infyter_app.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/models/workout.dart';
import 'package:infyter/screens/progress_screen.dart';
import 'package:infyter/services/step_source.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:infyter/state/steps_range.dart';
import 'package:infyter/widgets/entrance.dart';
import 'package:infyter/widgets/steps_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'letra_grande_util.dart';

DateTime _dia(int atras) {
  final h = DateTime.now();
  return DateTime(h.year, h.month, h.day - atras);
}

StepsPeriod _periodo(
  StepsSpan span, {
  required DateTime hoy,
  Map<String, int> pasos = const {},
  Map<String, int> desde = const {},
  List<LoggedSession> sesiones = const [],
  List<BodyweightEntry> peso = const [],
  int meta = 8000,
}) => stepsPeriod(
  span: span,
  today: hoy,
  steps: pasos,
  stepsFrom: desde,
  goal: meta,
  sessions: sesiones,
  bodyweight: peso,
  profileWeightKg: 75,
);

LoggedSession _sesion(DateTime dia, int seg) => LoggedSession(dia.add(const Duration(hours: 10)), seg, []);

void _preparar({bool activado = true, Map<int, int> pasos = const {}, Map<int, int> desde = const {}}) {
  fit.stepSource = FakeStepSource();
  fit.stepsOn = activado;
  fit.stepGoal = kDefaultStepGoal;
  fit.steps.clear();
  fit.stepsFrom.clear();
  fit.sessions.clear();
  for (final e in pasos.entries) {
    fit.steps[stepsDayKey(_dia(e.key))] = e.value;
  }
  for (final e in desde.entries) {
    fit.stepsFrom[stepsDayKey(_dia(e.key))] = e.value;
  }
  fit.route = 'progress';
}

Future<void> _abrir(WidgetTester tester) async {
  await tester.pumpWidget(const InfyterApp());
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _pasar(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _cerrar(WidgetTester tester) async {
  fit.saveAndExit();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

Finder _rotulo(String texto, Type tarjeta) =>
    find.descendant(of: find.byType(tarjeta), matching: find.text(texto));

Finder _rueda(String texto) => find.byWidgetPredicate((w) => w is RollIn && w.text == texto);

Future<void> _verBloques(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(StepsProgressCard));
  await _pasar(tester);
}

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
    fit.bgPattern = 'dynamic';
    fit.startCountdown = true;
    fit.stepSource = const UnavailableStepSource();
    fit.stepsStatus = StepsStatus.off;
    fit.stepsOn = false;
    fit.stepGoal = kDefaultStepGoal;
    fit.steps.clear();
    fit.stepsFrom.clear();
    fit.sessions.clear();
    fit.bodyweight.clear();
  });

  group('calculo del periodo', () {
    final hoy = DateTime(2026, 11, 20);

    test('7D: promedio de los dias con datos, huecos como hueco y dias parciales', () {
      final p = _periodo(
        StepsSpan.week,
        hoy: hoy,
        pasos: {'2026-11-20': 6000, '2026-11-19': 10000, '2026-11-17': 8000},
        desde: {'2026-11-17': 872},
      );
      expect(p.bars, hasLength(7));
      expect(p.bars.first.date, DateTime(2026, 11, 14));
      expect(p.bars.last.value, 6000);
      expect(p.bars.map((b) => b.value == null).where((x) => x), hasLength(4));
      expect(p.bars[3].partial, isTrue);
      expect(p.bars.last.partial, isFalse);
      expect(p.average, 8000);
      expect(p.daysWithData, 3);
      expect(p.goalDays, 2);
      expect(p.stepsKcal, 600);
      expect(p.workoutKcal, 0);
    });

    test('un dia sin lectura nunca cuenta como 0 en el promedio ni en la meta', () {
      final p = _periodo(StepsSpan.week, hoy: hoy, pasos: {'2026-11-20': 5000});
      expect(p.average, 5000);
      expect(p.daysWithData, 1);
      expect(p.goalDays, 0);
      final vacio = _periodo(StepsSpan.week, hoy: hoy);
      expect(vacio.average, isNull);
      expect(vacio.totalKcal, 0);
    });

    test('un dia con 0 pasos leidos es dato, no hueco', () {
      final p = _periodo(StepsSpan.week, hoy: hoy, pasos: {'2026-11-20': 0});
      expect(p.bars.last.value, 0);
      expect(p.daysWithData, 1);
      expect(p.average, 0);
    });

    test(
      'kcal de entrenamientos: tope de 3 h, sin duracion cuenta 0 y lo de afuera del periodo no entra',
      () {
        final p = _periodo(
          StepsSpan.week,
          hoy: hoy,
          sesiones: [
            _sesion(DateTime(2026, 11, 19), 3600),
            _sesion(DateTime(2026, 11, 18), 5 * 3600),
            _sesion(DateTime(2026, 11, 17), 0),
            _sesion(DateTime(2026, 11, 10), 3600),
          ],
        );
        expect(p.workoutKcal, 190 + 560);
        final mes = _periodo(StepsSpan.month, hoy: hoy, sesiones: [_sesion(DateTime(2026, 11, 10), 3600)]);
        expect(mes.workoutKcal, 190);
      },
    );

    test('el peso de cada dia es el ultimo guardado hasta ese dia', () {
      final p = _periodo(
        StepsSpan.week,
        hoy: hoy,
        pasos: {'2026-11-20': 6000, '2026-11-16': 6000},
        peso: [BodyweightEntry(DateTime(2026, 11, 18), 90)],
      );
      expect(p.stepsKcal, 150 + 180);
    });

    test('30D: 30 barras que terminan hoy', () {
      final p = _periodo(StepsSpan.month, hoy: hoy, pasos: {'2026-10-22': 1000});
      expect(p.bars, hasLength(30));
      expect(p.bars.first.date, DateTime(2026, 10, 22));
      expect(p.bars.first.value, 1000);
      expect(p.bars.last.date, hoy);
    });

    test('12M: promedio diario por mes, meses sin datos como hueco', () {
      final p = _periodo(
        StepsSpan.year,
        hoy: hoy,
        pasos: {'2026-11-20': 6000, '2026-11-02': 10000, '2026-10-05': 4000, '2025-11-30': 9000},
      );
      expect(p.bars, hasLength(12));
      expect(p.bars.first.date, DateTime(2025, 12, 1));
      expect(p.bars.last.value, 8000);
      expect(p.bars[10].value, 4000);
      expect(p.bars[5].value, isNull);
      expect(p.daysWithData, 3);
      expect(p.average, 6667);
    });

    test('12M cruza el cambio de anio', () {
      final p = _periodo(StepsSpan.year, hoy: DateTime(2026, 1, 15));
      expect(p.bars.first.date, DateTime(2025, 2, 1));
      expect(p.bars.last.date, DateTime(2026, 1, 1));
    });
  });

  group('pantalla', () {
    testWidgets('sin pasos activados ni datos, Progreso no muestra nada nuevo', (tester) async {
      usarPantalla(tester, ancho: 360, alto: 780);
      _preparar(activado: false);
      await _abrir(tester);
      final titulo = find.text(t.stepsTitle.toUpperCase());
      final kcal = find.text(t.kcalTitle.toUpperCase());
      final hay = titulo.evaluate().isNotEmpty || kcal.evaluate().isNotEmpty;
      final bloques = find.byType(StepsProgressCard).evaluate().length;
      await _cerrar(tester);
      expect(hay, isFalse);
      expect(bloques, 0);
    });

    testWidgets('con pasos activados aparecen los dos bloques y 30D y 12M cambian el periodo', (
      tester,
    ) async {
      usarPantalla(tester, ancho: 360, alto: 780);
      _preparar(pasos: {0: 5000, 1: 9000, 20: 3000});
      fit.sessions.add(_sesion(_dia(1), 3600));
      await _abrir(tester);
      await _verBloques(tester);
      expect(find.text(t.stepsTitle.toUpperCase()), findsOneWidget);
      expect(find.text(t.kcalTitle.toUpperCase()), findsOneWidget);
      expect(_rueda('7.000'), findsOneWidget);
      expect(find.text(t.stepsGoalDays('8.000', 1, 2)), findsOneWidget);
      expect(find.text(t.stepsLegendGaps), findsOneWidget);
      expect(find.textContaining(t.stepsLegendPartial), findsNothing);
      await tester.tap(_rotulo(t.days30, StepsProgressCard));
      await _pasar(tester);
      expect(_rueda('5.667'), findsOneWidget);
      expect(find.text(t.stepsGoalDays('8.000', 1, 3)), findsOneWidget);
      await tester.tap(_rotulo(t.months12, StepsProgressCard));
      await _pasar(tester);
      expect(find.text(t.stepsGoalDays('8.000', 1, 3)), findsOneWidget);
      await _cerrar(tester);
    });

    testWidgets('el bloque de kcal separa pasos y entrenamientos y lleva la ayuda', (tester) async {
      usarPantalla(tester, ancho: 360, alto: 780);
      _preparar(pasos: {0: 6000});
      fit.sessions.add(_sesion(_dia(1), 3600));
      await _abrir(tester);
      await _verBloques(tester);
      expect(_rueda('≈ 340'), findsOneWidget);
      expect(find.text('≈ 150 kcal'), findsOneWidget);
      expect(find.text('≈ 190 kcal'), findsOneWidget);
      expect(find.text(t.stepsByWalking), findsOneWidget);
      expect(find.text(t.kcalByWorkouts), findsWidgets);
      await tester.tap(find.text(t.kcalWeightPerDay(fit.weightLabel(fit.profile.weightKg))));
      await _pasar(tester);
      expect(find.text(t.stepsHelpTitle), findsOneWidget);
      await _cerrar(tester);
    });

    testWidgets('la hoja del dia suma los pasos, las kcal y desde cuando cuenta', (tester) async {
      usarPantalla(tester, ancho: 360, alto: 780);
      _preparar(pasos: {0: 6412, 1: 3000}, desde: {0: 872});
      await _abrir(tester);
      showDaySheet(tester.element(find.byType(AppShell)), _dia(0));
      await _pasar(tester);
      expect(find.text('6.412 pasos · ≈ 160 kcal'), findsOneWidget);
      expect(find.text(t.stepsCountingSince('14:32')), findsOneWidget);
      await _cerrar(tester);
      _preparar(pasos: {0: 6412, 1: 3000}, desde: {0: 872});
      await _abrir(tester);
      showDaySheet(tester.element(find.byType(AppShell)), _dia(1));
      await _pasar(tester);
      expect(find.text('3.000 pasos · ≈ 80 kcal'), findsOneWidget);
      expect(find.textContaining(t.stepsCountingSince('')), findsNothing);
      await _cerrar(tester);
      _preparar(pasos: {0: 6412});
      await _abrir(tester);
      showDaySheet(tester.element(find.byType(AppShell)), _dia(3));
      await _pasar(tester);
      expect(find.textContaining('pasos ·'), findsNothing);
      await _cerrar(tester);
    });

    testWidgets('con dias parciales la leyenda de barras claras aparece y el plural cuenta un dia', (
      tester,
    ) async {
      usarPantalla(tester, ancho: 360, alto: 780);
      _preparar(pasos: {0: 9000}, desde: {0: 872});
      await _abrir(tester);
      await _verBloques(tester);
      expect(find.textContaining(t.stepsLegendPartial), findsOneWidget);
      expect(find.text(t.stepsGoalDays('8.000', 1, 1)), findsOneWidget);
      expect(t.stepsGoalDays('8.000', 1, 1), isNot(contains('1 días')));
      await _cerrar(tester);
    });

    testWidgets('con el conteo apagado y datos guardados los bloques siguen apareciendo', (tester) async {
      usarPantalla(tester, ancho: 360, alto: 780);
      _preparar(activado: false, pasos: {1: 5000});
      await _abrir(tester);
      await _verBloques(tester);
      expect(find.text(t.stepsTitle.toUpperCase()), findsOneWidget);
      expect(find.text(t.kcalTitle.toUpperCase()), findsOneWidget);
      await _cerrar(tester);
    });

    testWidgets('el eje del grafico no se corta con maximos grandes no redondos', (tester) async {
      for (final idioma in const ['es', 'pt', 'ru', 'en']) {
        usarPantalla(tester, ancho: 320, alto: 711, escala: 2.0);
        tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
          boldText: true,
        );
        addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
        fit.setLanguage(idioma);
        _preparar(pasos: {0: 45678, 1: 12345});
        await _abrir(tester);
        await _verBloques(tester);
        final cortados = lineasExcedidas(tester, [find.byType(StepsProgressCard)]);
        await _cerrar(tester);
        expect(cortados, isEmpty, reason: idioma);
      }
    });

    testWidgets('el grafico no entra en la semantica', (tester) async {
      final semantica = tester.ensureSemantics();
      usarPantalla(tester, ancho: 360, alto: 780);
      _preparar(pasos: {0: 5000, 1: 9000});
      await _abrir(tester);
      await _verBloques(tester);
      final grafico = tester.getRect(find.byType(StepsBarChart));
      final etiquetas = <String>[];
      void visitar(SemanticsNode nodo, Matrix4 acumulada) {
        final m = acumulada.clone();
        if (nodo.transform != null) m.multiply(nodo.transform!);
        final rect = MatrixUtils.transformRect(m, nodo.rect);
        if (grafico.contains(rect.center)) etiquetas.add(nodo.getSemanticsData().label);
        nodo.visitChildren((hijo) {
          visitar(hijo, m);
          return true;
        });
      }

      visitar(
        tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!,
        Matrix4.diagonal3Values(1 / tester.view.devicePixelRatio, 1 / tester.view.devicePixelRatio, 1),
      );
      expect(
        find.ancestor(of: find.byType(StepsBarChart), matching: find.byType(ExcludeSemantics)),
        findsWidgets,
      );
      expect(etiquetas.where((e) => e.trim().isNotEmpty), isEmpty, reason: '$etiquetas');
      await _cerrar(tester);
      semantica.dispose();
    });

    testWidgets('la hoja del dia muestra el mismo total de kcal que Inicio', (tester) async {
      usarPantalla(tester, ancho: 360, alto: 780);
      _preparar(pasos: {0: 6000});
      fit.sessions.add(_sesion(_dia(0), 3600));
      fit.route = 'home';
      await _abrir(tester);
      final hoja = find.byWidgetPredicate((w) => w is RollIn && w.text.startsWith('≈ '));
      final inicio = (hoja.evaluate().first.widget as RollIn).text;
      expect(inicio, '≈ 340');
      showDaySheet(tester.element(find.byType(AppShell)), _dia(0));
      await _pasar(tester);
      expect(find.text('6.000 pasos · $inicio kcal'), findsOneWidget);
      await _cerrar(tester);
    });

    testWidgets('ir y volver a Progreso rapido no deja dos bloques con la misma clave', (tester) async {
      usarPantalla(tester, ancho: 360, alto: 780);
      _preparar(pasos: {0: 6412, 1: 3000});
      await _abrir(tester);
      for (var i = 0; i < 3; i++) {
        fit.goHome();
        await tester.pump(const Duration(milliseconds: 100));
        fit.openProgressOnSteps();
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _pasar(tester);
      final error = tester.takeException();
      await _cerrar(tester);
      expect(error, isNull);
    });

    testWidgets('un doble toque en la tarjeta no deja un pedido pendiente para la proxima vez', (
      tester,
    ) async {
      usarPantalla(tester, ancho: 360, alto: 780);
      _preparar(pasos: {0: 6412, 1: 3000});
      fit.sessions.add(_sesion(_dia(1), 3600));
      fit.route = 'home';
      await _abrir(tester);
      final tarjeta = find.text(t.stepsToday.toUpperCase());
      await tester.tap(tarjeta);
      await tester.tap(tarjeta, warnIfMissed: false);
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(fit.route, 'progress');
      expect(fit.takeFocusSteps(), isFalse);
      fit.goHome();
      await _pasar(tester);
      fit.goProgress();
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final posicion = tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
      final error = tester.takeException();
      await _cerrar(tester);
      expect(error, isNull);
      expect(posicion, 0);
    });

    testWidgets('tocar la tarjeta de Inicio lleva a Progreso y baja hasta el bloque de pasos', (
      tester,
    ) async {
      usarPantalla(tester, ancho: 360, alto: 780);
      _preparar(pasos: {0: 6412, 1: 3000});
      fit.sessions.add(_sesion(_dia(1), 3600));
      fit.route = 'home';
      await _abrir(tester);
      await tester.tap(find.text(t.stepsToday.toUpperCase()));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(fit.route, 'progress');
      final posicion = tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;
      final caja = tester.getRect(find.byType(StepsProgressCard));
      await _cerrar(tester);
      expect(posicion, greaterThan(0));
      expect(caja.top, greaterThanOrEqualTo(0));
      expect(caja.top, lessThan(400));
      expect(caja.bottom, lessThanOrEqualTo(780));
    });

    for (final idioma in const ['es', 'en']) {
      testWidgets('cada accion tiene nombre y toque, mide 48 dp y no se lee dos veces en $idioma', (
        tester,
      ) async {
        final semantica = tester.ensureSemantics();
        usarPantalla(tester, ancho: 360, alto: 780);
        fit.setLanguage(idioma);
        _preparar(pasos: {0: 5000, 1: 9000});
        await _abrir(tester);
        await _verBloques(tester);
        await tester.ensureVisible(find.byType(KcalProgressCard));
        await _pasar(tester);
        final cajas = [
          tester.getRect(find.byType(StepsProgressCard)),
          tester.getRect(find.byType(KcalProgressCard)),
        ];
        final nodos =
            <({String etiqueta, String valor, String pista, bool tocar, bool elegido, Rect rect})>[];
        void visitar(SemanticsNode nodo, Matrix4 acumulada) {
          final m = acumulada.clone();
          if (nodo.transform != null) m.multiply(nodo.transform!);
          final rect = MatrixUtils.transformRect(m, nodo.rect);
          final datos = nodo.getSemanticsData();
          if (cajas.any((c) => c.contains(rect.center))) {
            nodos.add((
              etiqueta: datos.label,
              valor: datos.value,
              pista: datos.hint,
              tocar: datos.hasAction(SemanticsAction.tap),
              elegido: datos.flagsCollection.isSelected == ui.Tristate.isTrue,
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
        for (final n in acciones) {
          expect(n.etiqueta.trim(), isNotEmpty, reason: '${n.rect}');
          expect(n.rect.width >= 47.5 && n.rect.height >= 47.5, isTrue, reason: '"${n.etiqueta}" ${n.rect}');
        }
        final etiquetas = [for (final n in acciones) n.etiqueta];
        for (final e in [t.days7, t.days30, t.months12]) {
          expect(etiquetas.where((x) => x == e), hasLength(2), reason: '$idioma $e');
        }
        expect(acciones.where((n) => n.etiqueta == t.days7 && n.elegido), hasLength(2));
        expect(acciones.where((n) => n.etiqueta == t.days30 && n.elegido), isEmpty);
        expect(acciones.where((n) => n.pista == t.stepsShowEstimate), hasLength(1));
        final lectura = [for (final n in nodos) '${n.etiqueta} ${n.valor}'].join(' | ');
        final miles = idioma == 'es' ? '7.000' : '7,000';
        expect(miles.allMatches(lectura).length, 1, reason: lectura);
        await _cerrar(tester);
        semantica.dispose();
      });
    }
  });

  group('letra grande', () {
    final estados = <String, void Function()>{
      'completo': () =>
          _preparar(pasos: {0: 6412, 1: 9876, 2: 4000, 5: 12000, 9: 7000, 40: 8000}, desde: {0: 872}),
      'meta ancha': () => _preparar(pasos: {0: 45678, 1: 30000, 3: 1200}),
      'sin datos': () => _preparar(),
    };
    for (final idioma in const ['es', 'en', 'de', 'fr', 'pt', 'ru']) {
      for (final escala in const [1.0, 1.3, 1.5, 2.0]) {
        for (final MapEntry(key: nombre, value: preparar) in estados.entries) {
          testWidgets('progreso con pasos ($nombre) en los tres periodos a 320 dp, escala $escala, $idioma', (
            tester,
          ) async {
            usarPantalla(tester, ancho: 320, alto: 711, escala: escala);
            fit.setLanguage(idioma);
            preparar();
            fit.sessions.add(_sesion(_dia(1), 3725));
            final fallas = <String>[];
            fallas.addAll(
              await conErrores(() async {
                await _abrir(tester);
                await _verBloques(tester);
              }),
            );
            for (var periodo = 0; periodo < 3; periodo++) {
              if (periodo > 0) {
                final rotulo = periodo == 1 ? t.days30 : t.months12;
                fallas.addAll(
                  await conErrores(() async {
                    for (final tarjeta in const [StepsProgressCard, KcalProgressCard]) {
                      await tester.ensureVisible(_rotulo(rotulo, tarjeta));
                      await tester.tap(_rotulo(rotulo, tarjeta));
                      await _pasar(tester);
                    }
                  }),
                );
              }
              fallas.addAll([
                for (final c in [
                  ...problemasDeTexto(tester, idioma).where(
                    (c) =>
                        !(idioma == 'fr' &&
                            escala == 2.0 &&
                            c.contains('partida') &&
                            c.contains(t.setupTitle.substring(0, 10))),
                  ),
                  ...lineasExcedidas(tester, [find.byType(StepsProgressCard), find.byType(KcalProgressCard)]),
                ])
                  'periodo $periodo: $c',
              ]);
            }
            await _cerrar(tester);
            expect(fallas, isEmpty);
          });
        }
      }
    }
  });
}
