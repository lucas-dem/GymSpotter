import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/models/progress_report.dart';
import 'package:infyter/models/workout.dart';
import 'package:infyter/services/progress_export/csv_export.dart';
import 'package:infyter/services/progress_export/export_format.dart';
import 'package:infyter/services/progress_export/json_export.dart';
import 'package:infyter/services/progress_export/pdf_export.dart';
import 'package:infyter/services/progress_export/report_outline.dart';
import 'package:infyter/services/progress_export/text_export.dart';
import 'package:infyter/services/progress_export/xlsx_export.dart';
import 'package:infyter/services/progress_report_builder.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'compartir_progreso_fixture.dart';

// ---------------------------------------------------------------- the report

/// The design's worked example plus a day with a workout and no steps (21 Nov)
/// and a day that exists only through bodyweight, with 0 steps read (23 Nov).
ProgressReport _report(String language, {required bool imperial}) => buildProgressReport(
      from: fixtureFrom,
      to: DateTime(2026, 11, 23),
      wholeHistory: false,
      now: fixtureNow,
      language: language,
      locale: language,
      units: ReportUnits(
        weight: imperial ? 'lb' : 'kg',
        length: imperial ? 'in' : 'cm',
        distance: imperial ? 'mi' : 'km',
        effort: 'rpe',
      ),
      sessions: [
        ...fixtureSessions(),
        LoggedSession(DateTime(2026, 11, 21, 9), 1800, [
          LoggedExercise('push_up', 'Push-up', 'chest', [LoggedSet(15, 0), LoggedSet(12, 0)]),
        ]),
      ],
      steps: {...fixtureSteps(), '2026-11-23': 0},
      stepsFrom: fixtureStepsFrom(),
      showStepsFrom: true,
      bodyweight: [...fixtureBodyweight(), BodyweightEntry(DateTime(2026, 11, 23, 8), 77.9)],
      measures: fixtureMeasures(),
      profileWeightKg: fixtureProfileWeightKg,
      toWeight: (kg) => imperial ? kg * 2.20462 : kg,
      toMeasure: (key, raw) => imperial && key != 'bodyfat' ? raw / 2.54 : raw,
      toDistance: (km) => imperial ? km / 1.609344 : km,
      restFor: fixtureRestFor,
      exerciseName: fixtureExerciseName,
    );

// ------------------------------------------------- what every format must say

class SetView {
  const SetView({
    this.name,
    this.n,
    this.kind,
    this.reps,
    this.weight,
    this.sec,
    this.dist,
    this.effort,
    this.rest,
  });
  final String? name;
  final int? n;
  final SetKind? kind;
  final int? reps;
  final double? weight;
  final int? sec;
  final double? dist;
  final double? effort;
  final int? rest;

  SetView named(String name, int n, SetKind kind, int? rest) => SetView(
        name: name,
        n: n,
        kind: kind,
        reps: reps,
        weight: weight,
        sec: sec,
        dist: dist,
        effort: effort,
        rest: rest,
      );
}

class DayView {
  const DayView({
    required this.date,
    required this.sets,
    required this.sessions,
    this.minutes,
    this.steps,
    this.stepsFrom,
    this.kcal,
    this.kcalSteps,
    this.kcalWorkouts,
    this.bodyweight,
    required this.measures,
  });
  final String date;
  final List<SetView> sets;
  final int sessions;
  final int? minutes;
  final int? steps;
  final String? stepsFrom;
  final int? kcal;
  final int? kcalSteps;
  final int? kcalWorkouts;
  final double? bodyweight;
  final List<double?> measures;
}

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

int? _sumMinutes(Iterable<int?> mins) {
  final known = mins.whereType<int>();
  return known.isEmpty ? null : known.fold<int>(0, (a, b) => a + b);
}

List<DayView> _expected(ProgressReport r, ExportFormat f) => [
      for (final d in r.days)
        DayView(
          date: _key(d.date),
          sets: [
            for (final s in d.sessions)
              for (final e in s.exercises)
                for (final set in e.sets)
                  SetView(
                    name: f.clean(e.name),
                    n: set.number,
                    kind: set.kind,
                    reps: set.reps,
                    weight: set.weight,
                    sec: set.durationSec,
                    dist: set.distance,
                    effort: set.effort,
                    rest: e.restConfiguredSec,
                  ),
          ],
          sessions: d.sessions.length,
          minutes: _sumMinutes(d.sessions.map((s) => s.durationMin)),
          steps: d.steps,
          stepsFrom: d.stepsFromMinute == null ? null : f.clock(d.stepsFromMinute!),
          kcal: d.kcalTotal,
          kcalSteps: d.kcalSteps,
          kcalWorkouts: d.kcalWorkouts,
          bodyweight: d.bodyweight,
          measures: [for (final k in r.measureKeys) d.measures[k]],
        ),
    ];

void _near(num? actual, num? wanted, double tol, String why) {
  if (wanted == null) {
    expect(actual, isNull, reason: why);
  } else {
    expect(actual, isNotNull, reason: why);
    expect(actual, closeTo(wanted, tol), reason: why);
  }
}

void _sameDays(String format, List<DayView> got, List<DayView> want) {
  expect(got.map((d) => d.date).toList(), want.map((d) => d.date).toList(), reason: '$format: days and their order');
  for (var i = 0; i < want.length; i++) {
    final a = got[i];
    final e = want[i];
    final w = '$format ${e.date}';
    expect(a.sets.length, e.sets.length, reason: '$w: number of sets');
    for (var j = 0; j < e.sets.length; j++) {
      final x = a.sets[j];
      final y = e.sets[j];
      final s = '$w set ${j + 1}';
      expect(x.name, y.name, reason: '$s exercise name');
      expect(x.n, y.n, reason: '$s number');
      expect(x.kind, y.kind, reason: '$s kind');
      expect(x.reps, y.reps, reason: '$s reps');
      _near(x.weight, y.weight, 0.051, '$s weight');
      expect(x.sec, y.sec, reason: '$s duration');
      _near(x.dist, y.dist, 0.0051, '$s distance');
      _near(x.effort, y.effort, 0.051, '$s effort');
      expect(x.rest, y.rest, reason: '$s rest');
    }
    expect(a.sessions, e.sessions, reason: '$w sessions');
    expect(a.minutes, e.minutes, reason: '$w workout minutes');
    expect(a.steps, e.steps, reason: '$w steps');
    expect(a.stepsFrom, e.stepsFrom, reason: '$w steps counted since');
    expect(a.kcal, e.kcal, reason: '$w kcal');
    expect(a.kcalSteps, e.kcalSteps, reason: '$w kcal steps');
    expect(a.kcalWorkouts, e.kcalWorkouts, reason: '$w kcal workouts');
    _near(a.bodyweight, e.bodyweight, 0.051, '$w bodyweight');
    expect(a.measures.length, e.measures.length, reason: '$w measures');
    for (var k = 0; k < e.measures.length; k++) {
      _near(a.measures[k], e.measures[k], 0.051, '$w measure ${k + 1}');
    }
  }
}

// ----------------------------------------------------------------- Text / PDF

class _Acc {
  _Acc(this.date);
  final String date;
  final sets = <SetView>[];
  int sessions = 0;
  int? minutes;
  String? pendingName;
  int? steps;
  String? stepsFrom;
  int? kcal, kcalSteps, kcalWorkouts;
  double? bodyweight;
  List<double?> measures = [];
}

/// Reads a day-by-day outline written as words (Text or the PDF's extracted words) back into values.
List<DayView> _parseOutline(String raw, ProgressReport r, AppLocalizations l, ExportFormat f) {
  final s = f.clean(raw).replaceAll(RegExp(r'\s+'), ' ');
  const num = r'(\d[\d.,]*\d|\d)';
  final fmt = NumberFormat.decimalPattern(f.locale);
  double n(String v) => fmt.parse(v).toDouble();
  int sec(String v) {
    final p = v.split(':').map(int.parse).toList();
    return p.length == 3 ? p[0] * 3600 + p[1] * 60 + p[2] : p[0] * 60 + p[1];
  }

  String tpl(String text, String group) => RegExp.escape(f.clean(text)).replaceFirst('@@', group);
  final u = r.units;
  final events = <(int, String, RegExpMatch)>[];
  void scan(String kind, String pattern) {
    for (final m in RegExp(pattern).allMatches(s)) {
      events.add((m.start, kind, m));
    }
  }

  final headings = <String, String>{};
  for (var d = r.from; !d.isAfter(r.to); d = DateTime(d.year, d.month, d.day + 1)) {
    headings[f.dayHeading(d)] = _key(d);
  }
  scan('day', '(${headings.keys.map(RegExp.escape).join('|')})');
  scan('session',
      '(?:${tpl(l.exportSessionNumbered(0).replaceFirst('0', '@@'), r'\d+')}|${RegExp.escape(f.clean(l.exportSession))})(?: · ${tpl(l.exportMinutes(0).replaceFirst('0', '@@'), r'(\d+)')})?');
  scan('rest', '${tpl(l.exportRestConfigured('@@'), r'(\d+:\d\d)')}|(${RegExp.escape(f.clean(l.exportRestNone))})');
  scan('set', r'(?<![\w.,])(\d+)\. ');
  scan('steps', '${RegExp.escape(f.clean(l.exportSteps))}: $num(?: \\(${tpl(l.exportStepsSince('@@'), r'(\d{2}:\d{2})')}\\))?');
  scan('kcal', '${RegExp.escape(f.clean(l.exportKcal))}: ≈ $num kcal \\(([^)]*)\\)');
  scan('bw', '${RegExp.escape(f.clean(l.exportBodyweight))}: $num ${RegExp.escape(u.weight)}');
  final alt = [
    for (final k in r.measureKeys)
      '${RegExp.escape(f.clean(measureLabelOf(l, k)))} $num${measureUnitOf(r, k) == '%' ? '%' : ' ${RegExp.escape(measureUnitOf(r, k))}'}',
  ].join('|');
  scan('measures', '${RegExp.escape(f.clean(l.exportMeasures))}: ((?:(?:$alt)(?: · )?)+)');
  events.sort((a, b) => a.$1.compareTo(b.$1));

  final tailRe = RegExp('^(?: \\(([^)]*)\\))?(?: · ${RegExp.escape(effortLabelOf(u))} $num)?');
  final wu = RegExp.escape(u.weight);
  final du = RegExp.escape(u.distance);
  final shapes = <(RegExp, SetView Function(RegExpMatch))>[
    (RegExp('^$num $wu × (\\d+:\\d\\d)'), (m) => SetView(weight: n(m[1]!), sec: sec(m[2]!))),
    (RegExp('^$num $wu × (\\d+)'), (m) => SetView(weight: n(m[1]!), reps: int.parse(m[2]!))),
    (RegExp('^$num $du(?: · (\\d+:\\d\\d))?'), (m) => SetView(dist: n(m[1]!), sec: m[2] == null ? null : sec(m[2]!))),
    (RegExp('^${tpl(l.exportRepsCount(0).replaceFirst('0', '@@'), r'(\d+)')}'), (m) => SetView(reps: int.parse(m[1]!))),
    (RegExp(r'^(\d+:\d\d)'), (m) => SetView(sec: sec(m[1]!))),
    (RegExp('^$num $wu'), (m) => SetView(weight: n(m[1]!))),
  ];
  final kinds = {for (final k in SetKind.values) f.clean(setKindLabelOf(l, k)): k};

  final days = <_Acc>[];
  int? rest;
  var restFresh = false;
  var lastEnd = 0;
  for (final (_, kind, m) in events) {
    if (kind == 'day') {
      days.add(_Acc(headings[m[1]!]!));
      rest = null;
      restFresh = false;
      continue;
    }
    if (days.isEmpty) continue;
    final d = days.last;
    switch (kind) {
      case 'session':
        d.sessions++;
        if (m[1] != null) d.minutes = (d.minutes ?? 0) + int.parse(m[1]!);
        rest = null;
        restFresh = false;
        lastEnd = m.end;
      case 'rest':
        d.pendingName = s.substring(lastEnd, m.start).replaceAll(RegExp(r'^[\s·]+|[\s·]+$'), '');
        rest = m[1] != null ? sec(m[1]!) : 0;
        restFresh = true;
      case 'set':
        final tail = s.substring(m.end);
        for (final (re, build) in shapes) {
          final hit = re.firstMatch(tail);
          if (hit != null) {
            final number = int.parse(m[1]!);
            if (number == 1 && !restFresh) rest = null;
            restFresh = false;
            final after = tail.substring(hit.end);
            final t = tailRe.firstMatch(after)!;
            final base = build(hit);
            final label = t[1] == null ? null : kinds[t[1]!];
            d.sets.add(SetView(
              name: d.pendingName,
              n: number,
              kind: label ?? SetKind.normal,
              reps: base.reps,
              weight: base.weight,
              sec: base.sec,
              dist: base.dist,
              effort: t[2] == null ? null : n(t[2]!),
              rest: rest,
            ));
            lastEnd = m.end + hit.end + t.end;
            break;
          }
        }
      case 'steps':
        d.steps = n(m[1]!).round();
        d.stepsFrom = m[2];
      case 'kcal':
        d.kcal = n(m[1]!).round();
        final sm = RegExp(tpl(l.exportKcalSteps('@@'), num)).firstMatch(m[2]!);
        final wm = RegExp(tpl(l.exportKcalWorkouts('@@'), num)).firstMatch(m[2]!);
        d.kcalSteps = sm == null ? null : n(sm[1]!).round();
        d.kcalWorkouts = wm == null ? null : n(wm[1]!).round();
      case 'bw':
        d.bodyweight = n(m[1]!);
      case 'measures':
        d.measures = [
          for (final k in r.measureKeys)
            () {
              final km = RegExp('${RegExp.escape(f.clean(measureLabelOf(l, k)))} $num').firstMatch(m[1]!);
              return km == null ? null : n(km[1]!);
            }(),
        ];
    }
  }
  return [
    for (final d in days)
      DayView(
        date: d.date,
        sets: d.sets,
        sessions: d.sessions,
        minutes: d.minutes,
        steps: d.steps,
        stepsFrom: d.stepsFrom,
        kcal: d.kcal,
        kcalSteps: d.kcalSteps,
        kcalWorkouts: d.kcalWorkouts,
        bodyweight: d.bodyweight,
        measures: d.measures.isEmpty ? List.filled(r.measureKeys.length, null) : d.measures,
      ),
  ];
}

// ------------------------------------------------------------------------ CSV

List<List<String>> _csvRows(String text, String sep) {
  expect(text.codeUnitAt(0), 0xFEFF);
  final table = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;
  final body = text.substring(1);
  for (var i = 0; i < body.length; i++) {
    final c = body[i];
    if (quoted) {
      if (c == '"' && i + 1 < body.length && body[i + 1] == '"') {
        field.write('"');
        i++;
      } else if (c == '"') {
        quoted = false;
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == sep) {
      row.add(field.toString());
      field = StringBuffer();
    } else if (c == '\n') {
      row.add(field.toString());
      table.add(row);
      row = <String>[];
      field = StringBuffer();
    } else if (c != '\r') {
      field.write(c);
    }
  }
  return table;
}

List<DayView> _fromCsv(String text, ProgressReport r, AppLocalizations l, ExportFormat f) {
  final rows = _csvRows(text, f.csvSeparator);
  expect(rows.first.length, 19 + r.measureKeys.length, reason: 'CSV columns');
  final fmt = NumberFormat.decimalPattern(f.locale);
  num? n(String v) => v.isEmpty ? null : fmt.parse(v);
  final kinds = {for (final k in SetKind.values) setKindLabelOf(l, k): k};
  final order = <String>[];
  final byDate = <String, List<List<String>>>{};
  for (final row in rows.skip(1).where((x) => x.length > 1)) {
    (byDate[row[0]] ??= (() {
      order.add(row[0]);
      return <List<String>>[];
    })()).add(row);
  }
  final dates = DateFormat.yMd(f.locale);
  return [
    for (final date in order)
      () {
        final first = byDate[date]!.first;
        for (final x in byDate[date]!) {
          expect(x.sublist(13), first.sublist(13), reason: 'CSV $date: the day columns repeat in every row');
        }
        final steps = n(first[13])?.toInt();
        if (steps != null) {
          expect(first[13], f.plainNumber(steps, decimals: 0), reason: 'CSV $date: steps without thousands separator');
        }
        final sessionMins = <String, int?>{
          for (final x in byDate[date]!)
            if (x[2].isNotEmpty) x[2]: n(x[12])?.toInt(),
        };
        return DayView(
          date: _key(dates.parse(date)),
          sets: [
            for (final x in byDate[date]!)
              if (x[3].isNotEmpty)
                SetView(
                  name: x[3],
                  n: n(x[4])?.toInt(),
                  kind: kinds[x[5]],
                  reps: n(x[6])?.toInt(),
                  weight: n(x[7])?.toDouble(),
                  sec: n(x[8])?.toInt(),
                  dist: n(x[9])?.toDouble(),
                  effort: n(x[10])?.toDouble(),
                  rest: n(x[11])?.toInt(),
                ),
          ],
          sessions: sessionMins.length,
          minutes: _sumMinutes(sessionMins.values),
          steps: steps,
          stepsFrom: first[14].isEmpty ? null : first[14],
          kcal: n(first[15])?.toInt(),
          kcalSteps: n(first[16])?.toInt(),
          kcalWorkouts: n(first[17])?.toInt(),
          bodyweight: n(first[18])?.toDouble(),
          measures: [for (var k = 0; k < r.measureKeys.length; k++) n(first[19 + k])?.toDouble()],
        );
      }(),
  ];
}

// ------------------------------------------------------------------------ JSON

List<DayView> _fromJson(String text, ProgressReport r) {
  final doc = jsonDecode(text) as Map<String, dynamic>;
  return [
    for (final d in doc['days'] as List)
      DayView(
        date: d['date'] as String,
        sets: [
          for (final se in d['sessions'] as List)
            for (final e in se['exercises'] as List)
              for (final s in e['sets'] as List)
                SetView(
                  name: e['name'] as String?,
                  n: s['n'] as int?,
                  kind: SetKind.values.byName(s['kind'] as String),
                  reps: s['reps'] as int?,
                  weight: (s['weight'] as num?)?.toDouble(),
                  sec: s['durationSec'] as int?,
                  dist: (s['distance'] as num?)?.toDouble(),
                  effort: (s['effort'] as num?)?.toDouble(),
                  rest: e['restConfiguredSec'] as int?,
                ),
        ],
        sessions: (d['sessions'] as List).length,
        minutes: _sumMinutes([for (final se in d['sessions'] as List) se['durationMin'] as int?]),
        steps: d['steps'] as int?,
        stepsFrom: d['stepsCountedFrom'] as String?,
        kcal: d['kcal']['total'] as int?,
        kcalSteps: d['kcal']['steps'] as int?,
        kcalWorkouts: d['kcal']['workouts'] as int?,
        bodyweight: (d['bodyweight'] as num?)?.toDouble(),
        measures: [for (final k in r.measureKeys) ((d['measures'] as Map)[k] as num?)?.toDouble()],
      ),
  ];
}

// ------------------------------------------------------------------------ XLSX

num? _num(Sheet s, int r, int c) {
  final row = s.rows[r];
  if (c >= row.length) return null;
  return switch (row[c]?.value) {
    IntCellValue(:final value) => value,
    DoubleCellValue(:final value) => value,
    _ => null,
  };
}

String? _text(Sheet s, int r, int c) {
  final row = s.rows[r];
  if (c >= row.length) return null;
  return switch (row[c]?.value) {
    TextCellValue(:final value) => value.text,
    _ => null,
  };
}

String _dateOf(Sheet s, int r) => _key((s.rows[r][0]!.value as DateCellValue).asDateTimeLocal());

List<DayView> _fromXlsx(Uint8List bytes, ProgressReport r, AppLocalizations l, ExportFormat f) {
  final book = Excel.decodeBytes(bytes);
  final names = book.tables.keys.toList();
  expect(names, [f.clean(l.exportSheetSummary), f.clean(l.exportSheetDetail)], reason: 'Excel sheet names');
  final kinds = {for (final k in SetKind.values) setKindLabelOf(l, k): k};
  final summary = book[names[0]];
  final detail = book[names[1]];
  final sets = <String, List<SetView>>{};
  for (var i = 1; i < detail.maxRows; i++) {
    (sets[_dateOf(detail, i)] ??= []).add(SetView(
      name: _text(detail, i, 3),
      n: _num(detail, i, 4)?.toInt(),
      kind: kinds[_text(detail, i, 5)],
      reps: _num(detail, i, 6)?.toInt(),
      weight: _num(detail, i, 7)?.toDouble(),
      sec: _num(detail, i, 8)?.toInt(),
      dist: _num(detail, i, 9)?.toDouble(),
      effort: _num(detail, i, 10)?.toDouble(),
      rest: _num(detail, i, 11)?.toInt(),
    ));
  }
  return [
    for (var i = 1; i < summary.maxRows; i++)
      () {
        final date = _dateOf(summary, i);
        final mine = sets[date] ?? const <SetView>[];
        expect(_num(summary, i, 5), mine.length, reason: 'Resumen Series of $date');
        return DayView(
          date: date,
          sets: mine,
          sessions: _num(summary, i, 2)!.toInt(),
          minutes: _num(summary, i, 3)?.toInt(),
          steps: _num(summary, i, 6)?.toInt(),
          stepsFrom: _text(summary, i, 7),
          kcal: _num(summary, i, 8)?.toInt(),
          kcalSteps: _num(summary, i, 9)?.toInt(),
          kcalWorkouts: _num(summary, i, 10)?.toInt(),
          bodyweight: _num(summary, i, 11)?.toDouble(),
          measures: [for (var k = 0; k < r.measureKeys.length; k++) _num(summary, i, 12 + k)?.toDouble()],
        );
      }(),
  ];
}

// ------------------------------------------------------------------------ PDF

PdfFonts _fonts() => PdfFonts(
      regular: File(kPdfFontAssets.regular).readAsBytesSync(),
      bold: File(kPdfFontAssets.bold).readAsBytesSync(),
      italic: File(kPdfFontAssets.italic).readAsBytesSync(),
    );

String _latin(Uint8List b) => latin1.decode(b);

Uint8List _streamOf(Uint8List b, String text, int obj) {
  final m = RegExp('(?:^|\\n)$obj 0 obj\\n<<[^\\n]*?>>stream\\r?\\n').firstMatch(text)!;
  final end = text.indexOf('endstream', m.end);
  final raw = b.sublist(m.end, end);
  return text.substring(m.start, m.end).contains('FlateDecode') ? Uint8List.fromList(zlib.decode(raw)) : raw;
}

Map<int, String> _toUnicode(String cmap) {
  final out = <int, String>{};
  String uni(String hex) => String.fromCharCodes([
        for (var i = 0; i < hex.length; i += 4) int.parse(hex.substring(i, i + 4), radix: 16),
      ]);
  for (final block in RegExp(r'beginbfchar([\s\S]*?)endbfchar').allMatches(cmap)) {
    for (final m in RegExp(r'<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>').allMatches(block.group(1)!)) {
      out[int.parse(m.group(1)!, radix: 16)] = uni(m.group(2)!);
    }
  }
  for (final block in RegExp(r'beginbfrange([\s\S]*?)endbfrange').allMatches(cmap)) {
    for (final m in RegExp(r'<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>').allMatches(block.group(1)!)) {
      final lo = int.parse(m.group(1)!, radix: 16);
      final hi = int.parse(m.group(2)!, radix: 16);
      final start = uni(m.group(3)!).runes.first;
      for (var c = lo; c <= hi; c++) {
        out[c] = String.fromCharCode(start + c - lo);
      }
    }
  }
  return out;
}

/// Reads the words back from the PDF through each font's ToUnicode map, with no extra package.
List<String> _pdfWords(Uint8List b) {
  final text = _latin(b);
  final maps = <String, Map<int, String>>{};
  for (final obj in text.split('endobj')) {
    final name = RegExp(r'/Name/(F\d+)').firstMatch(obj)?.group(1);
    final ref = RegExp(r'/ToUnicode (\d+) 0 R').firstMatch(obj)?.group(1);
    if (name != null && ref != null) {
      maps[name] = _toUnicode(latin1.decode(_streamOf(b, text, int.parse(ref))));
    }
  }
  final words = <String>[];
  for (final page in RegExp(r'/Type/Page/[^\n]*?/Contents (\d+) 0 R').allMatches(text)) {
    final content = latin1.decode(_streamOf(b, text, int.parse(page.group(1)!)));
    for (final run in RegExp(r'/(F\d+) [\d.]+ Tf[^\[]*\[([^\]]*)\]\s*TJ').allMatches(content)) {
      final map = maps[run.group(1)!]!;
      final sb = StringBuffer();
      for (final h in RegExp(r'<([0-9a-fA-F]+)>').allMatches(run.group(2)!)) {
        final hex = h.group(1)!;
        for (var i = 0; i < hex.length; i += 4) {
          sb.write(map[int.parse(hex.substring(i, i + 4), radix: 16)] ?? '�');
        }
      }
      words.add(sb.toString());
    }
  }
  return words;
}

// ------------------------------------------------------------------------ main

void main() {
  late PdfFonts fonts;

  setUpAll(() async {
    await initializeDateFormatting();
    fonts = _fonts();
  });

  for (final c in [('es', false, 'kg/cm/km'), ('en', true, 'lb/in/mi')]) {
    final lang = c.$1;
    group('$lang ${c.$3}: the five formats say the same thing', () {
      late ProgressReport report;
      late AppLocalizations l;
      late ExportFormat f;
      late List<DayView> want;

      setUp(() {
        report = _report(lang, imperial: c.$2);
        l = lookupAppLocalizations(localeOf(lang));
        f = ExportFormat(report.locale);
        want = _expected(report, f);
      });

      test('the report has the days this test needs', () {
        expect(want.map((d) => d.date), ['2026-11-20', '2026-11-21', '2026-11-22', '2026-11-23']);
        expect(want.map((d) => d.sets.length), [5, 2, 0, 0]);
        expect(want[1].steps, isNull, reason: 'a day with no steps read');
        expect(want[3].steps, 0, reason: 'a day with 0 steps read, there through bodyweight');
        expect(want[3].bodyweight, isNotNull);
        expect(want[0].measures.whereType<double>(), hasLength(2));
        expect(report.units.weight, c.$2 ? 'lb' : 'kg');
      });

      void emptyAndZero(String format, List<DayView> got) {
        expect(got[1].steps, isNull, reason: '$format: no steps stays empty');
        expect(got[3].steps, 0, reason: '$format: 0 steps stays 0');
      }

      test('Text', () {
        final got = _parseOutline(buildTextExport(report, l, f), report, l, f);
        _sameDays('Text', got, want);
        emptyAndZero('Text', got);
      });

      test('CSV', () {
        final got = _fromCsv(buildCsvExport(report, l, f), report, l, f);
        _sameDays('CSV', got, want);
        emptyAndZero('CSV', got);
      });

      test('JSON', () {
        final got = _fromJson(buildJsonExport(report, f), report);
        _sameDays('JSON', got, want);
        emptyAndZero('JSON', got);
      });

      test('Excel', () {
        final got = _fromXlsx(buildXlsx(report, l, f), report, l, f);
        _sameDays('Excel', got, want);
        emptyAndZero('Excel', got);
      });

      test('PDF', () async {
        final bytes = await buildPdf(report, l, f, fonts);
        final got = _parseOutline(_pdfWords(bytes).join(' '), report, l, f);
        _sameDays('PDF', got, want);
        emptyAndZero('PDF', got);
      });
    });
  }
}
