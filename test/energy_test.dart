import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/models/workout.dart';
import 'package:infyter/state/energy.dart';

void main() {
  final day = DateTime(2026, 11, 20, 9);

  group('weightForDay', () {
    test('uses the latest entry on or before the day', () {
      final entries = [
        BodyweightEntry(DateTime(2026, 11, 25), 90),
        BodyweightEntry(DateTime(2026, 11, 20, 22), 80),
        BodyweightEntry(DateTime(2026, 11, 1), 70),
      ];
      expect(weightForDay(day, entries, 75), 80);
      expect(weightForDay(DateTime(2026, 11, 10), entries, 75), 70);
    });

    test('falls back to the profile weight', () {
      expect(weightForDay(day, [], 75), 75);
      expect(
        weightForDay(day, [BodyweightEntry(DateTime(2026, 12, 1), 90)], 72.5),
        72.5,
      );
    });
  });

  group('kcal', () {
    test('8000 steps at 75 kg is about 200', () {
      expect(stepsKcal(8000, 75), closeTo(200, 0.001));
      expect(roundKcal(stepsKcal(8000, 75)), 200);
    });

    test('60 min at 75 kg is about 190', () {
      expect(sessionKcal(3600, 75), closeTo(187.5, 0.001));
      expect(roundKcal(sessionKcal(3600, 75)), 190);
    });

    test('a 5 h session counts 3 h', () {
      expect(sessionKcal(5 * 3600, 75), sessionKcal(3 * 3600, 75));
      expect(sessionKcal(3 * 3600, 75), closeTo(562.5, 0.001));
    });

    test('a session without duration adds nothing', () {
      expect(sessionKcal(0, 75), 0);
      expect(sessionKcal(-5, 75), 0);
    });

    test('rounds to the nearest 10', () {
      expect(roundKcal(204.9), 200);
      expect(roundKcal(205), 210);
      expect(roundKcal(0), 0);
    });
  });

  group('dayKcal', () {
    test('adds steps and that day\'s sessions with the historic weight', () {
      final bw = [
        BodyweightEntry(DateTime(2026, 11, 1), 60),
        BodyweightEntry(DateTime(2026, 11, 20), 75),
      ];
      final sessions = [
        LoggedSession(DateTime(2026, 11, 20, 18), 3600, []),
        LoggedSession(DateTime(2026, 11, 19, 18), 3600, []),
        LoggedSession(DateTime(2026, 11, 20, 7), 0, []),
      ];
      final r = dayKcal(
        day: day,
        steps: 8000,
        sessions: sessions,
        bodyweight: bw,
        profileWeightKg: 99,
      );
      expect(r.weightKg, 75);
      expect(r.stepsKcal, 200);
      expect(r.workoutKcal, 190);
      expect(r.total, 390);
    });

    test('null steps count as zero and the profile weight is the fallback', () {
      final r = dayKcal(
        day: day,
        steps: null,
        sessions: [LoggedSession(day, 3600, [])],
        bodyweight: const [],
        profileWeightKg: 75,
      );
      expect(r.stepsKcal, 0);
      expect(r.total, 190);
    });
  });
}
