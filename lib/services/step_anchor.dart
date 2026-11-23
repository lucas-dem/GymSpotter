import 'step_source.dart';

/// Clave del ancla en las preferencias nativas `infyter_steps` (`ANCHOR` en StepCounter.kt); Dart la lee y escribe por el canal.
const String kStepAnchorKey = 'infyter_steps_anchor_v1';

const int kMaxStepsPerSecond = 4;

/// Cuanto antes de la medianoche del dia del ancla puede quedar el reloj (hora automatica) sin que se corte el tramo.
const int kClockBackToleranceMs = 5 * 60 * 1000;

class StepLocalTime {
  const StepLocalTime(this.day, this.minute, this.offsetMinutes);

  final String day;
  final int minute;
  final int offsetMinutes;
}

typedef StepLocalClock = StepLocalTime Function(int wallMs);

StepLocalTime deviceLocalTime(int wallMs) {
  final t = DateTime.fromMillisecondsSinceEpoch(wallMs);
  final day = '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}';
  return StepLocalTime(day, t.hour * 60 + t.minute, t.timeZoneOffset.inMinutes);
}

String _two(int n) => n.toString().padLeft(2, '0');

class StepAnchor {
  const StepAnchor({
    required this.counter,
    required this.wallMs,
    required this.elapsedMs,
    required this.bootCount,
    required this.day,
    required this.offsetMinutes,
    required this.steps,
    this.fromMinute,
  });

  final int counter;
  final int wallMs;
  final int elapsedMs;
  final int bootCount;
  final String day;
  final int offsetMinutes;
  final int steps;
  final int? fromMinute;

  StepDayReading get reading => StepDayReading(day, steps, fromMinute: fromMinute);

  Map<String, Object> toJson() => {
    'c': counter,
    't': wallMs,
    'e': elapsedMs,
    'b': bootCount,
    'day': day,
    'tz': offsetMinutes,
    'acc': steps,
    'f': ?fromMinute,
  };

  /// El ancla guardada, o null si falta o no se entiende: en ese caso la proxima lectura abre un tramo nuevo.
  static StepAnchor? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final c = raw['c'], t = raw['t'], e = raw['e'], b = raw['b'];
    final day = raw['day'], tz = raw['tz'], acc = raw['acc'], f = raw['f'];
    if (c is! int || t is! int || e is! int || b is! int || tz is! int || acc is! int) return null;
    if (day is! String || !isPlausibleStepDay(day) || c < 0 || e < 0 || acc < 0) return null;
    return StepAnchor(
      counter: c,
      wallMs: t,
      elapsedMs: e,
      bootCount: b,
      day: day,
      offsetMinutes: tz,
      steps: acc,
      fromMinute: f is int && f > 0 && f < 1440 ? f : null,
    );
  }
}

/// Aplica la regla de "nunca inventar": suma a [anchor] solo los pasos que seguro son de su dia y devuelve el ancla nueva.
StepAnchor advanceStepAnchor(
  StepAnchor? anchor,
  StepCounterReading reading, {
  StepLocalClock localTime = deviceLocalTime,
}) {
  final now = localTime(reading.wallMs);
  StepAnchor next(String day, int steps, int? fromMinute) => StepAnchor(
    counter: reading.counter,
    wallMs: reading.wallMs,
    elapsedMs: reading.elapsedMs,
    bootCount: reading.bootCount,
    day: day,
    offsetMinutes: now.offsetMinutes,
    steps: steps,
    fromMinute: fromMinute,
  );
  final fresh = next(now.day, 0, now.minute == 0 ? null : now.minute);
  if (anchor == null || anchor.offsetMinutes != now.offsetMinutes) return fresh;
  final rebooted = _rebooted(anchor, reading);
  final dayWentBack =
      !rebooted &&
      now.day.compareTo(anchor.day) < 0 &&
      localTime(reading.wallMs + kClockBackToleranceMs).day == anchor.day;
  if (anchor.day != now.day && !dayWentBack) return fresh;
  return next(
    anchor.day,
    anchor.steps + _stepsSince(anchor, reading, rebooted, localTime),
    anchor.fromMinute,
  );
}

bool _rebooted(StepAnchor anchor, StepCounterReading reading) {
  final bootChanged =
      anchor.bootCount != -1 && reading.bootCount != -1 && anchor.bootCount != reading.bootCount;
  return bootChanged || reading.counter < anchor.counter || reading.elapsedMs < anchor.elapsedMs;
}

int _stepsSince(StepAnchor anchor, StepCounterReading reading, bool rebooted, StepLocalClock localTime) {
  if (!rebooted) {
    final delta = reading.counter - anchor.counter;
    return _believable(delta, reading.elapsedMs - anchor.elapsedMs) ? delta : 0;
  }
  if (reading.counter >= anchor.counter) return 0;
  final bootWallMs = reading.wallMs - reading.elapsedMs;
  final boot = localTime(bootWallMs);
  final bootInSameDay = boot.day == anchor.day && boot.offsetMinutes == anchor.offsetMinutes;
  if (!bootInSameDay || bootWallMs < anchor.wallMs) return 0;
  return _believable(reading.counter, reading.elapsedMs) ? reading.counter : 0;
}

bool _believable(int steps, int elapsedMs) =>
    steps >= 0 && elapsedMs >= 0 && steps * 1000 <= elapsedMs * kMaxStepsPerSecond;
