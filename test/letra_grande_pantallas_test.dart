import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/app/app_shell.dart';
import 'package:infyter/app/infyter_app.dart';
import 'package:infyter/models/workout.dart';
import 'package:infyter/screens/progress_screen.dart';
import 'package:infyter/screens/session_screen.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:infyter/wear/wear_app.dart';
import 'package:infyter/widgets/dialogs.dart';
import 'package:infyter/widgets/medal_shelf.dart';
import 'package:infyter/widgets/ruler_picker.dart';

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

void _entreno({bool descanso = false}) {
  final id = fit.createRoutine('Pecho y espalda pesado');
  for (final e in fit.allExercises.take(4)) {
    fit.toggleRoutineExercise(id, e.id);
  }
  fit.startRoutine(fit.routines.first);
  fit.setSessionReps(0, 0, 12);
  fit.setSessionWeight(0, 0, 102.5);
  if (descanso) fit.toggleSet(0, 0);
}

Future<List<String>> _revisar(
  WidgetTester tester,
  Widget app,
  String que, {
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
  return [for (final e in errores) '$que: $e', for (final c in textoCortado(tester)) '$que: $c'];
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
            final fallas = await _revisar(tester, const InfyterApp(), nombre);
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
            final fallas = await _revisar(tester, const InfyterApp(), 'hoja $nombre', abrir: abrir);
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

  for (final escala in _escalas) {
    testWidgets('the watch home and workout fit with text scale $escala', (tester) async {
      tester.view.physicalSize = const Size(454, 454);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = escala;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final fallas = await _revisar(tester, const WearApp(), 'reloj inicio');
      _entreno(descanso: true);
      fallas.addAll(await _revisar(tester, const WearApp(), 'reloj entreno'));
      await _cerrar(tester);
      for (final f in fallas) {
        debugPrint('FALLA reloj x$escala $f');
      }
      expect(fallas, isEmpty);
    });
  }
}
