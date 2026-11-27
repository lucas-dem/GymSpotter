import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel_community/excel_community.dart';
import 'package:intl/intl.dart';

import '../../l10n/l10n.dart';
import '../../models/progress_report.dart';
import '../../models/workout.dart';
import 'export_format.dart';

final _headerStyle = CellStyle(bold: true);
final _decimalStyle = CellStyle(numberFormat: NumFormat.standard_0);
final _controlChars = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]');
final _sheetNameForbidden = RegExp(r'[\[\]:*?/\\]');

String _sheetName(String s) {
  final clean = s.replaceAll(_sheetNameForbidden, '').replaceAll(_controlChars, '').trim();
  final name = clean.length > 31 ? clean.substring(0, 31) : clean;
  return name.isEmpty ? 'Sheet' : name;
}

String _kindLabel(AppLocalizations l, SetKind k) => switch (k) {
      SetKind.normal => l.setTypeNormal,
      SetKind.warmup => l.setTypeWarmup,
      SetKind.drop => l.setTypeDrop,
      SetKind.failure => l.setTypeFailure,
      SetKind.restPause => l.setTypeRestPause,
    };

TextCellValue _text(String s) => TextCellValue(s.replaceAll(_controlChars, ''));

CellValue? _int(int? v) => v == null ? null : IntCellValue(v);

CellValue? _double(double? v) => v == null ? null : DoubleCellValue(v);

CellValue? _num(num? v) => v == null ? null : (v is int ? IntCellValue(v) : DoubleCellValue(v.toDouble()));

void _writeSheet(Sheet sheet, List<String> headers, List<List<CellValue?>> rows, List<double> widths) {
  for (var c = 0; c < headers.length; c++) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
    cell.value = _text(headers[c]);
    cell.cellStyle = _headerStyle;
    sheet.setColumnWidth(c, widths[c]);
  }
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      final v = rows[r][c];
      if (v == null) continue;
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1));
      cell.value = v;
      if (v is DoubleCellValue) cell.cellStyle = _decimalStyle;
    }
  }
}

Uint8List buildXlsx(ProgressReport report, AppLocalizations l, ExportFormat f) {
  final u = report.units;
  final book = Excel.createExcel();
  final summaryName = _sheetName(l.exportSheetSummary);
  var detailName = _sheetName(l.exportSheetDetail);
  if (detailName == summaryName) detailName = _sheetName('$detailName 2');
  book.rename(book.getDefaultSheet()!, summaryName);
  final summary = book[summaryName];
  final detail = book[detailName];

  final measureUnit = {for (final k in report.measureKeys) k: k == 'bodyfat' ? '%' : u.length};
  final summaryHeaders = [
    l.exportColDate,
    l.exportColWeekday,
    l.exportColSessions,
    l.exportColSessionMinutes,
    l.exportColExercises,
    l.exportColSets,
    l.exportSteps,
    l.exportColStepsSince,
    l.exportColKcal,
    l.exportColKcalSteps,
    l.exportColKcalWorkouts,
    l.exportColBodyweight(u.weight),
    for (final k in report.measureKeys) '${l.measureName(k)} (${measureUnit[k]})',
  ];
  final weekdayFormat = DateFormat.EEEE(report.locale);
  String weekday(DateTime d) {
    final w = f.clean(weekdayFormat.format(d));
    return w.isEmpty ? w : w[0].toUpperCase() + w.substring(1);
  }

  final summaryRows = <List<CellValue?>>[];
  final detailRows = <List<CellValue?>>[];
  for (final day in report.days) {
    final date = DateCellValue.fromDateTime(day.date);
    final minutes = day.sessions.map((s) => s.durationMin).whereType<int>();
    final exercises = day.sessions.fold<int>(0, (n, s) => n + s.exercises.length);
    final sets = day.sessions.fold<int>(0, (n, s) => n + s.exercises.fold<int>(0, (m, e) => m + e.sets.length));
    final day0 = _text(weekday(day.date));
    summaryRows.add([
      date,
      day0,
      IntCellValue(day.sessions.length),
      minutes.isEmpty ? null : IntCellValue(minutes.reduce((a, b) => a + b)),
      IntCellValue(exercises),
      IntCellValue(sets),
      _int(day.steps),
      day.stepsFromMinute == null ? null : _text(f.clock(day.stepsFromMinute!)),
      _int(day.kcalTotal),
      _int(day.kcalSteps),
      _int(day.kcalWorkouts),
      _double(day.bodyweight),
      for (final k in report.measureKeys) _double(day.measures[k]),
    ]);
    for (var s = 0; s < day.sessions.length; s++) {
      for (final ex in day.sessions[s].exercises) {
        for (final set in ex.sets) {
          detailRows.add([
            date,
            day0,
            IntCellValue(s + 1),
            _text(f.clean(ex.name)),
            IntCellValue(set.number),
            _text(f.clean(_kindLabel(l, set.kind))),
            _int(set.reps),
            _double(set.weight),
            _int(set.durationSec),
            _double(set.distance),
            _num(set.effort),
            IntCellValue(ex.restConfiguredSec),
          ]);
        }
      }
    }
  }

  _writeSheet(summary, summaryHeaders, summaryRows, [
    16, 14, 14, 16, 12, 10, 10, 14, 14, 14, 14, 14,
    for (final _ in report.measureKeys) 14,
  ]);
  _writeSheet(
    detail,
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
      u.effort == 'rir' ? 'RIR' : 'RPE',
      l.exportColRest,
    ],
    detailRows,
    [16, 14, 14, 28, 8, 16, 14, 14, 14, 14, 8, 20],
  );
  final bytes = Uint8List.fromList(book.save()!);
  return report.language == 'ar' ? _rightToLeft(bytes) : bytes;
}

// excel_community does not persist Sheet.isRTL on sheets it renamed or created, so the flag is written into the saved sheets.
Uint8List _rightToLeft(Uint8List xlsx) {
  final out = Archive();
  for (final file in ZipDecoder().decodeBytes(xlsx)) {
    var content = file.content as List<int>;
    if (RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(file.name)) {
      final xml = utf8.decode(content).replaceFirst('<sheetView ', '<sheetView rightToLeft="1" ');
      content = utf8.encode(xml);
    }
    out.add(ArchiveFile(file.name, content.length, content));
  }
  return Uint8List.fromList(ZipEncoder().encode(out));
}
