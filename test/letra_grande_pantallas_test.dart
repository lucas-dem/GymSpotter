import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/app/app_shell.dart';
import 'package:infyter/app/infyter_app.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/models/workout.dart';
import 'package:infyter/screens/progress_screen.dart';
import 'package:infyter/screens/session_screen.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:infyter/wear/wear_app.dart';
import 'package:infyter/widgets/dialogs.dart';
import 'package:infyter/widgets/medal_shelf.dart';
import 'package:infyter/widgets/routine_folder.dart';
import 'package:infyter/widgets/ruler_picker.dart';
import 'package:infyter/widgets/ui_kit.dart';

import 'letra_grande_util.dart';

const _pantallas = [(360.0, 780.0), (411.0, 914.0)];
const _escalas = [1.0, 1.3, 1.5, 2.0];
const _idiomas = String.fromEnvironment('IDIOMAS', defaultValue: 'es,en');
const _listarPuntos = bool.fromEnvironment('LISTAR_PUNTOS');

void _datos() {
  fit.saveAndExit();
  fit.onboarded = true;
  fit.startCountdown = false;
  fit.routines.clear();
  fit.sessions
    ..clear()
    ..add(
      LoggedSession(DateTime.now().subtract(const Duration(days: 2)), 3725, [
        LoggedExercise('EIeI8Vf', 'Barbell Bench Press', 'chest', [LoggedSet(10, 102.5), LoggedSet(8, 105)]),
        LoggedExercise('0br45wL', 'Push-up', 'chest', [LoggedSet(20, 0)]),
      ]),
    );
}

String _rutina() {
  final id = fit.createRoutine('Pecho y espalda pesado');
  for (final e in fit.allExercises.take(4)) {
    fit.toggleRoutineExercise(id, e.id);
  }
  return id;
}

void _entreno({bool descanso = false}) {
  _rutina();
  fit.startRoutine(fit.routines.first);
  fit.setSessionReps(0, 0, 12);
  fit.setSessionWeight(0, 0, 102.5);
  if (descanso) fit.toggleSet(0, 0);
}

Future<List<String>> _revisar(
  WidgetTester tester,
  Widget app,
  String que, {
  String idioma = 'es',
  void Function(BuildContext)? abrir,
}) async {
  final errores = await conErrores(() async {
    await tester.pumpWidget(app);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    if (abrir != null) {
      abrir(tester.element(find.byType(AppShell)));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }
  });
  if (_listarPuntos) {
    for (final p in textoConPuntos(tester)) {
      debugPrint('PUNTOS $que: $p');
    }
  }
  return [for (final e in errores) '$que: $e', for (final c in problemasDeTexto(tester, idioma)) '$que: $c'];
}

Future<void> _cerrar(WidgetTester tester) async {
  fit.saveAndExit();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  setUpAll(cargarNunito);
  setUp(_datos);
  tearDown(() {
    fit.saveAndExit();
    fit.routines.clear();
    fit.startCountdown = true;
    fit.setLanguage('es');
  });

  final casos = <String, void Function()>{
    for (final r in const [
      'home',
      'progress',
      'exercises',
      'exercise-detail',
      'settings',
      'preferences',
      'routines',
      'tools',
      'train',
      'notes',
      'note-edit',
      'measures',
      'timeline',
      'moments',
      'awards',
      'places',
      'ai-plan',
    ])
      r: () => fit.route = r,
    'routine-edit': () {
      fit.openRoutine(fit.createRoutine('Pierna'));
      fit.toggleRoutineExercise(fit.activeRoutineId!, 'EIeI8Vf');
      fit.route = 'routine-edit';
    },
    'routines-folder': () {
      _rutina();
      fit.route = 'routines';
    },
    'onboarding': () => fit.onboarded = false,
    'session': _entreno,
    'session-descanso': () => _entreno(descanso: true),
    'session-fin': () {
      _entreno(descanso: true);
      fit.finishSession();
    },
    'compare': () => fit.route = 'compare',
    for (final id in const ['rm', 'bmi', 'cal', 'bf', 'plate', 'warmup'])
      'tools-detail-$id': () {
        fit.activeToolId = id;
        fit.route = 'tools-detail';
      },
  };

  final hojas = <String, (void Function(), void Function(BuildContext))>{
    'regla': (
      _entreno,
      (c) => askRuler(c, title: 'Peso', value: 102.5, min: 0, max: 300, step: 2.5, unit: 'kg'),
    ),
    'agregar-al-entreno': (_entreno, showAddToSessionSheet),
    'medalla': (() => fit.route = 'awards', (c) => showMedalSheet(c, AwardId.values.first)),
    'dia': (() => fit.route = 'progress', (c) => showDaySheet(c, fit.sessions.first.date)),
    'confirmar': (
      () => fit.route = 'home',
      (c) => askConfirm(
        c,
        title: 'Quitar ejercicio',
        body: 'Se borran sus series de este entreno.',
        confirmLabel: 'Quitar',
      ),
    ),
  };

  for (final idioma in _idiomas.split(',')) {
    for (final (ancho, alto) in _pantallas) {
      for (final escala in _escalas) {
        for (final MapEntry(key: nombre, value: preparar) in casos.entries) {
          testWidgets('$nombre fits at ${ancho.toInt()} dp with text scale $escala in $idioma', (
            tester,
          ) async {
            usarPantalla(tester, ancho: ancho, alto: alto, escala: escala);
            fit.setLanguage(idioma);
            preparar();
            final fallas = await _revisar(tester, const InfyterApp(), nombre, idioma: idioma);
            await _cerrar(tester);
            for (final f in fallas) {
              debugPrint('FALLA $idioma ${ancho.toInt()}dp x$escala $f');
            }
            expect(fallas, isEmpty);
          });
        }
      }
    }
  }

  for (final idioma in _idiomas.split(',')) {
    for (final (ancho, alto) in _pantallas) {
      for (final escala in _escalas) {
        for (final MapEntry(key: nombre, value: (preparar, abrir)) in hojas.entries) {
          testWidgets('the $nombre sheet fits at ${ancho.toInt()} dp with text scale $escala in $idioma', (
            tester,
          ) async {
            usarPantalla(tester, ancho: ancho, alto: alto, escala: escala);
            fit.setLanguage(idioma);
            preparar();
            final fallas = await _revisar(tester, const InfyterApp(), 'hoja $nombre', idioma: idioma, abrir: abrir);
            await _cerrar(tester);
            for (final f in fallas) {
              debugPrint('FALLA $idioma ${ancho.toInt()}dp x$escala $f');
            }
            expect(fallas, isEmpty);
          });
        }
      }
    }
  }

  for (final idioma in _idiomas.split(',')) {
    for (final (ancho, alto) in _pantallas) {
      for (final escala in _escalas) {
        testWidgets('the routine card keeps its text inside at ${ancho.toInt()} dp, scale $escala, $idioma', (
          tester,
        ) async {
          usarPantalla(tester, ancho: ancho, alto: alto, escala: escala);
          fit.setLanguage(idioma);
          _rutina();
          fit.createRoutine('Vacía');
          final pierna = fit.createRoutine('Pierna');
          fit.toggleRoutineExercise(pierna, fit.allExercises.last.id);
          // At 1.0 a grouped count keeps its old one line (with "…" when long), so it gets a short group there.
          final grupo = escala > 1 ? 'Bloque Lunes' : 'A';
          final hombros = fit.createRoutine('Hombros');
          fit.toggleRoutineExercise(hombros, fit.allExercises.first.id);
          fit.setRoutineGroup(hombros, grupo);
          final espalda = fit.createRoutine('Espalda');
          for (final e in fit.allExercises.take(12)) {
            fit.toggleRoutineExercise(espalda, e.id);
          }
          fit.setRoutineGroup(espalda, grupo);
          fit.route = 'routines';
          final fallas = <String>[];
          final tarjetas = <Rect>[];
          await tester.pumpWidget(const InfyterApp());
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 200));
          }
          for (var k = 0; k < tester.widgetList(find.byType(RoutineFolder)).length; k++) {
            final tarjeta = find.byType(RoutineFolder).at(k);
            fallas.addAll(
              await conErrores(() async {
                await tester.ensureVisible(tarjeta);
                for (var i = 0; i < 4; i++) {
                  await tester.pump(const Duration(milliseconds: 200));
                }
              }),
            );
            final caja = tester.getRect(tarjeta);
            tarjetas.add(caja);
            final cuenta = tester.getRect(
              find
                  .descendant(
                    of: tarjeta,
                    matching: find.byWidgetPredicate(
                      (w) => w is Text && [0, 1, 4, 12].any((k) => w.data?.endsWith(t.exerciseCount(k)) ?? false),
                    ),
                  )
                  .last,
            );
            final boton = find.descendant(
              of: tarjeta,
              matching: find.byWidgetPredicate(
                (w) => w is Text && (w.data == titleCase(t.startWorkout) || w.data == t.addExercises),
              ),
            );
            final empezar = tester.getRect(boton);
            if (cuenta.bottom > empezar.top) fallas.add('tarjeta $k: la cuenta baja hasta "Empezar"');
            if (!caja.contains(empezar.bottomCenter - const Offset(0, 1))) fallas.add('tarjeta $k: "Empezar" afuera');
            if (escala == 1.0 && caja.height != 196) fallas.add('tarjeta $k: a 1.0 mide ${caja.height}, no 196');
            fallas.addAll(problemasDeTexto(tester, idioma));
          }
          final juntas = [for (final e in find.byType(RoutineFolder).evaluate()) tester.getRect(find.byWidget(e.widget))];
          await _cerrar(tester);
          for (var a = 0; a < juntas.length; a++) {
            for (var b = a + 1; b < juntas.length; b++) {
              final fila = (juntas[a].top - juntas[b].top).abs() < 1;
              if (fila && (juntas[a].height - juntas[b].height).abs() > 0.5) {
                fallas.add('tarjetas $a y $b lado a lado con distinto alto');
              }
            }
          }
          for (final f in fallas) {
            debugPrint('FALLA $idioma ${ancho.toInt()}dp x$escala tarjeta: $f');
          }
          expect(tarjetas, hasLength(5));
          expect(fallas, isEmpty);
        });
      }
    }
  }

  double dibujado(RenderParagraph r) =>
      r.textScaler.scale(r.text.style!.fontSize!) *
      MatrixUtils.transformRect(r.getTransformTo(null), const Rect.fromLTWH(0, 0, 1, 1)).height;

  RenderParagraph parrafo(WidgetTester tester, bool Function(String) cumple) => tester.allRenderObjects
      .whereType<RenderParagraph>()
      .firstWhere((r) => r.attached && r.hasSize && cumple(r.text.toPlainText()));

  for (final idioma in _idiomas.split(',')) {
    for (final (ancho, alto) in _pantallas) {
      for (final escala in _escalas) {
        testWidgets('elapsed and next target are not smaller than their neighbours at ${ancho.toInt()} dp, '
            'scale $escala, $idioma', (tester) async {
          usarPantalla(tester, ancho: ancho, alto: alto, escala: escala);
          fit.setLanguage(idioma);
          _entreno();
          await _revisar(tester, const InfyterApp(), 'entreno', idioma: idioma);
          final id = fit.session!.exercises.first.id;
          final ultima = dibujado(parrafo(tester, (s) => s == fit.lastSummaryFor(id)));
          final siguiente = dibujado(parrafo(tester, (s) => s.startsWith(fit.nextTargetLabel(id)!)));
          await _cerrar(tester);
          _datos();
          _entreno(descanso: true);
          await _revisar(tester, const InfyterApp(), 'descanso', idioma: idioma);
          final transcurrido = dibujado(parrafo(tester, (s) => s == t.elapsedCaps.toUpperCase()));
          final series = dibujado(parrafo(tester, (s) => s == t.setsCaps.toUpperCase()));
          await _cerrar(tester);
          expect(
            siguiente,
            greaterThanOrEqualTo(0.99 * ultima),
            reason: 'SIGUIENTE $siguiente, ÚLTIMA $ultima',
          );
          expect(siguiente, greaterThanOrEqualTo(0.99 * 12 * escala), reason: 'SIGUIENTE achicado');
          if (escala > 1) {
            expect(
              transcurrido,
              greaterThanOrEqualTo(0.99 * series),
              reason: 'TRANSCURRIDO $transcurrido, SERIES $series',
            );
            expect(transcurrido, greaterThanOrEqualTo(0.99 * 9.5 * escala), reason: 'TRANSCURRIDO achicado');
          }
        });
      }
    }
  }

  for (final ancho in const [360.0, 411.0]) {
    testWidgets('at normal text size the muscle map title and its modes share one line at ${ancho.toInt()} dp', (
      tester,
    ) async {
      usarPantalla(tester, ancho: ancho, alto: 780);
      fit.setLanguage('es');
      fit.route = 'progress';
      await _revisar(tester, const InfyterApp(), 'progreso');
      await tester.scrollUntilVisible(find.text(t.muscleMap), 200, scrollable: find.byType(Scrollable).first);
      await tester.pump(const Duration(milliseconds: 400));
      final titulo = tester.getCenter(find.text(t.muscleMap));
      final modo = tester.getCenter(find.text(t.days7).first);
      expect((titulo.dy - modo.dy).abs(), lessThan(4), reason: 'como antes: el selector al lado del título');
      await _cerrar(tester);
    });
  }

  for (final idioma in _idiomas.split(',')) {
    for (final (ancho, alto) in _pantallas) {
      for (final escala in _escalas) {
        testWidgets('the four tab bar labels share one size at ${ancho.toInt()} dp, scale $escala, $idioma', (
          tester,
        ) async {
          usarPantalla(tester, ancho: ancho, alto: alto, escala: escala);
          fit.setLanguage(idioma);
          fit.route = 'home';
          final fallas = await _revisar(tester, const InfyterApp(), 'barra', idioma: idioma);
          final altos = <String, double>{};
          for (final label in [t.home, t.progress, t.exercises, t.profile]) {
            final r = tester
                .renderObjectList<RenderParagraph>(find.text(label))
                .reduce((a, b) => a.localToGlobal(Offset.zero).dy > b.localToGlobal(Offset.zero).dy ? a : b);
            final m = r.getTransformTo(null);
            altos[label] = r.textSize.height * MatrixUtils.transformRect(m, const Rect.fromLTWH(0, 0, 1, 1)).height;
          }
          await _cerrar(tester);
          final menor = altos.values.reduce(math.min), mayor = altos.values.reduce(math.max);
          expect(fallas, isEmpty);
          expect(mayor / menor, lessThan(1.01), reason: 'alto visible de cada rótulo: $altos');
        });
      }
    }
  }

  for (final idioma in _idiomas.split(',')) {
    for (final escala in _escalas) {
    testWidgets('the watch home and workout fit with text scale $escala in $idioma', (tester) async {
      tester.view.physicalSize = const Size(454, 454);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = escala;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      fit.setLanguage(idioma);
      final fallas = await _revisar(tester, const WearApp(), 'reloj inicio', idioma: idioma);
      _entreno(descanso: true);
      fallas.addAll(await _revisar(tester, const WearApp(), 'reloj entreno', idioma: idioma));
      await _cerrar(tester);
      for (final f in fallas) {
        debugPrint('FALLA $idioma 227dp x$escala $f');
      }
      expect(fallas, isEmpty);
    });
    }
  }
}
