import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/l10n/app_localizations.dart';
import 'package:infyter/models/progress_report.dart';
import 'package:infyter/models/workout.dart';
import 'package:infyter/services/progress_export/csv_export.dart';
import 'package:infyter/services/progress_export/export_format.dart';
import 'package:infyter/services/progress_export/json_export.dart';
import 'package:infyter/services/progress_export/text_export.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'compartir_progreso_fixture.dart';

String csv(String language, String locale, {bool imperial = false}) => buildCsvExport(
  fixtureReport(language: language, locale: locale, imperial: imperial),
  lookupAppLocalizations(Locale(language)),
  ExportFormat(locale),
);

String json(String language, String locale, {bool imperial = false}) => buildJsonExport(
  fixtureReport(language: language, locale: locale, imperial: imperial),
  ExportFormat(locale),
);

String rows(List<String> lines) => '﻿${lines.map((l) => '$l\r\n').join()}';

List<List<String>> parseCsv(String text, String sep) {
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

ReportSet repsSet() => const ReportSet(
  number: 1,
  kind: SetKind.normal,
  reps: 5,
  weight: null,
  durationSec: null,
  distance: null,
  effort: null,
);

void main() {
  setUpAll(initializeDateFormatting);

  test('golden csv: es uses semicolon and decimal comma', () {
    expect(
      csv('es', 'es'),
      rows([
        'Fecha;Día de la semana;Entrenamiento;Ejercicio;Serie;Tipo de serie;Repeticiones;Peso (kg);Duración (s);Distancia (km);RPE;Descanso configurado (s);Duración del entrenamiento (min);Pasos;Pasos contados desde;kcal activas estimadas;kcal estimadas por pasos;kcal estimadas por entrenamientos;Peso corporal (kg);Brazo (cm);Cintura (cm)',
        '20/11/2026;Viernes;1;Press plano;1;Calentamiento;10;40;;;;90;52;8432;;390;220;170;78,4;36,5;82',
        '20/11/2026;Viernes;1;Press plano;2;Efectiva;8;60;;;;90;52;8432;;390;220;170;78,4;36,5;82',
        '20/11/2026;Viernes;1;Press plano;3;Efectiva;8;62,5;;;9;90;52;8432;;390;220;170;78,4;36,5;82',
        '20/11/2026;Viernes;1;Planchas frontales;1;Efectiva;;;60;;;90;52;8432;;390;220;170;78,4;36,5;82',
        '20/11/2026;Viernes;1;Cinta;1;Efectiva;;;1200;2,5;;0;52;8432;;390;220;170;78,4;36,5;82',
        '22/11/2026;Domingo;;;;;;;;;;;;3120;14:05;80;80;;;;',
      ]),
    );
  });

  test('golden csv: en uses comma and decimal point', () {
    expect(
      csv('en', 'en'),
      rows([
        'Date,Weekday,Workout,Exercise,Set,Set type,Reps,Weight (kg),Duration (s),Distance (km),RPE,Configured rest (s),Workout duration (min),Steps,Steps counted since,Estimated active kcal,Estimated kcal from steps,Estimated kcal from workouts,Bodyweight (kg),Arm (cm),Waist (cm)',
        '11/20/2026,Friday,1,Press plano,1,Warm-up,10,40,,,,90,52,8432,,390,220,170,78.4,36.5,82',
        '11/20/2026,Friday,1,Press plano,2,Working,8,60,,,,90,52,8432,,390,220,170,78.4,36.5,82',
        '11/20/2026,Friday,1,Press plano,3,Working,8,62.5,,,9,90,52,8432,,390,220,170,78.4,36.5,82',
        '11/20/2026,Friday,1,Planchas frontales,1,Working,,,60,,,90,52,8432,,390,220,170,78.4,36.5,82',
        '11/20/2026,Friday,1,Cinta,1,Working,,,1200,2.5,,0,52,8432,,390,220,170,78.4,36.5,82',
        '11/22/2026,Sunday,,,,,,,,,,,,3120,14:05,80,80,,,,',
      ]),
    );
  });

  test('golden csv: de number format with English labels uses semicolon', () {
    expect(
      csv('en', 'de'),
      rows([
        'Date;Weekday;Workout;Exercise;Set;Set type;Reps;Weight (kg);Duration (s);Distance (km);RPE;Configured rest (s);Workout duration (min);Steps;Steps counted since;Estimated active kcal;Estimated kcal from steps;Estimated kcal from workouts;Bodyweight (kg);Arm (cm);Waist (cm)',
        '20.11.2026;Freitag;1;Press plano;1;Warm-up;10;40;;;;90;52;8432;;390;220;170;78,4;36,5;82',
        '20.11.2026;Freitag;1;Press plano;2;Working;8;60;;;;90;52;8432;;390;220;170;78,4;36,5;82',
        '20.11.2026;Freitag;1;Press plano;3;Working;8;62,5;;;9;90;52;8432;;390;220;170;78,4;36,5;82',
        '20.11.2026;Freitag;1;Planchas frontales;1;Working;;;60;;;90;52;8432;;390;220;170;78,4;36,5;82',
        '20.11.2026;Freitag;1;Cinta;1;Working;;;1200;2,5;;0;52;8432;;390;220;170;78,4;36,5;82',
        '22.11.2026;Sonntag;;;;;;;;;;;;3120;14:05;80;80;;;;',
      ]),
    );
  });

  test('golden csv: lb, in and mi', () {
    expect(
      csv('en', 'en', imperial: true),
      rows([
        'Date,Weekday,Workout,Exercise,Set,Set type,Reps,Weight (lb),Duration (s),Distance (mi),RPE,Configured rest (s),Workout duration (min),Steps,Steps counted since,Estimated active kcal,Estimated kcal from steps,Estimated kcal from workouts,Bodyweight (lb),Arm (in),Waist (in)',
        '11/20/2026,Friday,1,Press plano,1,Warm-up,10,88.2,,,,90,52,8432,,390,220,170,172.8,14.4,32.3',
        '11/20/2026,Friday,1,Press plano,2,Working,8,132.3,,,,90,52,8432,,390,220,170,172.8,14.4,32.3',
        '11/20/2026,Friday,1,Press plano,3,Working,8,137.8,,,9,90,52,8432,,390,220,170,172.8,14.4,32.3',
        '11/20/2026,Friday,1,Planchas frontales,1,Working,,,60,,,90,52,8432,,390,220,170,172.8,14.4,32.3',
        '11/20/2026,Friday,1,Cinta,1,Working,,,1200,1.55,,0,52,8432,,390,220,170,172.8,14.4,32.3',
        '11/22/2026,Sunday,,,,,,,,,,,,3120,14:05,80,80,,,,',
      ]),
    );
  });

  test('csv is UTF-8 with BOM and CRLF endings', () {
    final text = csv('es', 'es');
    final bytes = utf8.encode(text);
    expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    expect(bytes.sublist(bytes.length - 2), [13, 10]);
    expect(text.replaceAll('\r\n', '').contains('\n'), isFalse);
  });

  test('golden json: es', () {
    expect(json('es', 'es'), '''
{
  "format": "infyter-progress",
  "version": 1,
  "generatedAt": "2026-11-27T10:15:00",
  "language": "es",
  "period": {
    "from": "2026-11-20",
    "to": "2026-11-22",
    "wholeHistory": false
  },
  "units": {
    "weight": "kg",
    "length": "cm",
    "distance": "km",
    "duration": "s",
    "energy": "kcal",
    "effort": "rpe"
  },
  "caloriesAreEstimates": true,
  "restIsConfiguredNotActual": true,
  "days": [
    {
      "date": "2026-11-20",
      "sessions": [
        {
          "durationMin": 52,
          "exercises": [
            {
              "name": "Press plano",
              "restConfiguredSec": 90,
              "sets": [
                {
                  "n": 1,
                  "kind": "warmup",
                  "reps": 10,
                  "weight": 40,
                  "durationSec": null,
                  "distance": null,
                  "effort": null
                },
                {
                  "n": 2,
                  "kind": "normal",
                  "reps": 8,
                  "weight": 60,
                  "durationSec": null,
                  "distance": null,
                  "effort": null
                },
                {
                  "n": 3,
                  "kind": "normal",
                  "reps": 8,
                  "weight": 62.5,
                  "durationSec": null,
                  "distance": null,
                  "effort": 9
                }
              ]
            },
            {
              "name": "Planchas frontales",
              "restConfiguredSec": 90,
              "sets": [
                {
                  "n": 1,
                  "kind": "normal",
                  "reps": null,
                  "weight": null,
                  "durationSec": 60,
                  "distance": null,
                  "effort": null
                }
              ]
            },
            {
              "name": "Cinta",
              "restConfiguredSec": 0,
              "sets": [
                {
                  "n": 1,
                  "kind": "normal",
                  "reps": null,
                  "weight": null,
                  "durationSec": 1200,
                  "distance": 2.5,
                  "effort": null
                }
              ]
            }
          ]
        }
      ],
      "steps": 8432,
      "stepsCountedFrom": null,
      "kcal": {
        "total": 390,
        "steps": 220,
        "workouts": 170
      },
      "bodyweight": 78.4,
      "measures": {
        "arm": 36.5,
        "waist": 82
      }
    },
    {
      "date": "2026-11-22",
      "sessions": [],
      "steps": 3120,
      "stepsCountedFrom": "14:05",
      "kcal": {
        "total": 80,
        "steps": 80,
        "workouts": null
      },
      "bodyweight": null,
      "measures": {}
    }
  ]
}''');
  });

  test('json imperial carries units and converted raw numbers', () {
    final doc = jsonDecode(json('en', 'en', imperial: true)) as Map<String, dynamic>;
    final units = doc['units'] as Map<String, dynamic>;
    expect([units['weight'], units['length'], units['distance']], ['lb', 'in', 'mi']);
    final first = (doc['days'] as List<dynamic>).first as Map<String, dynamic>;
    expect(first['bodyweight'], 172.8);
    expect(first['measures'], {'arm': 14.4, 'waist': 32.3});
  });

  test('csv quotes fields and guards formulas', () {
    final report = ProgressReport(
      from: fixtureFrom,
      to: fixtureFrom,
      wholeHistory: false,
      generatedAt: fixtureNow,
      language: 'en',
      locale: 'en',
      units: const ReportUnits(weight: 'kg', length: 'cm', distance: 'km', effort: 'rpe'),
      measureKeys: const [],
      days: [
        ReportDay(
          date: fixtureFrom,
          sessions: [
            ReportSession(
              durationMin: null,
              exercises: [
                ReportExercise(name: '=SUM(A1)', restConfiguredSec: 60, sets: [repsSet()]),
                ReportExercise(name: 'Row, "wide"', restConfiguredSec: 60, sets: [repsSet()]),
              ],
            ),
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
    final text = buildCsvExport(report, lookupAppLocalizations(const Locale('en')), ExportFormat('en'));
    final table = parseCsv(text, ',');
    expect(text, contains('"Row, ""wide"""'));
    expect(table[1][3], "'=SUM(A1)");
    expect(table[2][3], 'Row, "wide"');
    expect(table[1].length, table[0].length);
  });

  test('a day without a steps reading stays empty, a read zero stays 0', () {
    ReportDay weightOnly(DateTime date, int? steps) => ReportDay(
      date: date,
      sessions: const [],
      steps: steps,
      stepsFromMinute: null,
      kcalTotal: null,
      kcalSteps: null,
      kcalWorkouts: null,
      bodyweight: 70,
      measures: const {},
    );
    final report = ProgressReport(
      from: fixtureFrom,
      to: fixtureTo,
      wholeHistory: false,
      generatedAt: fixtureNow,
      language: 'en',
      locale: 'en',
      units: const ReportUnits(weight: 'kg', length: 'cm', distance: 'km', effort: 'rpe'),
      measureKeys: const [],
      days: [weightOnly(fixtureFrom, null), weightOnly(fixtureTo, 0)],
    );
    final l = lookupAppLocalizations(const Locale('en'));
    final f = ExportFormat('en');
    final out = buildTextExport(report, l, f);
    expect(RegExp('${l.exportSteps}:').allMatches(out).length, 1);
    expect(out, contains('${l.exportSteps}: 0'));

    final table = parseCsv(buildCsvExport(report, l, f), ',');
    final stepsColumn = table.first.indexOf(l.exportSteps);
    expect(table[1][stepsColumn], '');
    expect(table[2][stepsColumn], '0');

    final days = (jsonDecode(buildJsonExport(report, f)) as Map<String, dynamic>)['days'] as List<dynamic>;
    expect((days[0] as Map<String, dynamic>)['steps'], isNull);
    expect((days[1] as Map<String, dynamic>)['steps'], 0);
  });

  test('csv guards tab and carriage return at the start of a field', () {
    final report = fixtureReport(language: 'en', locale: 'en');
    expect(report.days, isNotEmpty);
    final tabbed = ProgressReport(
      from: report.from,
      to: report.to,
      wholeHistory: false,
      generatedAt: report.generatedAt,
      language: 'en',
      locale: 'en',
      units: report.units,
      measureKeys: const [],
      days: [
        ReportDay(
          date: fixtureFrom,
          sessions: [
            ReportSession(
              durationMin: null,
              exercises: [
                ReportExercise(name: '	x', restConfiguredSec: 0, sets: [repsSet()]),
              ],
            ),
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
    final text = buildCsvExport(tabbed, lookupAppLocalizations(const Locale('en')), ExportFormat('en'));
    expect(text, contains(",'	x,"));
  });

  group('the three formats say the same thing', () {
    for (final (language, locale, imperial) in [
      ('es', 'es', false),
      ('en', 'en', false),
      ('en', 'de', false),
      ('en', 'en', true),
    ]) {
      test('$language/$locale imperial=$imperial', () {
        final report = fixtureReport(language: language, locale: locale, imperial: imperial);
        final l = lookupAppLocalizations(Locale(language));
        final f = ExportFormat(locale);
        final out = buildTextExport(report, l, f);
        final table = parseCsv(buildCsvExport(report, l, f), f.csvSeparator);
        final doc = jsonDecode(buildJsonExport(report, f)) as Map<String, dynamic>;
        final jsonDays = doc['days'] as List<dynamic>;
        final col = {for (var i = 0; i < table.first.length; i++) table.first[i]: i};
        final dataRows = table.skip(1).toList();

        expect(jsonDays.length, report.days.length);
        expect(dataRows.map((r) => r[0]).toSet().length, report.days.length);

        var totalSets = 0;
        for (var i = 0; i < report.days.length; i++) {
          final day = report.days[i];
          final jsonDay = jsonDays[i] as Map<String, dynamic>;
          final csvRows = dataRows.where((r) => r[0] == f.numericDate(day.date)).toList();
          final sets = [
            for (final s in day.sessions)
              for (final e in s.exercises) ...e.sets,
          ];
          final jsonSets = [
            for (final s in jsonDay['sessions'] as List<dynamic>)
              for (final e in (s as Map<String, dynamic>)['exercises'] as List<dynamic>)
                ...((e as Map<String, dynamic>)['sets'] as List<dynamic>),
          ];
          totalSets += sets.length;

          expect(jsonSets.length, sets.length);
          expect(csvRows.where((r) => r[col[l.exportColSet]!].isNotEmpty).length, sets.length);
          expect(out, contains('*${f.dayHeading(day.date)}*'));

          expect(jsonDay['steps'], day.steps);
          expect(csvRows.first[col[l.exportSteps]!], f.plainNumber(day.steps!, decimals: 0));
          expect(out, contains('${l.exportSteps}: ${f.number(day.steps!, decimals: 0)}'));

          expect((jsonDay['kcal'] as Map<String, dynamic>)['total'], day.kcalTotal);
          expect(csvRows.first[col[l.exportColKcal]!], f.plainNumber(day.kcalTotal!, decimals: 0));
          expect(out, contains('≈ ${f.number(day.kcalTotal!, decimals: 0)} kcal'));
        }

        expect(RegExp(r'^  \d+\. ', multiLine: true).allMatches(out).length, totalSets);
        expect(totalSets, 5);
      });
    }
  });
}
