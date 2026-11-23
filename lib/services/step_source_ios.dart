import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'step_source.dart';
import 'step_source_android.dart' show kStepUpdateInterval;

const int kIosStepDays = 7;

const Duration kIosReadTimeout = Duration(seconds: 15);

/// En las preferencias del telefono, fuera de gymmane_v1 y del ZIP: sin clave = nunca se conto, 0 = contando sin limite,
/// -1 = arranque nuevo pendiente, si no, ms desde el que se cuenta.
const String kIosStepStartKey = 'infyter_steps_ios_start_v1';

const int _noLimit = 0;

const int _pendingStart = -1;

/// Pasos de Core Motion: el Swift da dias enteros; los 7 dias como mucho cada [StepChannel.iosThrottle] o al cambiar de dia, y entre medio solo hoy.
class IosStepSource implements StepSource {
  IosStepSource({
    MethodChannel channel = const MethodChannel(StepChannel.name),
    DateTime Function() clock = DateTime.now,
    Duration throttle = StepChannel.iosThrottle,
    Duration updateInterval = kStepUpdateInterval,
    Duration readTimeout = kIosReadTimeout,
  }) : _channel = channel,
       _clock = clock,
       _throttle = throttle,
       _updateInterval = updateInterval,
       _readTimeout = readTimeout;

  final MethodChannel _channel;
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

  @visibleForTesting
  bool get listening => _lifecycle != null;

  @override
  Stream<void> get updates => _updates.stream;

  @override
  Future<bool> isAvailable() async => await _channel.invokeMethod<bool>(StepChannel.isAvailable) ?? false;

  /// Un permiso negado despues de haber contado deja la marca de arranque nuevo: si se revoca y se vuelve a dar, lo de ese
  /// periodo no entra. Si nunca se conto, la primera activacion conserva sus 7 dias.
  @override
  Future<StepPermission> permission() async {
    final answer = StepChannel.parsePermission(
      await _channel.invokeMethod<String>(StepChannel.permissionStatus),
    );
    if (answer == StepPermission.denied) await _markFreshStart(onlyIfCounted: true);
    return answer;
  }

  @override
  Future<StepPermission> requestPermission() async =>
      StepChannel.parsePermission(await _channel.invokeMethod<String>(StepChannel.requestPermission));

  @override
  Future<List<StepDayReading>> readDays() async {
    final generation = _generation;
    final now = _clock();
    final startMs = await _countingStart(generation, now);
    if (generation != _generation) return const [];
    final full = _needsFull(now);
    final raw = await _channel
        .invokeMethod<Object?>(StepChannel.readDays, {'days': full ? kIosStepDays : 1, 'fromMs': ?startMs})
        .timeout(_readTimeout, onTimeout: () => null);
    if (generation != _generation || raw is! List) return const [];
    if (full) _fullAt = now;
    _tickIfForeground();
    final start = startMs == null ? null : DateTime.fromMillisecondsSinceEpoch(startMs);
    final startDay = start == null ? null : _dayKey(start);
    final startMinute = start == null ? 0 : start.hour * 60 + start.minute;
    return [
      for (final day in StepChannel.parseDays(raw))
        if (startDay == null || day.day.compareTo(startDay) >= 0)
          StepDayReading(
            day.day,
            day.steps,
            fromMinute: day.day == startDay && startMinute > 0 ? startMinute : null,
          ),
    ];
  }

  @override
  Future<void> forget() => _drop();

  @override
  Future<void> stopCounting() => _drop();

  /// Desde cuando se cuenta (null = sin limite: los 7 dias); la primera lectura con la clave vacia guarda 0, y la primera
  /// despues de apagar, de borrar o de un permiso negado fija ahora.
  Future<int?> _countingStart(int generation, DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    if (generation != _generation) return null;
    final stored = prefs.getInt(kIosStepStartKey);
    if (stored == null) {
      await prefs.setInt(kIosStepStartKey, _noLimit);
      return null;
    }
    if (stored == _noLimit) return null;
    final nowMs = now.millisecondsSinceEpoch;
    if (stored > 0 && stored <= nowMs) return stored;
    await prefs.setInt(kIosStepStartKey, nowMs);
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
    final stored = prefs.getInt(kIosStepStartKey);
    if (stored == _pendingStart || (onlyIfCounted && stored == null)) return;
    await prefs.setInt(kIosStepStartKey, _pendingStart);
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
