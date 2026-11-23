import '../models/workout.dart';
import 'energy.dart';

enum StepsSpan { week, month, year }

class StepsBar {
  const StepsBar({required this.date, required this.value, this.partial = false});

  final DateTime date;
  final double? value;
  final bool partial;
}

class StepsPeriod {
  const StepsPeriod({
    required this.bars,
    required this.average,
    required this.daysWithData,
    required this.goalDays,
    required this.stepsKcal,
    required this.workoutKcal,
  });

  final List<StepsBar> bars;
  final int? average;
  final int daysWithData;
  final int goalDays;
  final int stepsKcal;
  final int workoutKcal;

  int get totalKcal => stepsKcal + workoutKcal;
  bool get hasPartial => bars.any((b) => b.partial);
}

String stepsDayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Days that have a stored reading are real data; a missing day is a gap, never 0. The 12-month bars are daily averages per month.
StepsPeriod stepsPeriod({
  required StepsSpan span,
  required DateTime today,
  required Map<String, int> steps,
  required Map<String, int> stepsFrom,
  required int goal,
  required List<LoggedSession> sessions,
  required List<BodyweightEntry> bodyweight,
  required double profileWeightKg,
}) {
  final end = DateTime(today.year, today.month, today.day);
  final start = switch (span) {
    StepsSpan.week => DateTime(end.year, end.month, end.day - 6),
    StepsSpan.month => DateTime(end.year, end.month, end.day - 29),
    StepsSpan.year => DateTime(end.year, end.month - 11, 1),
  };

  var sum = 0;
  var withData = 0;
  var reached = 0;
  var stepsKcalTotal = 0;
  final days = <DateTime>[];
  final values = <DateTime, int>{};
  for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) {
    days.add(d);
    final n = steps[stepsDayKey(d)];
    if (n == null) continue;
    values[d] = n;
    sum += n;
    withData++;
    if (n >= goal) reached++;
    stepsKcalTotal += roundKcal(stepsKcal(n, weightForDay(d, bodyweight, profileWeightKg)));
  }

  var workoutKcalTotal = 0;
  final perDay = <DateTime, double>{};
  for (final s in sessions) {
    final d = DateTime(s.date.year, s.date.month, s.date.day);
    if (d.isBefore(start) || d.isAfter(end)) continue;
    perDay[d] = (perDay[d] ?? 0) + sessionKcal(s.durationSec, weightForDay(d, bodyweight, profileWeightKg));
  }
  for (final v in perDay.values) {
    workoutKcalTotal += roundKcal(v);
  }

  final bars = <StepsBar>[];
  if (span == StepsSpan.year) {
    for (var i = 0; i < 12; i++) {
      final month = DateTime(start.year, start.month + i, 1);
      var monthSum = 0;
      var monthDays = 0;
      for (final e in values.entries) {
        if (e.key.year == month.year && e.key.month == month.month) {
          monthSum += e.value;
          monthDays++;
        }
      }
      bars.add(StepsBar(date: month, value: monthDays == 0 ? null : monthSum / monthDays));
    }
  } else {
    for (final d in days) {
      final n = values[d];
      bars.add(
        StepsBar(date: d, value: n?.toDouble(), partial: n != null && stepsFrom.containsKey(stepsDayKey(d))),
      );
    }
  }

  return StepsPeriod(
    bars: bars,
    average: withData == 0 ? null : (sum / withData).round(),
    daysWithData: withData,
    goalDays: reached,
    stepsKcal: stepsKcalTotal,
    workoutKcal: workoutKcalTotal,
  );
}
