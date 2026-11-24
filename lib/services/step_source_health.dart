import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'step_source.dart';
import 'step_source_android.dart' show kStepUpdateInterval;

/// Canal de Health Connect (Android 14 o superior): supported, permissionStatus, requestPermission, readDays y openSettings.
/// readDays recibe {days: 1..7, fromMs: int opcional} y devuelve [{day, steps}] como el readDays de iOS: un item por dia local
/// con dato, del mas viejo al de hoy; un dia sin dato, con 0 o cuya consulta falla no se manda.
const String kHealthStepsChannel = 'infyter/health_steps';

const int kHealthStepDays = 7;

const Duration kHealthStepThrottle = Duration(minutes: 5);

const Duration kHealthReadTimeout = Duration(seconds: 15);

/// En las preferencias del telefono, fuera de gymmane_v1 y del ZIP, con los valores de la marca de iOS: sin clave = nunca se
/// conto, 0 = contando sin limite, -1 = arranque nuevo pendiente, si no, ms desde el que se cuenta.
const String kHealthStepStartKey = 'infyter_steps_hc_start_v1';

const int _noLimit = 0;

const int _pendingStart = -1;

/// Pasos que Health Connect cuenta en el telefono, aunque la app este cerrada. Se leen solo en primer plano, dias enteros y
/// sin "desde": el rotulo de dia parcial es del sensor.
class HealthConnectStepSource implements StepSource, HealthConnectSteps {
  HealthConnectStepSource({
    MethodChannel channel = const MethodChannel(kHealthStepsChannel),
    MethodChannel sensorChannel = const MethodChannel(StepChannel.name),
    DateTime Function() clock = DateTime.now,
    Duration throttle = kHealthStepThrottle,
    Duration updateInterval = kStepUpdateInterval,
    Duration readTimeout = kHealthReadTimeout,
  }) : _channel = channel,
       _sensorChannel = sensorChannel,
       _clock = clock,
       _throttle = throttle,
       _updateInterval = updateInterval,
       _readTimeout = readTimeout;

  final MethodChannel _channel;
  final MethodChannel _sensorChannel;
  final DateTime Function() _clock;
  final Duration _throttle;
  final Duration _updateInterval;
  final Duration _readTimeout;
  final StreamController<void> _updates = StreamController<void>.broadcast();

  DateTime? _fullAt;
  int _generation = 0;
  Timer? _ticker;
  AppLifecycleListener? _lifecycle;

  @visibleForTesting
  bool get ticking => _ticker != null;

  @override
  Stream<void> get updates => _updates.stream;

  @override
  Future<bool> isAvailable() async => await _channel.invokeMethod<bool>('supported') ?? false;

  /// Un permiso negado despues de haber contado deja la marca de arranque nuevo, como en iOS.
  @override
  Future<StepPermission> permission() async {
    final answer = StepChannel.parsePermission(await _channel.invokeMethod<String>('permissionStatus'));
    if (answer == StepPermission.denied) await _markFreshStart(onlyIfCounted: true);
    return answer;
  }

  @override
  Future<StepPermission> requestPermission() async =>
      StepChannel.parsePermission(await _channel.invokeMethod<String>('requestPermission'));

  @override
  Future<List<StepDayReading>> readDays() async {
    if (_inBackground()) return const [];
    final generation = _generation;
    final now = _clock();
    final startMs = await _countingStart(generation, now);
    if (generation != _generation) return const [];
    final full = _needsFull(now);
    final raw = await _channel
        .invokeMethod<Object?>('readDays', {'days': full ? kHealthStepDays : 1, 'fromMs': ?startMs})
        .timeout(_readTimeout, onTimeout: () => null);
    if (generation != _generation || raw is! List) return const [];
    if (full) _fullAt = now;
    _tickIfForeground();
    final startDay = startMs == null ? null : _dayKey(DateTime.fromMillisecondsSinceEpoch(startMs));
    return [
      for (final day in StepChannel.parseDays(raw))
        if (startDay == null || day.day.compareTo(startDay) >= 0) StepDayReading(day.day, day.steps),
    ];
  }

  /// Ademas de la marca, borra el ancla que haya dejado el sensor antes de esta version.
  @override
  Future<void> forget() async {
    await _drop();
    await _sensorChannel.invokeMethod<void>(StepChannel.clearAnchor);
  }

  @override
  Future<void> stopCounting() => _drop();

  @override
  Future<bool> openHealthConnect() async => await _channel.invokeMethod<bool>('openSettings') ?? false;

  bool _inBackground() => switch (WidgetsBinding.instance.lifecycleState) {
    AppLifecycleState.paused || AppLifecycleState.hidden || AppLifecycleState.detached => true,
    _ => false,
  };

  Future<int?> _countingStart(int generation, DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    if (generation != _generation) return null;
    final stored = prefs.getInt(kHealthStepStartKey);
    if (stored == null) {
      await prefs.setInt(kHealthStepStartKey, _noLimit);
      return null;
    }
    if (stored == _noLimit) return null;
    final nowMs = now.millisecondsSinceEpoch;
    if (stored > 0 && stored <= nowMs) return stored;
    await prefs.setInt(kHealthStepStartKey, nowMs);
    return nowMs;
  }

  bool _needsFull(DateTime now) {
    final last = _fullAt;
    if (last == null) return true;
    final since = now.difference(last);
    if (since.isNegative || since >= _throttle) return true;
    return last.year != now.year || last.month != now.month || last.day != now.day;
  }

  Future<void> _drop() async {
    _generation++;
    _fullAt = null;
    _stopTicking();
    await _markFreshStart();
  }

  Future<void> _markFreshStart({bool onlyIfCounted = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(kHealthStepStartKey);
    if (stored == _pendingStart || (onlyIfCounted && stored == null)) return;
    await prefs.setInt(kHealthStepStartKey, _pendingStart);
  }

  void _tickIfForeground() {
    if (_ticker != null || WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    _ticker = Timer.periodic(_updateInterval, (_) => _updates.add(null));
  }

  void _onLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || state == AppLifecycleState.inactive) return;
    _stopTicking();
  }

  void _stopTicking() {
    _ticker?.cancel();
    _ticker = null;
    _lifecycle?.dispose();
    _lifecycle = null;
  }
}

String _dayKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
