// Reimportar el mismo historial después de actualizar no duplica sesiones (sesión 27, decisión 2e de Braian).
// En 1.3.1, "Bíceps en polea" no tenía alias: se importaba con un id provisorio ("imp:…"). Ahora el alias lo encuentra
// en el catálogo con otro id, y la clave de duplicados (fecha + id y cantidad de series de cada ejercicio) dejaba de
// coincidir. Ahora, para las sesiones ya guardadas, los ids provisorios se resuelven con los nombres de hoy antes de
// comparar. Un ejercicio distinto con las mismas series sigue siendo otra sesión.
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/models/workout.dart';
import 'package:infyter/services/workout_import.dart';
import 'package:infyter/state/fit_state.dart';

void main() {
  setUp(() => fit.sessions.clear());

  final dia = DateTime(2026, 9, 14, 18, 30);

  ParsedSession importada(String nombre, List<(int, double)> series) => ParsedSession(dia, 0)
    ..exercises.add(
      ParsedExercise(nombre, null)..sets.addAll([for (final s in series) ParsedSet(s.$1, s.$2)]),
    );

  // Así quedó guardada en 1.3.1 la sesión importada con "Bíceps en polea".
  void guardadaEn131(List<(int, double)> series) => fit.sessions.add(
    LoggedSession(dia, 0, [
      LoggedExercise('imp:biceps-en-polea', 'Bíceps en polea', 'biceps', [
        for (final s in series) LoggedSet(s.$1, s.$2),
      ]),
    ]),
  );

  test('una sesión importada en 1.3.1 con id provisorio no se duplica al reimportarla', () {
    guardadaEn131([(12, 20), (10, 22.5)]);

    expect(
      fit.importParsedSessions([
        importada('Bíceps en polea', [(12, 20), (10, 22.5)]),
      ]),
      0,
    );
    expect(fit.sessions, hasLength(1));
  });

  test('guardia: hoy "Bíceps en polea" se importa con el ejercicio del catálogo', () {
    expect(
      fit.importParsedSessions([
        importada('Bíceps en polea', [(12, 20)]),
      ]),
      1,
    );
    expect(fit.sessions.single.exercises.single.id, isNot(startsWith('imp:')));
  });

  test('guardia: en el mismo momento pero con otra cantidad de series, es otra sesión', () {
    guardadaEn131([(12, 20), (10, 22.5)]);

    expect(
      fit.importParsedSessions([
        importada('Bíceps en polea', [(12, 20), (10, 22.5), (8, 25)]),
      ]),
      1,
    );
    expect(fit.sessions, hasLength(2));
  });

  test('en el mismo momento y con las mismas series, otro ejercicio es otra sesión', () {
    guardadaEn131([(12, 20), (10, 22.5)]);

    expect(
      fit.importParsedSessions([
        importada('Barbell Curl', [(12, 20), (10, 22.5)]),
      ]),
      1,
    );
    expect(fit.sessions, hasLength(2));
  });

  test('dos entrenos distintos del mismo día, con las mismas series, se importan los dos', () {
    final empuje = importada('Push-up', [(10, 0), (10, 0)]);
    final tiron = importada('Pull-up', [(10, 0), (10, 0)]);

    expect(fit.importParsedSessions([empuje, tiron]), 2);
  });

  test('guardia: reimportar lo mismo, sin cambios de nombre, sigue sin duplicar', () {
    final sesion = importada('Barbell Bench Press', [(10, 60), (8, 62.5)]);

    expect(fit.importParsedSessions([sesion]), 1);
    expect(fit.importParsedSessions([sesion]), 0);
  });
}
