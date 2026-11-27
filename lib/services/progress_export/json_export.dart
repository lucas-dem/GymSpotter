import 'dart:convert';

import '../../models/progress_report.dart';
import 'export_format.dart';

num? _raw(double? v) => v == null ? null : (v == v.roundToDouble() ? v.toInt() : v);

String _isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _isoSecond(DateTime d) =>
    '${_isoDay(d)}T${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

Map<String, Object?> _set(ReportSet s) => {
  'n': s.number,
  'kind': s.kind.name,
  'reps': s.reps,
  'weight': _raw(s.weight),
  'durationSec': s.durationSec,
  'distance': _raw(s.distance),
  'effort': _raw(s.effort),
};

Map<String, Object?> _day(ReportDay d, ProgressReport report, ExportFormat f) => {
  'date': _isoDay(d.date),
  'sessions': [
    for (final s in d.sessions)
      {
        'durationMin': s.durationMin,
        'exercises': [
          for (final e in s.exercises)
            {
              'name': f.clean(e.name),
              'restConfiguredSec': e.restConfiguredSec,
              'sets': [for (final set in e.sets) _set(set)],
            },
        ],
      },
  ],
  'steps': d.steps,
  'stepsCountedFrom': d.stepsFromMinute == null ? null : f.clock(d.stepsFromMinute!),
  'kcal': d.kcalTotal == null
      ? null
      : {'total': d.kcalTotal, 'steps': d.kcalSteps, 'workouts': d.kcalWorkouts},
  'bodyweight': _raw(d.bodyweight),
  'measures': {
    for (final key in report.measureKeys)
      if (d.measures[key] != null) key: _raw(d.measures[key]),
  },
};

/// Writes the report as indented JSON with raw numbers, ISO dates and null for missing data.
String buildJsonExport(ProgressReport report, ExportFormat f) {
  final u = report.units;
  final doc = {
    'format': 'infyter-progress',
    'version': 1,
    'generatedAt': _isoSecond(report.generatedAt),
    'language': report.language,
    'period': {'from': _isoDay(report.from), 'to': _isoDay(report.to), 'wholeHistory': report.wholeHistory},
    'units': {
      'weight': u.weight,
      'length': u.length,
      'distance': u.distance,
      'duration': 's',
      'energy': 'kcal',
      'effort': u.effort,
    },
    'caloriesAreEstimates': true,
    'restIsConfiguredNotActual': true,
    'days': [for (final d in report.days) _day(d, report, f)],
  };
  return const JsonEncoder.withIndent('  ').convert(doc);
}
