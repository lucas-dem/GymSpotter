import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/l10n/app_localizations.dart';
import 'package:infyter/services/progress_export/export_format.dart';
import 'package:infyter/services/progress_export/text_export.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'compartir_progreso_fixture.dart';

String text({required String language, required String locale, bool imperial = false}) => buildTextExport(
  fixtureReport(language: language, locale: locale, imperial: imperial),
  lookupAppLocalizations(Locale(language)),
  ExportFormat(locale),
);

void main() {
  setUpAll(initializeDateFormatting);

  test('golden text: es, decimal comma', () {
    expect(text(language: 'es', locale: 'es'), '''
*Infyter · Progreso*
Del 20 nov 2026 al 22 nov 2026
Unidades: kg, cm, km

*Viernes, 20 de noviembre de 2026*
Entrenamiento · 52 min
Press plano · descanso configurado 1:30
  1. 40 kg × 10 (Calentamiento)
  2. 60 kg × 8
  3. 62,5 kg × 8 · RPE 9
Planchas frontales · descanso configurado 1:30
  1. 1:00
Cinta · sin descanso configurado
  1. 2,5 km · 20:00
Pasos: 8.432
Calorías activas estimadas: ≈ 390 kcal (pasos ≈ 220 · entrenamientos ≈ 170)
Peso corporal: 78,4 kg
Medidas: Brazo 36,5 cm · Cintura 82 cm

*Domingo, 22 de noviembre de 2026*
Pasos: 3.120 (desde las 14:05)
Calorías activas estimadas: ≈ 80 kcal (pasos ≈ 80)

_Las calorías son activas y estimadas, con el peso anotado más reciente de cada día (o el del perfil). No son un dato médico._
_El descanso es el configurado hoy para cada ejercicio: Infyter no guarda el descanso real de cada serie._
Hecho con Infyter''');
  });

  test('golden text: en, decimal point', () {
    expect(text(language: 'en', locale: 'en'), '''
*Infyter · Progress*
From Nov 20, 2026 to Nov 22, 2026
Units: kg, cm, km

*Friday, November 20, 2026*
Workout · 52 min
Press plano · configured rest 1:30
  1. 40 kg × 10 (Warm-up)
  2. 60 kg × 8
  3. 62.5 kg × 8 · RPE 9
Planchas frontales · configured rest 1:30
  1. 1:00
Cinta · no rest configured
  1. 2.5 km · 20:00
Steps: 8,432
Estimated active calories: ≈ 390 kcal (steps ≈ 220 · workouts ≈ 170)
Bodyweight: 78.4 kg
Measurements: Arm 36.5 cm · Waist 82 cm

*Sunday, November 22, 2026*
Steps: 3,120 (since 14:05)
Estimated active calories: ≈ 80 kcal (steps ≈ 80)

_Calories are active and estimated, using the latest weight logged on or before each day (or your profile weight). They are not medical data._
_Rest is what is configured today for each exercise: Infyter does not store the actual rest of each set._
Made with Infyter''');
  });

  test('golden text: de number format with English labels, decimal comma', () {
    expect(text(language: 'en', locale: 'de'), '''
*Infyter · Progress*
From 20. Nov. 2026 to 22. Nov. 2026
Units: kg, cm, km

*Freitag, 20. November 2026*
Workout · 52 min
Press plano · configured rest 1:30
  1. 40 kg × 10 (Warm-up)
  2. 60 kg × 8
  3. 62,5 kg × 8 · RPE 9
Planchas frontales · configured rest 1:30
  1. 1:00
Cinta · no rest configured
  1. 2,5 km · 20:00
Steps: 8.432
Estimated active calories: ≈ 390 kcal (steps ≈ 220 · workouts ≈ 170)
Bodyweight: 78,4 kg
Measurements: Arm 36,5 cm · Waist 82 cm

*Sonntag, 22. November 2026*
Steps: 3.120 (since 14:05)
Estimated active calories: ≈ 80 kcal (steps ≈ 80)

_Calories are active and estimated, using the latest weight logged on or before each day (or your profile weight). They are not medical data._
_Rest is what is configured today for each exercise: Infyter does not store the actual rest of each set._
Made with Infyter''');
  });

  test('golden text: lb, in and mi', () {
    expect(text(language: 'en', locale: 'en', imperial: true), '''
*Infyter · Progress*
From Nov 20, 2026 to Nov 22, 2026
Units: lb, in, mi

*Friday, November 20, 2026*
Workout · 52 min
Press plano · configured rest 1:30
  1. 88.2 lb × 10 (Warm-up)
  2. 132.3 lb × 8
  3. 137.8 lb × 8 · RPE 9
Planchas frontales · configured rest 1:30
  1. 1:00
Cinta · no rest configured
  1. 1.55 mi · 20:00
Steps: 8,432
Estimated active calories: ≈ 390 kcal (steps ≈ 220 · workouts ≈ 170)
Bodyweight: 172.8 lb
Measurements: Arm 14.4 in · Waist 32.3 in

*Sunday, November 22, 2026*
Steps: 3,120 (since 14:05)
Estimated active calories: ≈ 80 kcal (steps ≈ 80)

_Calories are active and estimated, using the latest weight logged on or before each day (or your profile weight). They are not medical data._
_Rest is what is configured today for each exercise: Infyter does not store the actual rest of each set._
Made with Infyter''');
  });

  test('a day with no sessions has no workout lines and steps without data are omitted', () {
    final report = fixtureReport(language: 'es', locale: 'es');
    final out = text(language: 'es', locale: 'es');
    expect(report.days.length, 2);
    expect(out.contains('Pasos: 0'), isFalse);
    expect('Entrenamiento'.allMatches(out).length, 1);
  });

  test('RIR scale shows RIR', () {
    final out = buildTextExport(
      fixtureReport(language: 'en', locale: 'en', effort: 'rir'),
      lookupAppLocalizations(const Locale('en')),
      ExportFormat('en'),
    );
    expect(out, contains('62.5 kg × 8 · RIR 1'));
  });
}
