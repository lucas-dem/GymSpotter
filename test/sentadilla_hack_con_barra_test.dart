// "Sentadilla hack con barra" (5VCj6iH, en inglés "Barbell Hack Squat") queda oculta (sesión 29, pedido de Braian).
// No aparece en la biblioteca, la búsqueda, las sugerencias ni en las listas para agregar ejercicios. Su id y su
// definición siguen en el catálogo: las rutinas, el historial, las copias y las importaciones que ya la tienen la
// siguen cargando y mostrando. Su dibujo (`hack-squat`) lo comparte "Sentadilla hack en Smith" (ZuPXtCK) y no se
// toca (lo fija `_sharedArtKept` en exercise_alias_test.dart).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/app/infyter_app.dart';
import 'package:infyter/catalog/exercise_catalog.dart';
import 'package:infyter/catalog/hidden_exercises.dart';
import 'package:infyter/catalog/program_templates.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/models/exercise.dart';
import 'package:infyter/models/workout.dart';
import 'package:infyter/services/exercise_match.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/services/plan_qr.dart';
import 'package:infyter/services/progress_reminder.dart';
import 'package:infyter/services/workout_import.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:infyter/widgets/ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _oculta = '5VCj6iH'; // Sentadilla hack con barra
const _smith = 'ZuPXtCK'; // Sentadilla hack en Smith: comparte el dibujo y sigue a la vista
const _prensaHack = 'pendulum-hack-squat';
const _hackDeFrente = 'reverse-pendulum-hack-squat';

// Lo que guarda 1.3.1 (clave gymmane_v1) para alguien con la sentadilla hack con barra en una rutina y en su
// historial.
const _guardado = '''
{
  "onboarded": true,
  "language": "es",
  "routines": [
    {"id": "r1760000000000000-0", "n": "Piernas", "ex": ["5VCj6iH", "ZuPXtCK"], "s": {"5VCj6iH": 4}}
  ],
  "sessions": [
    {"d": "2026-10-20T18:30:00.000", "dur": 2400, "ex": [
      {"id": "5VCj6iH", "n": "Barbell Hack Squat", "p": "glutes", "s": [{"r": 8, "w": 60.0}, {"r": 6, "w": 70.0}]}
    ]}
  ]
}
''';

List<String> _ids(Iterable<Exercise> list) => [for (final e in list) e.id];

Exercise _def(String id) => kExercises.singleWhere((e) => e.id == id);

// Precondición de cada búsqueda: sin el ocultamiento, la encontraría.
void _laEncontraria(String q) =>
    expect(_ids(kExercises.where(exerciseSearch(q))), contains(_oculta), reason: 'precondición: "$q"');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('infyter_hack_barra');
    Store.rescueDirectory = '${tmp.path}/data_rescue';
    SharedPreferences.setMockInitialValues({});
    Store.instance.debugReset();
    await Store.instance.init();
    ProgressReminder.instance.enabled = false;
    fit.resetAllData();
    fit.clearExFilters();
    fit.onboarded = true;
    setAppLanguage('es');
  });

  tearDown(() async {
    fit.resetAllData();
    fit.clearExFilters();
    fit.activeExerciseId = null;
    setAppLanguage('en');
    Store.rescueDirectory = null;
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('guardia: su id y su definición siguen en el catálogo, con su nombre en español', () {
    final def = _def(_oculta);
    expect(def.name, 'Barbell Hack Squat');
    expect(exerciseName(def), 'Sentadilla hack con barra');
  });

  test('guardia: cada id oculto existe en el catálogo (un error de tipeo no ocultaría nada)', () {
    final catalogo = {for (final e in kExercises) e.id};
    expect(kHiddenExercises, contains(_oculta));
    expect(kHiddenExercises.where((id) => !catalogo.contains(id)), isEmpty);
  });

  test('guardia: ningún plan hecho la agrega a una rutina', () {
    for (final template in kProgramTemplates) {
      for (final day in template.days) {
        for (final (name, _) in day.exercises) {
          final ex = fit.matchExerciseByName(name);
          expect(ex, isNotNull, reason: name);
          expect(kHiddenExercises, isNot(contains(ex!.id)), reason: '${template.id} · ${day.name} · $name');
        }
      }
    }
  });

  group('no aparece en el catálogo ni en la búsqueda', () {
    test('la biblioteca no la lista; las otras hack, sí', () {
      final ids = _ids(fit.exercisesFiltered);
      expect(ids, isNot(contains(_oculta)));
      expect(ids, containsAll([_smith, _prensaHack, _hackDeFrente]));
    });

    // exercisesMatching es también la lista para agregar ejercicios a una rutina (routine_edit_screen).
    test('buscarla por su nombre, en inglés, por su alias o por "hack" no la encuentra', () {
      for (final q in [
        'Sentadilla hack con barra',
        'sentadilla hack',
        'Barbell Hack Squat',
        'Hack Squat (Barbell)',
        'hack',
      ]) {
        _laEncontraria(q);
        expect(_ids(fit.exercisesMatching(q)), isNot(contains(_oculta)), reason: q);
      }
      expect(_ids(fit.exercisesMatching('hack')), containsAll([_smith, _prensaHack, _hackDeFrente]));
    });

    // trainSearchResults es también la búsqueda para agregar un ejercicio durante la sesión.
    test('entrenar por músculo y su búsqueda no la ofrecen', () {
      expect(_def(_oculta).primary, 'glutes'); // Precondición: es de glúteos.
      expect(_ids(fit.getFilteredExercises(['glutes'])), allOf(isNot(contains(_oculta)), contains(_smith)));
      for (final q in ['Sentadilla hack con barra', 'hack']) {
        _laEncontraria(q);
        expect(_ids(fit.trainSearchResults(q)), isNot(contains(_oculta)), reason: q);
      }
      expect(_ids(fit.trainSearchResults('hack')), contains(_smith));
    });

    test('el contador de favoritos de la biblioteca no la cuenta, aunque siga marcada', () {
      fit.toggleFavorite(_oculta);
      fit.toggleFavorite(_smith);
      expect(fit.favouriteCount, 1);
      expect(fit.favorites[_oculta], isTrue); // El dato guardado no cambia.
    });

    test('el conteo de ejercicios de un lugar (Lugares y bienvenida) no la cuenta', () {
      final casa = fit.addPlace('Casa', equipment: {'Barbell'});
      final lugar = fit.places.singleWhere((p) => p.id == casa);
      final conBarra = [
        for (final e in kExercises)
          if (e.equipment == 'Barbell' || e.equipment == 'Bodyweight') e.id,
      ];
      expect(conBarra, contains(_oculta)); // Precondición: es de barra.
      expect(fit.placeExerciseCount(lugar), conBarra.length - 1);
      expect(fit.exerciseCountFor({'Barbell'}), conBarra.length - 1); // La que usa la bienvenida.
    });

    testWidgets('en la pantalla de la biblioteca, buscar "hack" no la muestra', (tester) async {
      fit.setExSearch('hack');
      fit.route = 'exercises';
      await tester.pumpWidget(const InfyterApp());
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Sentadilla hack en Smith'), findsOneWidget);
      expect(find.text('Sentadilla hack con barra'), findsNothing);
    });

    testWidgets('el selector de ejercicio de una nota nueva no la ofrece', (tester) async {
      fit.route = 'note-edit';
      await tester.pumpWidget(const InfyterApp());
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Sin ejercicio'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField).last, 'hack');
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Sentadilla hack en Smith'), findsOneWidget);
      expect(find.text('Sentadilla hack con barra'), findsNothing);
    });
  });

  group('no se sugiere', () {
    test('los similares de su ficha y de las otras no la proponen', () {
      expect(_def(_oculta).primary, _def(_smith).primary); // Precondición: mismo músculo.
      final similares = _ids(fit.similarExercises(_def(_smith), 1000));
      expect(similares, isNot(contains(_oculta)));
      expect(similares, isNotEmpty);
    });

    test('las alternativas para un lugar sin máquinas no la proponen', () {
      expect(_def(_oculta).equipment, 'Barbell'); // Precondición: se puede hacer en ese lugar.
      fit.setActivePlace(fit.addPlace('Casa', equipment: {'Barbell'}));
      final alternativas = _ids(fit.alternativesHere(_def(_smith), 1000));
      expect(alternativas, isNot(contains(_oculta)));
      expect(alternativas, isNotEmpty);
    });

    test('las sugerencias de la sesión no la proponen aunque sea favorita', () {
      fit.toggleFavorite(_oculta);
      fit.toggleFavorite(_smith);
      final sugeridos = _ids(fit.sessionSuggestions());
      expect(sugeridos, isNot(contains(_oculta)));
      expect(sugeridos, contains(_smith));
    });

    test('las sugerencias de la sesión no la proponen aunque esté en el historial', () {
      fit.sessions.add(
        LoggedSession(DateTime(2026, 10, 30, 18), 1800, [
          LoggedExercise(_oculta, 'Barbell Hack Squat', 'glutes', [LoggedSet(8, 60)]),
          LoggedExercise(_prensaHack, 'Pendulum Hack Squat', 'quads', [LoggedSet(10, 80)]),
        ]),
      );
      final sugeridos = _ids(fit.sessionSuggestions());
      expect(sugeridos, isNot(contains(_oculta)));
      expect(sugeridos, contains(_prensaHack));
    });

    test('los recomendados del inicio no la proponen', () {
      // Una sola sesión, de espalda y de hoy: el foco pasa a piernas (con glúteos).
      fit.sessions.add(
        LoggedSession(DateTime.now(), 1800, [
          LoggedExercise('eZyBC3j', 'Barbell Bent Over Row', 'back', [LoggedSet(8, 60)]),
        ]),
      );
      expect(fit.suggestedFocus.muscles, contains(_def(_oculta).primary)); // Precondición.
      final recomendados = _ids(fit.recommendedExercises(1000));
      expect(recomendados, isNot(contains(_oculta)));
      expect(recomendados, contains(_smith));
    });

    test('el pedido de plan para la IA no la lista', () {
      final texto = fit.planRequestText();
      expect(texto, isNot(contains('Barbell Hack Squat')));
      expect(texto, contains('Smith Hack Squat'));
    });

    testWidgets('su ficha no ofrece "Sugerir en entrenamientos", que ya no haría nada', (tester) async {
      fit.openExercise(_oculta);
      await tester.pumpWidget(const InfyterApp());
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Sentadilla hack con barra'), findsWidgets); // Es su ficha.
      expect(find.text(t.suggestInWorkouts), findsNothing);
    });

    testWidgets('guardia: la ficha de la sentadilla hack en Smith lo sigue ofreciendo', (tester) async {
      fit.openExercise(_smith);
      await tester.pumpWidget(const InfyterApp());
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(t.suggestInWorkouts), findsOneWidget);
    });
  });

  group('lo que ya la tiene la sigue cargando y mostrando', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({'gymmane_v1': _guardado});
      Store.instance.debugReset();
      await Store.instance.init();
      fit.loadFromStore();
      setAppLanguage('es');
    });

    test('la rutina la conserva, con sus series, y la muestra con su nombre', () {
      final r = fit.routines.single;
      expect(r.exerciseIds, [_oculta, _smith]);
      expect(fit.routineSets(r, _oculta), 4);
      expect(fit.routineExercises(r).map(exerciseName), [
        'Sentadilla hack con barra',
        'Sentadilla hack en Smith',
      ]);
    });

    // El historial (progress_screen) muestra cada ejercicio con t.catalogName(id, nombre guardado).
    test('el historial la conserva y la muestra con su nombre', () {
      final ex = fit.sessions.single.exercises.single;
      expect(ex.id, _oculta);
      expect(ex.sets.map((s) => s.reps), [8, 6]);
      expect(t.catalogName(ex.id, ex.name), 'Sentadilla hack con barra');
    });

    test('empezar la rutina abre la sesión con ella', () {
      fit.startRoutine(fit.routines.single);
      expect(fit.session!.exercises.map((e) => e.id), [_oculta, _smith]);
      fit.discardSession();
    });

    test('su ficha se abre desde la rutina o el historial', () {
      fit.openExercise(_oculta);
      expect(fit.activeExercise.id, _oculta);
      expect(exerciseName(fit.activeExercise), 'Sentadilla hack con barra');
    });

    testWidgets('el editor de la rutina la muestra', (tester) async {
      fit.openRoutine(fit.routines.single.id);
      await tester.pumpWidget(const InfyterApp());
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Sentadilla hack con barra'), findsWidgets);
    });

    testWidgets('una nota que ya la tiene la muestra, y su selector la deja marcada', (tester) async {
      fit.openNoteEditor(exerciseId: _oculta);
      await tester.pumpWidget(const InfyterApp());
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Sentadilla hack con barra')); // La fila de la nota abre el selector.
      await tester.pump(const Duration(milliseconds: 400));

      final opciones = tester.widget<OptionGroup>(find.byType(OptionGroup).last).items;
      final marcadas = [
        for (final o in opciones)
          if (o.selected) o.label,
      ];
      expect(marcadas, ['Sentadilla hack con barra']);
    });
  });

  group('la importación la acepta', () {
    test('una copia JSON con la rutina y el historial la trae entera', () {
      expect(fit.importJson(_guardado), isTrue);
      expect(fit.routines.single.exerciseIds, [_oculta, _smith]);
      expect(_ids(fit.routineExercises(fit.routines.single)), [_oculta, _smith]);
      expect(fit.sessions.single.exercises.single.id, _oculta);
    });

    test('un CSV de Strong con "Hack Squat (Barbell)" la empareja', () {
      const csv =
          'Date;Workout Name;Duration;Exercise Name;Set Order;Weight;Reps;Distance;Seconds;Notes;Workout Notes;RPE\n'
          '2024-01-13 10:00:00;Piernas;1h 5m;Hack Squat (Barbell);1;60;8;;;;;\n';
      expect(fit.importParsedSessions(parseImport(csv).sessions), 1);
      expect(fit.sessions.single.exercises.single.id, _oculta);
    });

    test('el CSV que exporta la app, con su nombre en español, la empareja', () {
      const csv =
          'date,exercise,muscle,set,reps,weight_kg,volume_kg,est_1rm_kg\n'
          '2026-10-20,Sentadilla hack con barra,glutes,1,8,60,480,76\n';
      expect(fit.importParsedSessions(parseImport(csv).sessions), 1);
      expect(fit.sessions.single.exercises.single.id, _oculta);
    });

    test('un plan de la IA que la nombra la agrega a la rutina', () {
      final r = fit.importPlan('{"name":"Piernas","exercises":[{"name":"Barbell Hack Squat","sets":4}]}');
      expect(r.added, 1);
      expect(r.missed, isEmpty);
      expect(fit.routines.single.exerciseIds, [_oculta]);
    });

    test('un plan compartido por QR que la tiene la agrega a la rutina', () {
      final id = fit.createRoutine('Piernas');
      fit.toggleRoutineExercise(id, _oculta);
      final qr = encodePlanQrJson(fit.exportPlanJson(fit.routines));
      fit.resetAllData(); // Del otro lado: un teléfono sin esa rutina.

      final r = fit.importPlan(decodePlanQr(qr)!);
      expect(r.added, 1);
      expect(fit.routines.single.exerciseIds, [_oculta]);
    });
  });
}
