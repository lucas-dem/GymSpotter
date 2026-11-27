import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/models/measure.dart';
import 'package:infyter/models/progress_report.dart';
import 'package:infyter/models/workout.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/services/progress_export/export_format.dart';
import 'package:infyter/services/progress_report_builder.dart';
import 'package:infyter/services/progress_report_source.dart';
import 'package:infyter/state/energy.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:infyter/state/steps_range.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'compartir_progreso_fixture.dart';

const _kg = ReportUnits(weight: 'kg', length: 'cm', distance: 'km', effort: 'rpe');

ProgressReport _build({
  DateTime? from,
  DateTime? to,
  bool wholeHistory = false,
  List<LoggedSession> sessions = const [],
  Map<String, int> steps = const {},
  Map<String, int> stepsFrom = const {},
  bool showStepsFrom = true,
  List<BodyweightEntry> bodyweight = const [],
  List<BodyMeasure> measures = const [],
  ReportUnits units = _kg,
}) =>
    buildProgressReport(
      from: from ?? DateTime(2026, 11, 1),
      to: to ?? DateTime(2026, 11, 30),
      wholeHistory: wholeHistory,
      now: fixtureNow,
      language: 'es',
      locale: 'es',
      units: units,
      sessions: sessions,
      steps: steps,
      stepsFrom: stepsFrom,
      showStepsFrom: showStepsFrom,
      bodyweight: bodyweight,
      measures: measures,
      profileWeightKg: fixtureProfileWeightKg,
      toWeight: (kg) => kg,
      toMeasure: (key, raw) => raw,
      toDistance: (km) => km,
      restFor: fixtureRestFor,
      exerciseName: fixtureExerciseName,
    );

LoggedSession _session(DateTime at, {int sec = 1800}) => LoggedSession(at, sec, [
      LoggedExercise('bench_press', 'Bench press', 'chest', [LoggedSet(8, 60)]),
    ]);

List<DateTime> _dates(ProgressReport r) => r.days.map((d) => d.date).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async => initializeDateFormatting());

  group('period', () {
    test('keeps the days from Desde to Hasta inclusive, by local date', () {
      final r = _build(
        from: DateTime(2026, 11, 20),
        to: DateTime(2026, 11, 22),
        sessions: [
          _session(DateTime(2026, 11, 19, 23, 59)),
          _session(DateTime(2026, 11, 20, 0, 0)),
          _session(DateTime(2026, 11, 22, 23, 59)),
          _session(DateTime(2026, 11, 23, 0, 0)),
        ],
        steps: {'2026-11-19': 500, '2026-11-21': 4000, '2026-11-23': 600},
      );
      expect(_dates(r), [DateTime(2026, 11, 20), DateTime(2026, 11, 21), DateTime(2026, 11, 22)]);
      expect(r.from, DateTime(2026, 11, 20));
      expect(r.to, DateTime(2026, 11, 22));
      expect(r.wholeHistory, isFalse);
    });

    test('a time of day in Desde or Hasta does not cut the day', () {
      final r = _build(
        from: DateTime(2026, 11, 20, 15),
        to: DateTime(2026, 11, 22, 9),
        sessions: [_session(DateTime(2026, 11, 20, 8)), _session(DateTime(2026, 11, 22, 21))],
      );
      expect(_dates(r), [DateTime(2026, 11, 20), DateTime(2026, 11, 22)]);
    });

    test('the fixture gives Thursday and Saturday, oldest first', () {
      final r = fixtureReport();
      expect(_dates(r), [DateTime(2026, 11, 20), DateTime(2026, 11, 22)]);
      expect(r.generatedAt, fixtureNow);
      expect(r.language, 'es');
      expect(r.locale, 'es');
    });
  });

  group('whole history', () {
    test('runs from the first to the last day with data, whatever Desde and Hasta say', () {
      final r = _build(
        from: DateTime(2026, 11, 20),
        to: DateTime(2026, 11, 20),
        wholeHistory: true,
        sessions: [_session(DateTime(2025, 3, 2, 10))],
        steps: {'2024-01-01': 0, '2026-12-05': 7000, '2027-01-01': 0},
        bodyweight: [BodyweightEntry(DateTime(2026, 11, 20, 7), 80)],
      );
      expect(r.wholeHistory, isTrue);
      expect(r.from, DateTime(2025, 3, 2));
      expect(r.to, DateTime(2026, 12, 5));
      expect(_dates(r), [DateTime(2025, 3, 2), DateTime(2026, 11, 20), DateTime(2026, 12, 5)]);
    });

    test('recordedSpan is null when nothing was ever logged', () {
      expect(
        recordedSpan(sessions: const [], steps: const {'2026-11-20': 0}, bodyweight: const [], measures: const []),
        isNull,
      );
      final r = _build(wholeHistory: true, steps: {'2026-11-20': 0});
      expect(r.isEmpty, isTrue);
    });

    test('measures and bodyweight also open the span', () {
      final span = recordedSpan(
        sessions: const [],
        steps: const {},
        bodyweight: [BodyweightEntry(DateTime(2026, 6, 1, 9), 80)],
        measures: [BodyMeasure(DateTime(2026, 2, 3, 9), 'waist', 82)],
      );
      expect(span, (from: DateTime(2026, 2, 3), to: DateTime(2026, 6, 1)));
    });
  });

  group('steps', () {
    test('a day without a reading has null steps, never 0', () {
      final r = _build(sessions: [_session(DateTime(2026, 11, 10, 18))]);
      final day = r.days.single;
      expect(day.steps, isNull);
      expect(day.kcalSteps, isNull);
      expect(day.stepsFromMinute, isNull);
      expect(day.kcalWorkouts, isNotNull);
      expect(day.kcalTotal, day.kcalWorkouts);
    });

    test('a day with only steps appears, with its kcal', () {
      final day = fixtureReport().days.last;
      expect(day.date, DateTime(2026, 11, 22));
      expect(day.sessions, isEmpty);
      expect(day.steps, 3120);
      expect(day.stepsFromMinute, 14 * 60 + 5);
      expect(day.kcalSteps, 80);
      expect(day.kcalWorkouts, isNull);
      expect(day.kcalTotal, 80);
      expect(day.bodyweight, isNull);
      expect(day.measures, isEmpty);
    });

    test('the counting start is left out when the source does not show it', () {
      final r = _build(steps: {'2026-11-22': 3120}, stepsFrom: {'2026-11-22': 845}, showStepsFrom: false);
      expect(r.days.single.stepsFromMinute, isNull);
    });

    test('a 0 read on a day that appears for something else is kept as 0', () {
      final r = _build(
        steps: {'2026-11-10': 0},
        bodyweight: [BodyweightEntry(DateTime(2026, 11, 10, 7), 80)],
      );
      expect(r.days.single.steps, 0);
      expect(r.days.single.kcalSteps, 0);
    });
  });

  group('empty', () {
    test('a period with nothing logged is empty', () {
      final r = _build(
        from: DateTime(2026, 11, 1),
        to: DateTime(2026, 11, 5),
        sessions: [_session(DateTime(2026, 11, 6, 9))],
        steps: {'2026-10-31': 9000},
      );
      expect(r.isEmpty, isTrue);
      expect(r.measureKeys, isEmpty);
    });

    test('days with nothing do not appear, and a lone 0 steps read is nothing', () {
      final r = _build(
        steps: {'2026-11-20': 8432, '2026-11-21': 0, '2026-11-22': 3120},
        measures: [BodyMeasure(DateTime(2026, 11, 23), 'unknown', 3)],
      );
      expect(_dates(r), [DateTime(2026, 11, 20), DateTime(2026, 11, 22)]);
      expect(_dates(fixtureReport()), isNot(contains(DateTime(2026, 11, 21))));
    });
  });

  group('bodyweight and measures', () {
    test('only on the day they were logged, the latest one of that day', () {
      final r = _build(
        steps: {'2026-11-21': 5000},
        bodyweight: [
          BodyweightEntry(DateTime(2026, 11, 20, 21), 79),
          BodyweightEntry(DateTime(2026, 11, 20, 7), 80),
        ],
        measures: [
          BodyMeasure(DateTime(2026, 11, 20, 7), 'waist', 83),
          BodyMeasure(DateTime(2026, 11, 20, 20), 'waist', 82.04),
          BodyMeasure(DateTime(2026, 11, 22, 9), 'bodyfat', 18.25),
        ],
      );
      expect(_dates(r), [DateTime(2026, 11, 20), DateTime(2026, 11, 21), DateTime(2026, 11, 22)]);
      expect(r.days[0].bodyweight, 79);
      expect(r.days[0].measures, {'waist': 82});
      expect(r.days[1].bodyweight, isNull);
      expect(r.days[1].measures, isEmpty);
      expect(r.days[2].measures, {'bodyfat': 18.3});
      expect(r.days[2].bodyweight, isNull);
    });

    test('measureKeys is the union of the period in the order of kMeasureKeys', () {
      final r = _build(
        measures: [
          BodyMeasure(DateTime(2026, 11, 20), 'waist', 82),
          BodyMeasure(DateTime(2026, 11, 21), 'bodyfat', 18),
          BodyMeasure(DateTime(2026, 11, 22), 'arm', 36),
          BodyMeasure(DateTime(2026, 12, 2), 'neck', 40),
        ],
      );
      expect(r.measureKeys, ['arm', 'waist', 'bodyfat']);
    });

    test('kcal still use the latest weight on or before the day', () {
      final r = fixtureReport();
      for (final day in r.days) {
        final k = dayKcal(
          day: day.date,
          steps: fixtureSteps()[stepsDayKey(day.date)],
          sessions: fixtureSessions(),
          bodyweight: fixtureBodyweight(),
          profileWeightKg: fixtureProfileWeightKg,
        );
        expect(day.kcalSteps, k.stepsKcal);
        expect(day.kcalTotal, k.total);
      }
      expect(r.days.first.kcalSteps, 220);
      expect(r.days.first.kcalWorkouts, 170);
      expect(r.days.first.kcalTotal, 390);
    });
  });

  group('sessions and sets', () {
    test('the fixture day keeps exercises, sets and configured rest in order', () {
      final day = fixtureReport().days.first;
      final session = day.sessions.single;
      expect(session.durationMin, 52);
      expect(session.exercises.map((e) => e.name), ['Press plano', 'Planchas frontales', 'Cinta']);
      expect(session.exercises.map((e) => e.restConfiguredSec), [90, 90, 0]);
      final bench = session.exercises.first.sets;
      expect(bench.map((s) => s.number), [1, 2, 3]);
      expect(bench.map((s) => s.kind), [SetKind.warmup, SetKind.normal, SetKind.normal]);
      expect(bench.map((s) => s.weight), [40, 60, 62.5]);
      expect(bench.map((s) => s.reps), [10, 8, 8]);
      expect(bench.map((s) => s.effort), [null, null, 9]);
      final plank = session.exercises[1].sets.single;
      expect((plank.reps, plank.weight, plank.durationSec, plank.distance), (null, null, 60, null));
      final run = session.exercises[2].sets.single;
      expect((run.reps, run.weight, run.durationSec, run.distance), (null, null, 1200, 2.5));
      expect(day.bodyweight, 78.4);
      expect(day.measures, {'arm': 36.5, 'waist': 82});
      expect(day.steps, 8432);
      expect(day.stepsFromMinute, isNull);
    });

    test('sessions by time, empty exercises dropped, a session without exercises kept', () {
      final r = _build(sessions: [
        LoggedSession(DateTime(2026, 11, 20, 19), 0, []),
        LoggedSession(DateTime(2026, 11, 20, 7), 1800, [
          LoggedExercise('bench_press', 'Bench press', 'chest', []),
          LoggedExercise('front_plank', 'Front plank', 'abs', [LoggedSet(0, 0, sec: 45)]),
        ]),
      ]);
      final sessions = r.days.single.sessions;
      expect(sessions.map((s) => s.durationMin), [30, null]);
      expect(sessions.first.exercises.map((e) => e.name), ['Planchas frontales']);
      expect(sessions.last.exercises, isEmpty);
    });

    test('RIR scale turns the stored RPE into reps in reserve', () {
      final set = fixtureReport(effort: 'rir').days.first.sessions.single.exercises.first.sets.last;
      expect(set.effort, 1);
    });
  });

  group('units of the user', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Store.instance.init();
      fit.resetAllData();
      setAppLanguage('es');
    });

    tearDown(() {
      fit.setUnits('kg');
      setAppLanguage('en');
    });

    void seed() {
      fit.sessions.add(LoggedSession(DateTime(2026, 11, 20, 18), 3120, [
        LoggedExercise('EIeI8Vf', 'Bench press', 'chest', [LoggedSet(8, 62.5, rpe: 9)]),
        LoggedExercise('own-run', 'Cinta', 'cardio', [LoggedSet(0, 0, sec: 1200, km: 2.5)]),
      ]));
      fit.steps['2026-11-20'] = 8432;
      fit.bodyweight.add(BodyweightEntry(DateTime(2026, 11, 20, 8), 78.4));
      fit.measures.add(BodyMeasure(DateTime(2026, 11, 20, 8), 'waist', 82));
      fit.measures.add(BodyMeasure(DateTime(2026, 11, 20, 8), 'bodyfat', 18.5));
      fit.setExerciseRest('EIeI8Vf', 120);
    }

    for (final unit in ['kg', 'lb']) {
      test('values match what the screens show in $unit', () {
        fit.setUnits(unit);
        seed();
        final r = progressReportFromFit(from: DateTime(2026, 11, 20), to: DateTime(2026, 11, 20), wholeHistory: false);
        final day = r.days.single;
        final exercises = day.sessions.single.exercises;
        expect(r.units.weight, fit.units);
        expect(r.units.length, fit.lengthUnit);
        expect(r.units.distance, fit.distanceUnit);
        expect(fmt(exercises.first.sets.single.weight!), fit.weightValue(62.5));
        expect(fmt(exercises.last.sets.single.distance!), fit.distanceValue(2.5));
        expect(fmt(day.bodyweight!), fit.weightValue(78.4));
        expect(fmt(day.measures['waist']!), fit.measureValue('waist', 82));
        expect(fmt(day.measures['bodyfat']!), '18.5');
        expect(exercises.first.restConfiguredSec, 120);
        expect(exercises.first.restConfiguredSec, fit.restFor('EIeI8Vf'));
        expect(exercises.last.restConfiguredSec, fit.restFor('own-run'));
        expect(r.language, 'es');
        expect(r.locale, 'es');
      });
    }

    test('in lb the numbers are converted, not the kg ones', () {
      fit.setUnits('lb');
      seed();
      final day = progressReportFromFit(from: DateTime(2026, 11, 20), to: DateTime(2026, 11, 20), wholeHistory: false)
          .days
          .single;
      expect(day.bodyweight, 172.8);
      expect(day.measures['waist'], 32.3);
      expect(day.sessions.single.exercises.last.sets.single.distance, 1.55);
    });

    test('whole history from fit runs over everything recorded', () {
      seed();
      fit.steps['2026-12-01'] = 1000;
      final r = progressReportFromFit(from: DateTime(2026, 11, 25), to: DateTime(2026, 11, 25), wholeHistory: true);
      expect(_dates(r), [DateTime(2026, 11, 20), DateTime(2026, 12, 1)]);
      expect(recordedSpanFromFit(), (from: DateTime(2026, 11, 20), to: DateTime(2026, 12, 1)));
    });

    test('the exercise name comes from the catalogue, not from the logged name', () {
      seed();
      final names = progressReportFromFit(from: DateTime(2026, 11, 20), to: DateTime(2026, 11, 20), wholeHistory: false)
          .days
          .single
          .sessions
          .single
          .exercises
          .map((e) => e.name);
      expect(names.first, 'Press plano');
      expect(names.first, t.catalogNameRaw('EIeI8Vf', 'Bench press'));
    });
  });

  group('ExportFormat', () {
    test('es writes decimal comma, dot thousands and ; for CSV', () {
      final f = ExportFormat('es');
      expect(f.decimalComma, isTrue);
      expect(f.csvSeparator, ';');
      expect(f.number(62.5), '62,5');
      expect(f.number(60), '60');
      expect(f.number(18432), '18.432');
      expect(f.number(8432), '8.432');
      expect(f.plainNumber(18432), '18432');
      expect(f.number(1.556, decimals: 2), '1,56');
      expect(f.dayHeading(DateTime(2026, 11, 20)), 'Viernes, 20 de noviembre de 2026');
      expect(f.numericDate(DateTime(2026, 11, 20)), '20/11/2026');
    });

    test('en writes decimal point, comma thousands and , for CSV', () {
      final f = ExportFormat('en');
      expect(f.decimalComma, isFalse);
      expect(f.csvSeparator, ',');
      expect(f.number(62.5), '62.5');
      expect(f.number(8432), '8,432');
      expect(f.plainNumber(8432), '8432');
    });

    test('fr has no narrow no-break space and ar dates have no RLM', () {
      final fr = ExportFormat('fr');
      expect(fr.number(18432), isNot(contains(' ')));
      expect(fr.number(18432), '18 432');
      expect(fr.csvSeparator, ';');
      final ar = ExportFormat('ar');
      expect(ar.numericDate(DateTime(2026, 11, 20)), isNot(contains('‏')));
      expect(ar.shortDate(DateTime(2026, 11, 20)), isNot(contains('‏')));
      expect(ar.decimalComma, isFalse);
    });

    test('clean drops invisible characters', () {
      final f = ExportFormat('ja');
      expect(f.clean('a⁠b​c­d‎e‏f'), 'abcdef');
      expect(f.clean('1 2'), '1 2');
    });

    test('clock and duration read like the app', () {
      final f = ExportFormat('es');
      expect(f.clock(845), '14:05');
      expect(f.clock(5), '00:05');
      for (final sec in [0, 59, 60, 90, 1200, 3600, 3725, -3]) {
        expect(f.duration(sec), durationLabel(sec));
      }
    });
  });
}
