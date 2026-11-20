part of 'fit_state.dart';

const int kDefaultStepGoal = 8000;
const int kMinStepGoal = 1000;
const int kMaxStepGoal = 30000;
const int kStepGoalStep = 500;

final RegExp _stepDayKey = RegExp(r'^\d{4}-\d{2}-\d{2}$');

int normalizeStepGoal(num goal) =>
    _roundTo(goal.toDouble(), kStepGoalStep.toDouble()).round().clamp(kMinStepGoal, kMaxStepGoal);

mixin StepsState on FitCore {
  final Map<String, int> steps = {};

  final Map<String, int> stepsFrom = {};

  int stepGoal = kDefaultStepGoal;

  bool stepsOn = false;

  int? stepsAskedAt;

  void _clearSteps() {
    steps.clear();
    stepsFrom.clear();
    stepGoal = kDefaultStepGoal;
    stepsOn = false;
  }
}

/// Una entrada de `steps` o `stepsFrom`: clave AAAA-MM-DD y entero no negativo; si no, lanza.
MapEntry<String, int> _stepEntry(Object? day, Object? value) {
  if (day is! String || !_stepDayKey.hasMatch(day)) throw FormatException('día inesperado: $day');
  final count = (value as num).toInt();
  if (count < 0) throw FormatException('cantidad negativa: $value');
  return MapEntry(day, count);
}
