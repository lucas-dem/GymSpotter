import 'workout.dart';

class ReportUnits {
  const ReportUnits({
    required this.weight,
    required this.length,
    required this.distance,
    required this.effort,
  });

  final String weight;
  final String length;
  final String distance;
  final String effort;
}

class ProgressReport {
  const ProgressReport({
    required this.from,
    required this.to,
    required this.wholeHistory,
    required this.generatedAt,
    required this.language,
    required this.locale,
    required this.units,
    required this.measureKeys,
    required this.days,
  });

  final DateTime from;
  final DateTime to;
  final bool wholeHistory;
  final DateTime generatedAt;
  final String language;
  final String locale;
  final ReportUnits units;
  final List<String> measureKeys;
  final List<ReportDay> days;

  bool get isEmpty => days.isEmpty;
}

class ReportDay {
  const ReportDay({
    required this.date,
    required this.sessions,
    required this.steps,
    required this.stepsFromMinute,
    required this.kcalTotal,
    required this.kcalSteps,
    required this.kcalWorkouts,
    required this.bodyweight,
    required this.measures,
  });

  final DateTime date;
  final List<ReportSession> sessions;
  final int? steps;
  final int? stepsFromMinute;
  final int? kcalTotal;
  final int? kcalSteps;
  final int? kcalWorkouts;
  final double? bodyweight;
  final Map<String, double> measures;
}

class ReportSession {
  const ReportSession({required this.durationMin, required this.exercises});

  final int? durationMin;
  final List<ReportExercise> exercises;
}

class ReportExercise {
  const ReportExercise({required this.name, required this.restConfiguredSec, required this.sets});

  final String name;
  final int restConfiguredSec;
  final List<ReportSet> sets;
}

class ReportSet {
  const ReportSet({
    required this.number,
    required this.kind,
    required this.reps,
    required this.weight,
    required this.durationSec,
    required this.distance,
    required this.effort,
  });

  final int number;
  final SetKind kind;
  final int? reps;
  final double? weight;
  final int? durationSec;
  final double? distance;
  final double? effort;
}
