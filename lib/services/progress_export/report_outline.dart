import '../../l10n/app_localizations.dart';
import '../../models/progress_report.dart';
import '../../models/workout.dart';
import 'export_format.dart';

enum OutlineKind { title, period, units, dayHeading, session, exercise, set, fact, note, footer }

class OutlineBlock {
  const OutlineBlock(this.kind, this.text, [this.detail]);

  final OutlineKind kind;
  final String text;
  final String? detail;

  @override
  bool operator ==(Object other) =>
      other is OutlineBlock && other.kind == kind && other.text == text && other.detail == detail;

  @override
  int get hashCode => Object.hash(kind, text, detail);

  @override
  String toString() => '${kind.name}($text${detail == null ? '' : ' | $detail'})';
}

String setKindLabelOf(AppLocalizations l, SetKind kind) => switch (kind) {
  SetKind.warmup => l.setTypeWarmup,
  SetKind.drop => l.setTypeDrop,
  SetKind.failure => l.setTypeFailure,
  SetKind.restPause => l.setTypeRestPause,
  SetKind.normal => l.setTypeNormal,
};

String measureLabelOf(AppLocalizations l, String key) => switch (key) {
  'neck' => l.measureNeck,
  'shoulders' => l.measureShoulders,
  'chest' => l.measureChest,
  'arm' => l.measureArm,
  'forearm' => l.measureForearm,
  'waist' => l.measureWaist,
  'hips' => l.measureHips,
  'thigh' => l.measureThigh,
  'calf' => l.measureCalf,
  _ => l.measureBodyfat,
};

String measureUnitOf(ProgressReport report, String key) => key == 'bodyfat' ? '%' : report.units.length;

String effortLabelOf(ReportUnits units) => units.effort.toUpperCase();

/// Writes one set as a line without its number: "62,5 kg × 8 · RPE 9".
String setLine(ReportSet s, ReportUnits units, AppLocalizations l, ExportFormat f) {
  final weight = s.weight == null ? null : '${f.number(s.weight!)} ${units.weight}';
  final duration = s.durationSec == null ? null : f.duration(s.durationSec!);
  var body = switch ((s.distance, weight, s.reps, duration)) {
    (final double d, _, _, _) => ['${f.number(d, decimals: 2)} ${units.distance}', ?duration].join(' · '),
    (_, final String w, final int r, _) => '$w × $r',
    (_, final String w, _, final String d) => '$w × $d',
    (_, final String w, _, _) => w,
    (_, _, final int r, _) => l.exportRepsCount(r),
    (_, _, _, final String d) => d,
    _ => '–',
  };
  if (s.kind != SetKind.normal) body += ' (${setKindLabelOf(l, s.kind)})';
  if (s.effort != null) body += ' · ${effortLabelOf(units)} ${f.number(s.effort!)}';
  return body;
}

String _kcalValue(ReportDay d, AppLocalizations l, ExportFormat f) {
  String kcal(int v) => f.number(v, decimals: 0);
  final parts = [
    if (d.kcalSteps != null) l.exportKcalSteps(kcal(d.kcalSteps!)),
    if (d.kcalWorkouts != null) l.exportKcalWorkouts(kcal(d.kcalWorkouts!)),
  ];
  return '≈ ${kcal(d.kcalTotal!)} kcal (${parts.join(' · ')})';
}

/// The ordered blocks that Text and PDF both draw, so they say the same thing.
List<OutlineBlock> buildReportOutline(ProgressReport report, AppLocalizations l, ExportFormat f) {
  final from = f.shortDate(report.from);
  final to = f.shortDate(report.to);
  final u = report.units;
  OutlineBlock block(OutlineKind kind, String text, [String? detail]) =>
      OutlineBlock(kind, f.clean(text), detail == null ? null : f.clean(detail));
  final blocks = <OutlineBlock>[
    block(OutlineKind.title, l.exportDocTitle),
    block(OutlineKind.period, report.wholeHistory ? l.exportPeriodWhole(from, to) : l.exportPeriod(from, to)),
    block(OutlineKind.units, l.exportUnits('${u.weight}, ${u.length}, ${u.distance}')),
  ];
  for (final d in report.days) {
    blocks.add(block(OutlineKind.dayHeading, f.dayHeading(d.date)));
    for (var i = 0; i < d.sessions.length; i++) {
      final s = d.sessions[i];
      final name = d.sessions.length > 1 ? l.exportSessionNumbered(i + 1) : l.exportSession;
      final minutes = s.durationMin == null ? '' : ' · ${l.exportMinutes(s.durationMin!)}';
      blocks.add(block(OutlineKind.session, '$name$minutes'));
      for (final e in s.exercises) {
        final rest = e.restConfiguredSec > 0
            ? l.exportRestConfigured(f.duration(e.restConfiguredSec))
            : l.exportRestNone;
        blocks.add(block(OutlineKind.exercise, f.clean(e.name), rest));
        for (final set in e.sets) {
          blocks.add(block(OutlineKind.set, '${set.number}. ${f.clean(setLine(set, u, l, f))}'));
        }
      }
    }
    if (d.steps != null) {
      final since = d.stepsFromMinute == null ? '' : ' (${l.exportStepsSince(f.clock(d.stepsFromMinute!))})';
      blocks.add(block(OutlineKind.fact, l.exportSteps, '${f.number(d.steps!, decimals: 0)}$since'));
    }
    if (d.kcalTotal != null) {
      blocks.add(block(OutlineKind.fact, l.exportKcal, _kcalValue(d, l, f)));
    }
    if (d.bodyweight != null) {
      blocks.add(block(OutlineKind.fact, l.exportBodyweight, '${f.number(d.bodyweight!)} ${u.weight}'));
    }
    final measures = [
      for (final key in report.measureKeys)
        if (d.measures[key] != null)
          '${measureLabelOf(l, key)} ${f.number(d.measures[key]!)}'
              '${measureUnitOf(report, key) == '%' ? '%' : ' ${measureUnitOf(report, key)}'}',
    ];
    if (measures.isNotEmpty) {
      blocks.add(block(OutlineKind.fact, l.exportMeasures, f.clean(measures.join(' · '))));
    }
  }
  blocks
    ..add(block(OutlineKind.note, l.exportNoteKcal))
    ..add(block(OutlineKind.note, l.exportNoteRest))
    ..add(block(OutlineKind.footer, l.exportMadeWith));
  return blocks;
}
