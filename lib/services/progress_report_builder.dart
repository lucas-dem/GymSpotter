import '../models/measure.dart';
import '../models/progress_report.dart';
import '../models/workout.dart';
import '../state/energy.dart';
import '../state/steps_range.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

double _round1(double n) => (n * 10).round() / 10;

double _round2(double n) => (n * 100).round() / 100;

DateTime? _stepsDay(String key) {
  final d = DateTime.tryParse(key);
  return d == null ? null : _day(d);
}

/// Builds the export model for the days between [from] and [to], or for everything logged when [wholeHistory] is on.
ProgressReport buildProgressReport({
  required DateTime from,
  required DateTime to,
  required bool wholeHistory,
  required DateTime now,
  required String language,
  required String locale,
  required ReportUnits units,
  required List<LoggedSession> sessions,
  required Map<String, int> steps,
  required Map<String, int> stepsFrom,
  required bool showStepsFrom,
  required List<BodyweightEntry> bodyweight,
  required List<BodyMeasure> measures,
  required double profileWeightKg,
  required double Function(double kg) toWeight,
  required double Function(String key, double raw) toMeasure,
  required double Function(double km) toDistance,
  required int Function(String exerciseId) restFor,
  required String Function(String id, String fallback) exerciseName,
}) {
  final span = wholeHistory
      ? recordedSpan(sessions: sessions, steps: steps, bodyweight: bodyweight, measures: measures)
      : null;
  final start = _day(span?.from ?? from);
  final end = _day(span?.to ?? to);
  bool inside(DateTime d) => !d.isBefore(start) && !d.isAfter(end);

  final sessionsByDay = <DateTime, List<LoggedSession>>{};
  for (final s in sessions) {
    final d = _day(s.date);
    if (inside(d)) (sessionsByDay[d] ??= []).add(s);
  }
  final bodyweightByDay = <DateTime, BodyweightEntry>{};
  for (final e in bodyweight) {
    final d = _day(e.date);
    final kept = bodyweightByDay[d];
    if (inside(d) && (kept == null || !e.date.isBefore(kept.date))) bodyweightByDay[d] = e;
  }
  final measuresByDay = <DateTime, Map<String, BodyMeasure>>{};
  for (final m in measures) {
    final d = _day(m.date);
    if (!inside(d) || !kMeasureKeys.contains(m.key)) continue;
    final day = measuresByDay[d] ??= {};
    final kept = day[m.key];
    if (kept == null || !m.date.isBefore(kept.date)) day[m.key] = m;
  }

  final dates = {...sessionsByDay.keys, ...bodyweightByDay.keys, ...measuresByDay.keys};
  for (final e in steps.entries) {
    final d = _stepsDay(e.key);
    if (e.value > 0 && d != null && inside(d)) dates.add(d);
  }

  ReportSet set(LoggedSet s, int number) => ReportSet(
        number: number,
        kind: s.kind,
        reps: s.reps > 0 ? s.reps : null,
        weight: s.weight > 0 ? _round1(toWeight(s.weight)) : null,
        durationSec: s.sec,
        distance: (s.km ?? 0) > 0 ? _round2(toDistance(s.km!)) : null,
        effort: s.rpe == null ? null : (units.effort == 'rir' ? 10 - s.rpe! : s.rpe),
      );

  ReportSession session(LoggedSession s) => ReportSession(
        durationMin: s.durationSec > 0 ? (s.durationSec / 60).round() : null,
        exercises: [
          for (final e in s.exercises)
            if (e.sets.isNotEmpty)
              ReportExercise(
                name: exerciseName(e.id, e.name),
                restConfiguredSec: restFor(e.id),
                sets: [for (var i = 0; i < e.sets.length; i++) set(e.sets[i], i + 1)],
              ),
        ],
      );

  ReportDay day(DateTime d) {
    final daySessions = [...?sessionsByDay[d]]..sort((a, b) => a.date.compareTo(b.date));
    final key = stepsDayKey(d);
    final count = steps[key];
    final kcal = dayKcal(
      day: d,
      steps: count,
      sessions: daySessions,
      bodyweight: bodyweight,
      profileWeightKg: profileWeightKg,
    );
    final kcalSteps = count == null ? null : kcal.stepsKcal;
    final kcalWorkouts = daySessions.isEmpty ? null : kcal.workoutKcal;
    final weight = bodyweightByDay[d];
    final dayMeasures = measuresByDay[d] ?? const {};
    return ReportDay(
      date: d,
      sessions: [for (final s in daySessions) session(s)],
      steps: count,
      stepsFromMinute: count != null && showStepsFrom ? stepsFrom[key] : null,
      kcalTotal: kcalSteps == null && kcalWorkouts == null ? null : kcal.total,
      kcalSteps: kcalSteps,
      kcalWorkouts: kcalWorkouts,
      bodyweight: weight == null ? null : _round1(toWeight(weight.kg)),
      measures: {
        for (final k in kMeasureKeys)
          if (dayMeasures[k] != null) k: _round1(toMeasure(k, dayMeasures[k]!.value)),
      },
    );
  }

  final days = [for (final d in dates.toList()..sort()) day(d)];
  final usedKeys = {for (final d in days) ...d.measures.keys};
  return ProgressReport(
    from: start,
    to: end,
    wholeHistory: wholeHistory,
    generatedAt: now,
    language: language,
    locale: locale,
    units: units,
    measureKeys: kMeasureKeys.where(usedKeys.contains).toList(),
    days: days,
  );
}

/// First and last day with any logged data; null when nothing was ever logged.
({DateTime from, DateTime to})? recordedSpan({
  required List<LoggedSession> sessions,
  required Map<String, int> steps,
  required List<BodyweightEntry> bodyweight,
  required List<BodyMeasure> measures,
}) {
  final dates = <DateTime>[
    for (final s in sessions) _day(s.date),
    for (final e in steps.entries)
      if (e.value > 0) ?_stepsDay(e.key),
    for (final e in bodyweight) _day(e.date),
    for (final m in measures)
      if (kMeasureKeys.contains(m.key)) _day(m.date),
  ];
  if (dates.isEmpty) return null;
  dates.sort();
  return (from: dates.first, to: dates.last);
}
