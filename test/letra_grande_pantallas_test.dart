import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:infyter/app/app_shell.dart';
import 'package:infyter/app/infyter_app.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/models/workout.dart';
import 'package:infyter/screens/home_screen.dart';
import 'package:infyter/screens/progress_export_sheet.dart';
import 'package:infyter/screens/progress_screen.dart';
import 'package:infyter/screens/session_screen.dart';
import 'package:infyter/services/step_source.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:infyter/wear/wear_app.dart';
import 'package:infyter/widgets/dialogs.dart';
import 'package:infyter/widgets/medal_shelf.dart';
import 'package:infyter/widgets/routine_folder.dart';
import 'package:infyter/widgets/steps_card.dart';
import 'package:infyter/widgets/steps_progress.dart';
import 'package:infyter/widgets/ruler_picker.dart';
import 'package:infyter/widgets/ui_kit.dart';

import 'letra_grande_util.dart';

const _pantallas = [(360.0, 780.0), (411.0, 914.0)];
const _estrecha = (320.0, 711.0);
const _escalas = [1.0, 1.3, 1.5, 2.0];
const _idiomas = String.fromEnvironment('IDIOMAS', defaultValue: 'es,en');
const _listarPuntos = bool.fromEnvironment('LISTAR_PUNTOS');

String _hoy() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

void _pasos({
  bool disponible = true,
  bool activado = true,
  StepPermission permiso = StepPermission.granted,
  int? pasos,
  int? desde,
  int meta = kDefaultStepGoal,
  bool oculta = false,
  bool salud = false,
}) {
  final fuente = (salud ? FakeHealthConnectStepSource() : FakeStepSource())
    ..available = disponible
    ..permissionValue = permiso
    ..days = [if (pasos != null) StepDayReading(_hoy(), pasos, fromMinute: desde)];
  fit.stepSource = fuente;
  fit.stepsOn = activado;
  fit.stepGoal = meta;
  StepsCardPref.hidden.value = oculta;
  fit.route = 'home';
}

String _clave(int atras) {
  final h = DateTime.now();
  final d = DateTime(h.year, h.month, h.day - atras);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

void _progresoPasos({bool activado = true, bool parcial = false, bool datos = true, int meta = kDefaultStepGoal}) {
  _pasos(activado: activado, meta: meta);
  fit.route = 'progress';
  if (!datos) return;
  fit.steps
    ..[_clave(0)] = parcial ? 1234 : 6412
    ..[_clave(1)] = 9876
    ..[_clave(2)] = 45678
    ..[_clave(5)] = 4000
    ..[_clave(12)] = 8000
    ..[_clave(40)] = 7000;
  if (parcial) fit.stepsFrom[_clave(0)] = 14 * 60 + 32;
}

void _ajustesPasos({
  bool disponible = true,
  bool activado = true,
  StepPermission permiso = StepPermission.granted,
  bool salud = false,
}) {
  _pasos(disponible: disponible, activado: activado, permiso: permiso, pasos: 6412, meta: 30000, salud: salud);
  fit.route = 'preferences';
}

void _sinPasos() {
  fit.stepSource = const UnavailableStepSource();
  fit.stepsStatus = StepsStatus.off;
  fit.stepsOn = false;
  fit.stepGoal = kDefaultStepGoal;
  fit.steps.clear();
  fit.stepsFrom.clear();
  StepsCardPref.hidden.value = false;
}

void _datos() {
  _sinPasos();
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
  Future<void> Function(WidgetTester)? luego,
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
    if (luego != null) {
      await luego(tester);
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
  return [
    for (final e in errores) '$que: $e',
    for (final c in problemasDeTexto(tester, idioma)) '$que: $c',
    if (que.startsWith('progress-pasos'))
      for (final c in lineasExcedidas(tester, [find.byType(StepsProgressCard), find.byType(KcalProgressCard)]))
        '$que: $c',
  ];
}

Future<void> _cerrar(WidgetTester tester) async {
  fit.saveAndExit();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

final _hoyFijo = DateTime(2026, 3, 15);

String _claveDe(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void _datosParaCompartir({required int diasAtras}) {
  final dia = _hoyFijo.subtract(Duration(days: diasAtras));
  fit.sessions
    ..clear()
    ..add(
      LoggedSession(dia.add(const Duration(hours: 18)), 3725, [
        LoggedExercise('EIeI8Vf', 'Barbell Bench Press', 'chest', [LoggedSet(10, 102.5), LoggedSet(8, 105)]),
      ]),
    );
  fit.steps[_claveDe(dia)] = 6412;
  fit.route = 'progress';
}

void _sinNadaParaCompartir() {
  fit.sessions.clear();
  fit.route = 'progress';
}

Future<void> _tocarHistoricoCompleto(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(TinySwitch));
  await tester.pump();
  await tester.tap(find.byType(TinySwitch));
}

Future<void> _tocarExportar(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(PrimaryButton));
  await tester.pump();
  await tester.tap(find.byType(PrimaryButton));
}

void main() {
  setUpAll(cargarNunito);
  setUp(_datos);
  tearDown(() {
    fit.saveAndExit();
    fit.routines.clear();
    fit.startCountdown = true;
    fit.setLanguage('es');
    _sinPasos();
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
    'home-pasos-sin-activar': () => _pasos(activado: false),
    'home-pasos-necesita-permiso': () => _pasos(permiso: StepPermission.notDetermined),
    'home-pasos-negado': () => _pasos(permiso: StepPermission.denied),
    'home-pasos-no-disponible': () => _pasos(disponible: false),
    'home-pasos-contando': () => _pasos(pasos: 6412),
    'home-pasos-parcial': () => _pasos(pasos: 1234, desde: 14 * 60 + 32),
    'home-pasos-meta': () => _pasos(pasos: 9876),
    'home-pasos-ancho': () => _pasos(pasos: 45678, meta: 30000),
    'home-pasos-sin-datos': () => _pasos(),
    'home-hc-sin-activar': () => _pasos(activado: false, salud: true),
    'home-hc-necesita-permiso': () => _pasos(permiso: StepPermission.notDetermined, salud: true),
    'home-hc-negado': () => _pasos(permiso: StepPermission.denied, salud: true),
    'home-hc-contando': () => _pasos(pasos: 6412, salud: true),
    'home-hc-dia-del-cambio': () {
      _pasos(pasos: 900, salud: true);
      fit.steps[_hoy()] = 1234;
      fit.stepsFrom[_hoy()] = 14 * 60 + 32;
    },
    'progress-pasos': _progresoPasos,
    'progress-pasos-parcial': () => _progresoPasos(parcial: true),
    'progress-pasos-meta-ancha': () => _progresoPasos(meta: 30000),
    'progress-pasos-vacio': () => _progresoPasos(datos: false),
    'progress-pasos-apagado': () => _progresoPasos(activado: false),
    'preferences-pasos-apagado': () => _ajustesPasos(activado: false),
    'preferences-pasos-contando': _ajustesPasos,
    'preferences-pasos-necesita-permiso': () => _ajustesPasos(permiso: StepPermission.notDetermined),
    'preferences-pasos-negado': () => _ajustesPasos(permiso: StepPermission.denied),
    'preferences-pasos-no-disponible': () => _ajustesPasos(disponible: false),
    'preferences-hc-contando': () => _ajustesPasos(salud: true),
    'preferences-hc-necesita-permiso': () => _ajustesPasos(permiso: StepPermission.notDetermined, salud: true),
    'preferences-hc-negado': () => _ajustesPasos(permiso: StepPermission.denied, salud: true),
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
    'pasos-explicacion': (() => _pasos(activado: false), (c) => showStepsExplanation(c)),
    'pasos-explicacion-hc': (() => _pasos(activado: false, salud: true), (c) => showStepsExplanation(c)),
    'pasos-ayuda-hc': (() => _pasos(pasos: 6412, salud: true), showStepsHelp),
    'pasos-meta': (() => _pasos(pasos: 6412), showStepGoalSheet),
    'pasos-ayuda': (() => _pasos(pasos: 6412), showStepsHelp),
    'dia-pasos': (
      () => _progresoPasos(parcial: true),
      (c) => showDaySheet(c, DateTime.now()),
    ),
    'pasos-meta-ancha': (() => _pasos(pasos: 45678, meta: 30000), showStepGoalSheet),
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
    for (final escala in _escalas) {
      for (final nombre in const [
        'home',
        'session',
        'session-descanso',
        'home-pasos-sin-activar',
        'home-pasos-necesita-permiso',
        'home-pasos-sin-datos',
        'home-pasos-negado',
        'home-pasos-contando',
        'home-pasos-parcial',
        'home-pasos-meta',
        'home-pasos-ancho',
        'home-hc-sin-activar',
        'home-hc-necesita-permiso',
        'home-hc-negado',
        'home-hc-contando',
        'home-hc-dia-del-cambio',
        'progress',
        'progress-pasos',
        'progress-pasos-parcial',
        'progress-pasos-meta-ancha',
        'progress-pasos-vacio',
        'progress-pasos-apagado',
      ]) {
        testWidgets('$nombre fits at 320 dp with text scale $escala in $idioma', (tester) async {
          final (ancho, alto) = _estrecha;
          usarPantalla(tester, ancho: ancho, alto: alto, escala: escala);
          fit.setLanguage(idioma);
          casos[nombre]!();
          final fallas = await _revisar(tester, const InfyterApp(), nombre, idioma: idioma);
          await _cerrar(tester);
          for (final f in fallas) {
            debugPrint('FALLA $idioma 320dp x$escala $f');
          }
          expect(fallas, isEmpty);
        });
      }
    }
  }

  for (final idioma in _idiomas.split(',')) {
    for (final escala in _escalas) {
      for (final nombre in const [
        'preferences',
        'preferences-pasos-apagado',
        'preferences-pasos-contando',
        'preferences-pasos-necesita-permiso',
        'preferences-pasos-negado',
        'preferences-pasos-no-disponible',
        'preferences-hc-contando',
        'preferences-hc-necesita-permiso',
        'preferences-hc-negado',
      ]) {
        testWidgets('$nombre fits at 320 dp with text scale $escala in $idioma', (tester) async {
          final (ancho, alto) = _estrecha;
          usarPantalla(tester, ancho: ancho, alto: alto, escala: escala);
          fit.setLanguage(idioma);
          casos[nombre]!();
          final fallas = await _revisar(tester, const InfyterApp(), nombre, idioma: idioma);
          await _cerrar(tester);
          for (final f in fallas) {
            debugPrint('FALLA $idioma 320dp x$escala $f');
          }
          expect(fallas, isEmpty);
        });
      }
    }
  }

  for (final idioma in _idiomas.split(',')) {
    for (final escala in _escalas) {
      for (final nombre in const ['pasos-explicacion', 'pasos-explicacion-hc', 'pasos-ayuda', 'pasos-ayuda-hc']) {
        testWidgets('the $nombre sheet fits at 320 dp with text scale $escala in $idioma', (tester) async {
          final (ancho, alto) = _estrecha;
          final (preparar, abrir) = hojas[nombre]!;
          usarPantalla(tester, ancho: ancho, alto: alto, escala: escala);
          fit.setLanguage(idioma);
          preparar();
          final fallas = await _revisar(tester, const InfyterApp(), 'hoja $nombre', idioma: idioma, abrir: abrir);
          await _cerrar(tester);
          for (final f in fallas) {
            debugPrint('FALLA $idioma 320dp x$escala $f');
          }
          expect(fallas, isEmpty);
        });
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

  String diaMuyAtras() => t.shortDateYear(_hoyFijo.subtract(const Duration(days: 200)));

  final compartir = <String, (void Function(), void Function(BuildContext), Future<void> Function(WidgetTester)?, String Function())>{
    'compartir-opciones': (() => fit.route = 'progress', showShareChooser, null, () => t.shareChooserProgressHint),
    'compartir-normal': (
      () => _datosParaCompartir(diasAtras: 2),
      (c) => showProgressExportSheet(c, today: _hoyFijo),
      null,
      () => t.exportDayCount(1),
    ),
    'compartir-historico': (
      () => _datosParaCompartir(diasAtras: 200),
      (c) => showProgressExportSheet(c, today: _hoyFijo),
      _tocarHistoricoCompleto,
      () => t.exportWholeHistoryHint(diaMuyAtras(), diaMuyAtras()),
    ),
    'compartir-periodo-vacio': (
      () => _datosParaCompartir(diasAtras: 200),
      (c) => showProgressExportSheet(c, today: _hoyFijo),
      null,
      () => t.exportEmpty,
    ),
    'compartir-sin-nada': (
      _sinNadaParaCompartir,
      (c) => showProgressExportSheet(c, today: _hoyFijo),
      null,
      () => t.exportNothingAtAll,
    ),
    'compartir-exportando': (
      () => _datosParaCompartir(diasAtras: 2),
      (c) => showProgressExportSheet(c, today: _hoyFijo),
      _tocarExportar,
      () => t.exportBusy,
    ),
  };

  for (final idioma in _idiomas.split(',')) {
    for (final ancho in const [320.0, 360.0, 411.0]) {
      for (final escala in _escalas) {
        for (final MapEntry(key: nombre, value: (preparar, abrir, luego, clave)) in compartir.entries) {
          testWidgets('the $nombre sheet fits at ${ancho.toInt()} dp with text scale $escala in $idioma', (tester) async {
            final alto = ancho == 320 ? 711.0 : (ancho == 360 ? 780.0 : 914.0);
            usarPantalla(tester, ancho: ancho, alto: alto, escala: escala);
            fit.setLanguage(idioma);
            preparar();
            final fallas = await _revisar(
              tester,
              const InfyterApp(),
              'hoja $nombre',
              idioma: idioma,
              abrir: abrir,
              luego: luego,
            );
            final texto = clave();
            expect(find.text(texto), findsOneWidget, reason: '$nombre: no muestra "$texto"');
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

  final medidasSinTarjeta = <double, (double, double)>{
    320: (442, 630.5),
    360: (427, 569.8333),
    411: (394, 566.5833),
  };
  final escenariosSinTarjeta = <String, void Function()>{
    'fuente no disponible': () => _pasos(disponible: false),
    'sin fuente': () => _sinPasos(),
    'oculta con la x': () => _pasos(activado: false, oculta: true),
  };
  final estados = <String, (void Function(), bool, String Function())>{
    'sin activar': (() => _pasos(activado: false), true, () => t.stepsEnableTitle),
    'necesita permiso': (() => _pasos(permiso: StepPermission.notDetermined), true, () => t.stepsEnableTitle),
    'negado': (() => _pasos(permiso: StepPermission.denied), true, () => t.stepsDeniedTitle),
    'no disponible': (() => _pasos(disponible: false), false, () => t.stepsEnableTitle),
    'contando': (() => _pasos(pasos: 6412), true, () => t.stepsToday.toUpperCase()),
    'meta cumplida': (() => _pasos(pasos: 9876), true, () => t.stepsToday.toUpperCase()),
    'parcial': (() => _pasos(pasos: 1234, desde: 872), true, () => t.stepsCountingSince('14:32')),
  };
  for (final MapEntry(key: estado, value: (preparar, aparece, texto)) in estados.entries) {
    testWidgets('the steps card shows the right state: $estado', (tester) async {
      usarPantalla(tester, ancho: 360, alto: 780);
      fit.setLanguage('es');
      preparar();
      await _revisar(tester, const InfyterApp(), 'pasos $estado');
      final visible = find.text(texto()).evaluate().isNotEmpty;
      await _cerrar(tester);
      expect(visible, aparece);
    });
  }

  for (final ancho in const [320.0, 360.0, 411.0]) {
    for (final MapEntry(key: escenario, value: preparar) in escenariosSinTarjeta.entries) {
      testWidgets('at normal text size home keeps its measures without the steps card ($escenario) at ${ancho.toInt()} dp', (
        tester,
      ) async {
        usarPantalla(tester, ancho: ancho, alto: ancho == 320 ? 711 : 780);
        fit.setLanguage('es');
        preparar();
        await _revisar(tester, const InfyterApp(), 'home sin tarjeta');
        final titulo = tester.getTopLeft(find.text(titleCase(t.thisWeek))).dy;
        final recorrido = tester.state<ScrollableState>(find.byType(Scrollable).first).position.maxScrollExtent;
        final tarjeta = find.descendant(of: find.byType(StepsCard), matching: find.byType(SoftCard));
        final sinTarjeta = tarjeta.evaluate().isEmpty;
        await _cerrar(tester);
        expect(sinTarjeta, isTrue);
        expect(titulo, closeTo(medidasSinTarjeta[ancho]!.$1, 0.01));
        expect(recorrido, closeTo(medidasSinTarjeta[ancho]!.$2, 0.01));
      });
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
    for (final (ancho, alto) in [..._pantallas, if (idioma == 'es') _estrecha]) {
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

  for (final escala in _escalas) {
    testWidgets('the tab bar fits whole inside a 320 dp screen at scale $escala', (tester) async {
      final (ancho, alto) = _estrecha;
      usarPantalla(tester, ancho: ancho, alto: alto, escala: escala);
      fit.route = 'home';
      final fallas = await _revisar(tester, const InfyterApp(), 'barra 320');
      Rect caja(RenderBox r) => MatrixUtils.transformRect(r.getTransformTo(null), Offset.zero & r.size);
      RenderBox abajo(Finder f) => tester
          .renderObjectList<RenderBox>(f)
          .reduce((a, b) => a.localToGlobal(Offset.zero).dy > b.localToGlobal(Offset.zero).dy ? a : b);
      final pantalla = Rect.fromLTWH(0, 0, ancho, alto);
      final barra = caja(tester.renderObject<RenderBox>(find.byWidgetPredicate((w) => '${w.runtimeType}' == '_NavBar')));
      final piezas = <String, Rect>{
        for (final label in [t.home, t.progress, t.exercises, t.profile]) label: caja(abajo(find.text(label))),
        'play': caja(abajo(find.ancestor(of: find.byIcon(PhosphorIconsFill.play), matching: find.byType(Container)).first)),
      };
      await _cerrar(tester);
      for (final MapEntry(key: n, value: r) in piezas.entries) {
        if (!pantalla.contains(r.topLeft) || !pantalla.contains(r.bottomRight - const Offset(0.01, 0.01))) {
          fallas.add('$n fuera de la pantalla: $r');
        }
        if (r.left < barra.left || r.right > barra.right) fallas.add('$n fuera de la barra: $r, barra $barra');
      }
      final orden = [t.home, t.progress, 'play', t.exercises, t.profile];
      for (var i = 0; i + 1 < orden.length; i++) {
        final hueco = piezas[orden[i + 1]]!.left - piezas[orden[i]]!.right;
        if (hueco < 2) fallas.add('${orden[i]} y ${orden[i + 1]} a ${hueco.toStringAsFixed(1)} dp');
      }
      expect(fallas, isEmpty);
    });
  }

  for (final idioma in _idiomas.split(',')) {
    for (final (ancho, alto) in _pantallas) {
      for (final escala in _escalas) {
        testWidgets('the collapsed profile header fits at ${ancho.toInt()} dp, scale $escala, $idioma', (
          tester,
        ) async {
          usarPantalla(tester, ancho: ancho, alto: alto, escala: escala);
          fit.setLanguage(idioma);
          fit.route = 'settings';
          final fallas = await _revisar(tester, const InfyterApp(), 'perfil', idioma: idioma);
          fallas.addAll(
            await conErrores(() async {
              await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -1500));
              for (var i = 0; i < 8; i++) {
                await tester.pump(const Duration(milliseconds: 200));
              }
            }),
          );
          final compacto = find.ancestor(
            of: find.text('@${fit.profileHandle}'),
            matching: find.byWidgetPredicate((w) => w is Opacity && w.opacity == 1),
          );
          final visible = compacto.evaluate().isNotEmpty;
          fallas.addAll([...textoCortado(tester), ...palabrasPartidas(tester)]);
          await _cerrar(tester);
          for (final f in fallas) {
            debugPrint('FALLA $idioma ${ancho.toInt()}dp x$escala perfil plegado: $f');
          }
          expect(visible, isTrue, reason: 'el encabezado compacto tiene que quedar a la vista');
          expect(fallas, isEmpty);
        });
      }
    }
  }

  for (final idioma in _idiomas.split(',')) {
    for (final (ancho, alto) in _pantallas) {
      for (final nombre in const ['home', 'home-pasos-contando', 'home-pasos-negado']) {
        testWidgets('$nombre scrolled to the end keeps its last content above the tab bar at ${ancho.toInt()} dp, '
            'scale 1.5, $idioma', (tester) async {
          usarPantalla(tester, ancho: ancho, alto: alto, escala: 1.5);
          fit.setLanguage(idioma);
          casos[nombre]!();
          final fallas = await _revisar(tester, const InfyterApp(), nombre, idioma: idioma);
          final lista = find.descendant(of: find.byType(HomeScreen), matching: find.byType(SingleChildScrollView));
          final posicion = tester.state<ScrollableState>(find.descendant(of: lista, matching: find.byType(Scrollable)).first).position;
          posicion.jumpTo(posicion.maxScrollExtent);
          await tester.pump(const Duration(milliseconds: 400));
          final contenido = tester.getRect(find.descendant(of: lista, matching: find.byType(Column)).first);
          final barra = tester.getRect(find.byWidgetPredicate((w) => '${w.runtimeType}' == '_NavBar'));
          await _cerrar(tester);
          expect(posicion.maxScrollExtent, greaterThan(0));
          expect(fallas, isEmpty);
          expect(contenido.bottom, lessThanOrEqualTo(barra.top), reason: 'contenido $contenido, barra $barra');
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
