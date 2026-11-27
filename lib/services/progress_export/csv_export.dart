import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/progress_report.dart';
import 'export_format.dart';
import 'report_outline.dart';

String _capitalized(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

const _bom = '\uFEFF';

String _field(String s, String sep) {
  final guarded = s.isNotEmpty && '=+-@\t\r'.contains(s[0]) ? "'$s" : s;
  final needsQuotes =
      guarded.contains(sep) || guarded.contains('"') || guarded.contains('\n') || guarded.contains('\r');
  return needsQuotes ? '"${guarded.replaceAll('"', '""')}"' : guarded;
}

/// Writes one row per set with the day columns repeated, UTF-8 BOM and the separator Excel expects for the locale.
String buildCsvExport(ProgressReport report, AppLocalizations l, ExportFormat f) {
  final sep = f.csvSeparator;
  final u = report.units;
  final rows = <List<String>>[
    [
      l.exportColDate,
      l.exportColWeekday,
      l.exportSession,
      l.exportColExercise,
      l.exportColSet,
      l.exportColKind,
      l.exportColReps,
      l.exportColWeight(u.weight),
      l.exportColSetDuration,
      l.exportColDistance(u.distance),
      effortLabelOf(u),
      l.exportColRest,
      l.exportColSessionMinutes,
      l.exportSteps,
      l.exportColStepsSince,
      l.exportColKcal,
      l.exportColKcalSteps,
      l.exportColKcalWorkouts,
      l.exportColBodyweight(u.weight),
      for (final key in report.measureKeys) '${measureLabelOf(l, key)} (${measureUnitOf(report, key)})',
    ],
  ];

  final weekdayFormat = DateFormat.EEEE(report.locale);
  String num0(num? v) => v == null ? '' : f.plainNumber(v, decimals: 0);
  String num1(num? v) => v == null ? '' : f.plainNumber(v);

  for (final d in report.days) {
    final dayColumns = [
      num0(d.steps),
      d.stepsFromMinute == null ? '' : f.clock(d.stepsFromMinute!),
      num0(d.kcalTotal),
      num0(d.kcalSteps),
      num0(d.kcalWorkouts),
      num1(d.bodyweight),
      for (final key in report.measureKeys) num1(d.measures[key]),
    ];
    final date = f.numericDate(d.date);
    final weekday = _capitalized(f.clean(weekdayFormat.format(d.date)));

    List<String> row(String session, List<String> set, ReportExercise? e, int? minutes) => [
      date,
      weekday,
      session,
      e == null ? '' : f.clean(e.name),
      ...set,
      e == null ? '' : '${e.restConfiguredSec}',
      num0(minutes),
      ...dayColumns,
    ];

    if (d.sessions.isEmpty) rows.add(row('', List.filled(7, ''), null, null));
    for (var i = 0; i < d.sessions.length; i++) {
      final s = d.sessions[i];
      final sets = [
        for (final e in s.exercises)
          for (final set in e.sets) (e, set),
      ];
      if (sets.isEmpty) rows.add(row('${i + 1}', List.filled(7, ''), null, s.durationMin));
      for (final (e, set) in sets) {
        rows.add(
          row(
            '${i + 1}',
            [
              '${set.number}',
              setKindLabelOf(l, set.kind),
              num0(set.reps),
              num1(set.weight),
              set.durationSec == null ? '' : '${set.durationSec}',
              set.distance == null ? '' : f.plainNumber(set.distance!, decimals: 2),
              num1(set.effort),
            ],
            e,
            s.durationMin,
          ),
        );
      }
    }
  }
  return _bom + rows.map((r) => '${r.map((c) => _field(f.clean(c), sep)).join(sep)}\r\n').join();
}
