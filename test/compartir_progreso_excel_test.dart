import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/models/progress_report.dart';
import 'package:infyter/services/progress_export/export_format.dart';
import 'package:infyter/services/progress_export/xlsx_export.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'compartir_progreso_fixture.dart';

Excel _roundTrip(ProgressReport report, String lang) {
  final bytes = buildXlsx(report, lookupAppLocalizations(localeOf(lang)), ExportFormat(report.locale));
  return Excel.decodeBytes(bytes);
}

List<Object?> _row(Sheet s, int r) => [
      for (final c in s.rows[r])
        switch (c?.value) {
          null => null,
          IntCellValue(:final value) => value,
          DoubleCellValue(:final value) => value,
          TextCellValue(:final value) => value.text,
          DateCellValue d => d.asDateTimeLocal(),
          final other => other,
        },
    ];

void main() {
  setUpAll(() => initializeDateFormatting());

  test('no sheet name or header carries invisible word-joiners in any language', () {
    for (final lang in appLanguages) {
      final book = _roundTrip(fixtureReport(), lang);
      for (final name in book.tables.keys) {
        expect(name.contains('⁠'), isFalse, reason: '$lang sheet "$name"');
        final sheet = book[name];
        for (final cell in sheet.rows.first) {
          final text = cell?.value is TextCellValue ? (cell!.value as TextCellValue).value.text ?? '' : '';
          expect(text.contains('⁠'), isFalse, reason: '$lang header "$text"');
        }
      }
    }
  });

  test('es: two sheets with headers and every fixture row', () {
    final book = _roundTrip(fixtureReport(), 'es');
    expect(book.tables.keys.toList(), ['Resumen', 'Detalle']);

    final summary = book['Resumen'];
    expect(summary.maxRows, 3);
    expect(_row(summary, 0), [
      'Fecha', 'Día de la semana', 'Entrenamientos', 'Duración del entrenamiento (min)', 'Ejercicios', 'Series', 'Pasos',
      'Pasos contados desde', 'kcal activas estimadas', 'kcal estimadas por pasos',
      'kcal estimadas por entrenamientos', 'Peso corporal (kg)', 'Brazo (cm)', 'Cintura (cm)',
    ]);
    expect(_row(summary, 1), [
      DateTime(2026, 11, 20), 'Viernes', 1, 52, 3, 5, 8432, null, 390, 220, 170, 78.4, 36.5, 82,
    ]);
    expect(_row(summary, 2), [
      DateTime(2026, 11, 22), 'Domingo', 0, null, 0, 0, 3120, '14:05', 80, 80, null, null, null, null,
    ]);

    final detail = book['Detalle'];
    expect(detail.maxRows, 6);
    expect(_row(detail, 0), [
      'Fecha', 'Día de la semana', 'Entrenamiento', 'Ejercicio', 'Serie', 'Tipo de serie', 'Repeticiones', 'Peso (kg)',
      'Duración (s)', 'Distancia (km)', 'RPE', 'Descanso configurado (s)',
    ]);
    final d = DateTime(2026, 11, 20);
    expect(_row(detail, 1), [d, 'Viernes', 1, 'Press plano', 1, 'Calentamiento', 10, 40, null, null, null, 90]);
    expect(_row(detail, 2), [d, 'Viernes', 1, 'Press plano', 2, 'Efectiva', 8, 60, null, null, null, 90]);
    expect(_row(detail, 3), [d, 'Viernes', 1, 'Press plano', 3, 'Efectiva', 8, 62.5, null, null, 9, 90]);
    expect(_row(detail, 4), [d, 'Viernes', 1, 'Planchas frontales', 1, 'Efectiva', null, null, 60, null, null, 90]);
    expect(_row(detail, 5), [d, 'Viernes', 1, 'Cinta', 1, 'Efectiva', null, null, 1200, 2.5, null, 0]);
  });

  test('missing steps stay an empty cell and a read 0 stays 0', () {
    const noMeasures = <String, double>{};
    ProgressReport report(List<ReportDay> days) => ProgressReport(
          from: fixtureFrom,
          to: fixtureTo,
          wholeHistory: false,
          generatedAt: fixtureNow,
          language: 'es',
          locale: 'es',
          units: const ReportUnits(weight: 'kg', length: 'cm', distance: 'km', effort: 'rpe'),
          measureKeys: const [],
          days: days,
        );
    ReportDay day(int d, int? steps) => ReportDay(
          date: DateTime(2026, 11, d),
          sessions: const [],
          steps: steps,
          stepsFromMinute: null,
          kcalTotal: null,
          kcalSteps: null,
          kcalWorkouts: null,
          bodyweight: 70.5,
          measures: noMeasures,
        );
    final summary = _roundTrip(report([day(20, null), day(21, 0)]), 'es')['Resumen'];
    final stepsColumn = summary.rows[0].indexWhere((c) => (c?.value as TextCellValue?)?.value.text == 'Pasos');
    expect(stepsColumn, 6);
    expect(summary.rows[1][stepsColumn]?.value, isNull);
    expect(summary.rows[2][stepsColumn]?.value, const IntCellValue(0));
  });

  test('decimal cells use General, so 40 shows as 40 and 62.5 as 62.5', () {
    final detail = _roundTrip(fixtureReport(), 'es')['Detalle'];
    for (final (row, col) in [(1, 7), (3, 7), (3, 10), (5, 9)]) {
      final cell = detail.rows[row][col]!;
      expect(cell.cellStyle?.numberFormat, NumFormat.standard_0, reason: 'row $row col $col');
    }
    final summary = _roundTrip(fixtureReport(), 'es')['Resumen'];
    expect(summary.rows[1][11]?.cellStyle?.numberFormat, NumFormat.standard_0);
  });

  test('control characters are removed from text cells', () {
    final base = fixtureReport();
    final d = base.days.first;
    final dirty = ProgressReport(
      from: base.from,
      to: base.to,
      wholeHistory: false,
      generatedAt: base.generatedAt,
      language: 'es',
      locale: 'es',
      units: base.units,
      measureKeys: base.measureKeys,
      days: [
        ReportDay(
          date: d.date,
          sessions: [
            ReportSession(durationMin: 1, exercises: [
              ReportExercise(name: 'Pres', restConfiguredSec: 0, sets: d.sessions.first.exercises.first.sets),
            ]),
          ],
          steps: null,
          stepsFromMinute: null,
          kcalTotal: null,
          kcalSteps: null,
          kcalWorkouts: null,
          bodyweight: null,
          measures: const {},
        ),
      ],
    );
    expect(_row(_roundTrip(dirty, 'es')['Detalle'], 1)[3], 'Pres');
  });

  test('en with imperial units: names and unit headers follow the user', () {
    final book = _roundTrip(fixtureReport(language: 'en', imperial: true, effort: 'rir'), 'en');
    expect(book.tables.keys.toList(), ['Summary', 'Detail']);
    expect(_row(book['Summary'], 0).sublist(11), ['Bodyweight (lb)', 'Arm (in)', 'Waist (in)']);
    final head = _row(book['Detail'], 0);
    expect(head[1], 'Weekday');
    expect(_row(book['Detail'], 1)[1], 'Friday');
    expect(head[7], 'Weight (lb)');
    expect(head[9], 'Distance (mi)');
    expect(head[10], 'RIR');
    expect(_row(book['Detail'], 3)[10], 1);
  });

  test('ar sheets are right to left; others are not', () {
    final ar = _roundTrip(fixtureReport(language: 'ar'), 'ar');
    expect(ar.tables.values.every((s) => s.isRTL), isTrue);
    final es = _roundTrip(fixtureReport(), 'es');
    expect(es.tables.values.any((s) => s.isRTL), isFalse);
  });
}
