import 'package:infyter/models/measure.dart';
import 'package:infyter/models/progress_report.dart';
import 'package:infyter/models/workout.dart';
import 'package:infyter/services/progress_report_builder.dart';

final fixtureFrom = DateTime(2026, 11, 20);
final fixtureTo = DateTime(2026, 11, 22);
final fixtureNow = DateTime(2026, 11, 27, 10, 15);
const fixtureProfileWeightKg = 75.0;
const fixtureGlobalRestSec = 90;

const fixtureNames = {
  'bench_press': 'Press plano',
  'front_plank': 'Planchas frontales',
  'own_treadmill': 'Cinta',
};
const fixtureOwnRest = {'bench_press': 90};
const fixtureCardio = {'own_treadmill'};

List<LoggedSession> fixtureSessions() => [
      LoggedSession(DateTime(2026, 11, 20, 18, 30), 3120, [
        LoggedExercise('bench_press', 'Bench press', 'chest', [
          LoggedSet(10, 40, kind: SetKind.warmup),
          LoggedSet(8, 60),
          LoggedSet(8, 62.5, rpe: 9),
        ]),
        LoggedExercise('front_plank', 'Front plank', 'abs', [LoggedSet(0, 0, sec: 60)]),
        LoggedExercise('own_treadmill', 'Treadmill', 'cardio', [LoggedSet(0, 0, sec: 1200, km: 2.5)]),
      ]),
    ];

Map<String, int> fixtureSteps() => {'2026-11-20': 8432, '2026-11-22': 3120};

Map<String, int> fixtureStepsFrom() => {'2026-11-22': 14 * 60 + 5};

List<BodyweightEntry> fixtureBodyweight() => [BodyweightEntry(DateTime(2026, 11, 20, 8), 78.4)];

List<BodyMeasure> fixtureMeasures() => [
      BodyMeasure(DateTime(2026, 11, 20, 8), 'arm', 36.5),
      BodyMeasure(DateTime(2026, 11, 20, 8), 'waist', 82),
    ];

int fixtureRestFor(String id) =>
    fixtureOwnRest[id] ?? (fixtureCardio.contains(id) ? 0 : fixtureGlobalRestSec);

String fixtureExerciseName(String id, String fallback) => fixtureNames[id] ?? fallback;

/// The worked example of the design (20 to 22 Nov 2026); [imperial] gives lb, in and mi.
ProgressReport fixtureReport({
  String language = 'es',
  String? locale,
  bool imperial = false,
  String effort = 'rpe',
  bool wholeHistory = false,
}) =>
    buildProgressReport(
      from: fixtureFrom,
      to: fixtureTo,
      wholeHistory: wholeHistory,
      now: fixtureNow,
      language: language,
      locale: locale ?? (language == 'zh_Hant' ? 'zh_TW' : language),
      units: ReportUnits(
        weight: imperial ? 'lb' : 'kg',
        length: imperial ? 'in' : 'cm',
        distance: imperial ? 'mi' : 'km',
        effort: effort,
      ),
      sessions: fixtureSessions(),
      steps: fixtureSteps(),
      stepsFrom: fixtureStepsFrom(),
      showStepsFrom: true,
      bodyweight: fixtureBodyweight(),
      measures: fixtureMeasures(),
      profileWeightKg: fixtureProfileWeightKg,
      toWeight: (kg) => imperial ? kg * 2.20462 : kg,
      toMeasure: (key, raw) => imperial && key != 'bodyfat' ? raw / 2.54 : raw,
      toDistance: (km) => imperial ? km / 1.609344 : km,
      restFor: fixtureRestFor,
      exerciseName: fixtureExerciseName,
    );
