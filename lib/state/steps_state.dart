part of 'fit_state.dart';

const int kDefaultStepGoal = 8000;
const int kMinStepGoal = 1000;
const int kMaxStepGoal = 30000;
const int kStepGoalStep = 500;

enum StepsStatus { unread, off, unavailable, needsPermission, denied, counting }

final RegExp _stepDayKey = RegExp(r'^\d{4}-\d{2}-\d{2}$');

int normalizeStepGoal(num goal) =>
    _roundTo(goal.toDouble(), kStepGoalStep.toDouble()).round().clamp(kMinStepGoal, kMaxStepGoal);

mixin StepsState on FitCore {
  final Map<String, int> steps = {};

  final Map<String, int> stepsFrom = {};

  int stepGoal = kDefaultStepGoal;

  bool stepsOn = false;

  int? stepsAskedAt;

  StepSource stepSource = createStepSource();

  StepsStatus stepsStatus = StepsStatus.unread;

  DateTime? _focusStepsAt;

  /// Opens Progress and asks its steps block to scroll into view when it is built.
  void openProgressOnSteps() {
    if (route != 'progress') _focusStepsAt = DateTime.now();
    goProgress();
  }

  /// True once for a request made in the last few seconds; later requests are stale.
  bool takeFocusSteps() {
    final at = _focusStepsAt;
    _focusStepsAt = null;
    return at != null && DateTime.now().difference(at) < const Duration(seconds: 3);
  }

  Future<void>? _stepsRun;
  int _stepsEpoch = 0;

  /// Mira la fuente y, si se esta contando, mezcla los dias leidos con el maximo; [saveNow] guarda sin esperar.
  Future<void> refreshSteps({bool saveNow = false}) async {
    while (_stepsRun != null) {
      await _stepsRun;
    }
    final run = _refreshStepsOnce(saveNow);
    _stepsRun = run;
    try {
      await run;
    } finally {
      _stepsRun = null;
    }
  }

  /// Activa el conteo, pide el permiso si falta y lee; no activa si el telefono no puede contar.
  Future<void> enableSteps() async {
    final epoch = _stepsEpoch;
    try {
      final source = stepSource;
      if (await source.isAvailable()) {
        final askedAt = DateTime.now().millisecondsSinceEpoch;
        if (await source.permission() != StepPermission.granted) await source.requestPermission();
        if (epoch != _stepsEpoch) return;
        stepsOn = true;
        stepsAskedAt = askedAt;
        unawaited(StepsCardPref.setHidden(false));
        _persist();
        notifyListeners();
      }
    } catch (_) {}
    if (epoch != _stepsEpoch) return;
    await refreshSteps();
  }

  void setStepGoal(int goal) {
    final next = normalizeStepGoal(goal);
    if (next == stepGoal) return;
    stepGoal = next;
    _persist();
    notifyListeners();
  }

  /// Deja de contar sin tocar el historial ni pedir nada al sistema.
  void disableSteps() {
    if (!stepsOn) return;
    stepsOn = false;
    _persist();
    notifyListeners();
    unawaited(stepSource.stopCounting().catchError((Object _) {}));
    unawaited(refreshSteps());
  }

  void _stepsRestored() {
    _stepsEpoch++;
    stepsStatus = StepsStatus.unread;
  }

  Future<void> _refreshStepsOnce(bool saveNow) async {
    final epoch = _stepsEpoch;
    final source = stepSource;
    var changed = false;
    var dataChanged = false;
    try {
      final status = await _stepsStatusOf(source);
      if (epoch != _stepsEpoch) return;
      changed = _setStepsStatus(status);
      if (status == StepsStatus.counting) {
        final days = await source.readDays();
        if (epoch != _stepsEpoch) return;
        dataChanged = _mergeStepDays(days);
        changed = changed || dataChanged;
      }
    } catch (_) {}
    if (saveNow && (dataChanged || _saveDebounce != null)) {
      persistNow();
    } else if (dataChanged) {
      _persist();
    }
    if (changed) notifyListeners();
  }

  Future<StepsStatus> _stepsStatusOf(StepSource source) async {
    if (!await source.isAvailable()) return StepsStatus.unavailable;
    if (!stepsOn) return StepsStatus.off;
    return switch (await source.permission()) {
      StepPermission.granted => StepsStatus.counting,
      StepPermission.denied => StepsStatus.denied,
      StepPermission.notDetermined => StepsStatus.needsPermission,
    };
  }

  bool _setStepsStatus(StepsStatus status) {
    if (status == stepsStatus) return false;
    stepsStatus = status;
    return true;
  }

  bool _mergeStepDays(List<StepDayReading> days) {
    var changed = false;
    for (final reading in days) {
      if (!isPlausibleStepDay(reading.day) || reading.steps < 0 || reading.steps > kMaxStepsPerDay) continue;
      final saved = steps[reading.day];
      if (saved != null && reading.steps <= saved) continue;
      steps[reading.day] = reading.steps;
      final from = reading.fromMinute;
      if (from == null || from < 0 || from >= 1440) {
        stepsFrom.remove(reading.day);
      } else {
        stepsFrom[reading.day] = from;
      }
      changed = true;
    }
    return changed;
  }

  void _clearSteps() {
    _stepsEpoch++;
    stepsStatus = StepsStatus.unread;
    unawaited(stepSource.forget().catchError((Object _) {}));
    steps.clear();
    stepsFrom.clear();
    stepGoal = kDefaultStepGoal;
    stepsOn = false;
    stepsAskedAt = null;
    unawaited(StepsCardPref.setHidden(false));
  }
}

/// Una entrada de `steps` o `stepsFrom`: clave AAAA-MM-DD y entero no negativo; si no, lanza.
MapEntry<String, int> _stepEntry(Object? day, Object? value) {
  if (day is! String || !_stepDayKey.hasMatch(day)) throw FormatException('día inesperado: $day');
  final count = (value as num).toInt();
  if (count < 0) throw FormatException('cantidad negativa: $value');
  return MapEntry(day, count);
}
