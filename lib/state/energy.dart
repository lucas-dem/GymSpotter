import '../models/workout.dart';

const int kMaxSessionSec = 3 * 3600;

class DayKcal {
  const DayKcal({
    required this.weightKg,
    required this.stepsKcal,
    required this.workoutKcal,
  });

  final double weightKg;
  final int stepsKcal;
  final int workoutKcal;

  int get total => roundKcal(stepsKcal + workoutKcal.toDouble());
}

/// Latest saved weight on or before [day]; the profile weight if there is none.
double weightForDay(
  DateTime day,
  List<BodyweightEntry> bodyweight,
  double profileWeightKg,
) {
  final end = DateTime(day.year, day.month, day.day + 1);
  BodyweightEntry? best;
  for (final e in bodyweight) {
    if (e.date.isBefore(end) && (best == null || e.date.isAfter(best.date))) {
      best = e;
    }
  }
  return best?.kg ?? profileWeightKg;
}

double stepsKcal(int steps, double kg) => steps <= 0 ? 0 : steps * kg / 3000;

double sessionKcal(int durationSec, double kg) {
  if (durationSec <= 0) return 0;
  final sec = durationSec > kMaxSessionSec ? kMaxSessionSec : durationSec;
  return 2.5 * kg * sec / 3600;
}

int roundKcal(double kcal) => (kcal / 10).round() * 10;

DayKcal dayKcal({
  required DateTime day,
  required int? steps,
  required List<LoggedSession> sessions,
  required List<BodyweightEntry> bodyweight,
  required double profileWeightKg,
}) {
  final kg = weightForDay(day, bodyweight, profileWeightKg);
  var workout = 0.0;
  for (final s in sessions) {
    if (s.date.year == day.year &&
        s.date.month == day.month &&
        s.date.day == day.day) {
      workout += sessionKcal(s.durationSec, kg);
    }
  }
  return DayKcal(
    weightKg: kg,
    stepsKcal: roundKcal(stepsKcal(steps ?? 0, kg)),
    workoutKcal: roundKcal(workout),
  );
}
