import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'step_anchor.dart';
import 'step_source.dart';

const Duration kStepUpdateInterval = Duration(seconds: 60);

/// Pasos del sensor del telefono Android: el Kotlin da lecturas crudas y la regla de ancla decide a que dia van.
class AndroidStepSource implements StepSource {
  AndroidStepSource({
    MethodChannel channel = const MethodChannel(StepChannel.name),
    EventChannel events = const EventChannel(StepChannel.eventsName),
    StepLocalClock localTime = deviceLocalTime,
    Duration updateInterval = kStepUpdateInterval,
  }) : _channel = channel,
       _events = events,
       _localTime = localTime,
       _updateInterval = updateInterval;

  final MethodChannel _channel;
  final EventChannel _events;
  final StepLocalClock _localTime;
  final Duration _updateInterval;
  final StreamController<void> _updates = StreamController<void>.broadcast();
  final Map<String, StepDayReading> _unreported = {};

  StepAnchor? _anchor;
  bool _loaded = false;
  int _generation = 0;
  StreamSubscription<dynamic>? _watch;
  bool _watchHeard = false;
  AppLifecycleListener? _lifecycle;
  Timer? _cooldown;
  bool _updatePending = false;

  @visibleForTesting
  StepAnchor? get anchor => _anchor;

  @visibleForTesting
  bool get watching => _watch != null;

  @override
  Stream<void> get updates => _updates.stream;

  @override
  Future<bool> isAvailable() async => await _channel.invokeMethod<bool>(StepChannel.isAvailable) ?? false;

  @override
  Future<StepPermission> permission() async =>
      StepChannel.parsePermission(await _channel.invokeMethod<String>(StepChannel.permissionStatus));

  @override
  Future<StepPermission> requestPermission() async =>
      StepChannel.parsePermission(await _channel.invokeMethod<String>(StepChannel.requestPermission));

  @override
  Future<List<StepDayReading>> readDays() async {
    final generation = _generation;
    await _load(generation);
    if (generation != _generation) return const [];
    if (!(_watch != null && _watchHeard)) {
      final reading = StepCounterReading.fromMap(
        await _channel.invokeMethod<Object?>(StepChannel.readCounter),
      );
      if (generation != _generation) return const [];
      if (reading != null) _apply(reading);
    }
    await _save(generation);
    if (generation != _generation) return const [];
    _watchIfForeground();
    final current = _anchor;
    if (current != null) _unreported.putIfAbsent(current.day, () => current.reading);
    final days = _unreported.values.toList()..sort((a, b) => a.day.compareTo(b.day));
    _unreported.clear();
    return days;
  }

  @override
  Future<void> forget() async {
    _drop();
    await _channel.invokeMethod<void>(StepChannel.forget);
  }

  @override
  Future<void> stopCounting() async {
    _drop();
    await _channel.invokeMethod<void>(StepChannel.clearAnchor);
  }

  void _drop() {
    _generation++;
    _stopWatching();
    _anchor = null;
    _loaded = true;
    _unreported.clear();
  }

  Future<void> _load(int generation) async {
    if (_loaded) return;
    final raw = await _channel.invokeMethod<String>(StepChannel.loadAnchor);
    if (generation != _generation || _loaded) return;
    _anchor = raw == null ? null : StepAnchor.fromJson(_decode(raw));
    _loaded = true;
  }

  Future<void> _save(int generation) async {
    final current = _anchor;
    if (current == null || generation != _generation) return;
    await _channel.invokeMethod<void>(StepChannel.saveAnchor, {'anchor': jsonEncode(current.toJson())});
  }

  void _apply(StepCounterReading reading) {
    if (reading.counter < 0 || reading.elapsedMs < 0) return;
    final next = advanceStepAnchor(_anchor, reading, localTime: _localTime);
    _anchor = next;
    _unreported[next.day] = next.reading;
  }

  void _watchIfForeground() {
    if (_watch != null || WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    _lifecycle ??= AppLifecycleListener(onStateChange: _onLifecycle);
    _watchHeard = false;
    _watch = _events.receiveBroadcastStream().listen(_onEvent, onError: (Object _) => _stopWatching());
  }

  void _onLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || state == AppLifecycleState.inactive || _watch == null) return;
    _stopWatching();
    unawaited(_save(_generation).catchError((Object _) {}));
  }

  void _onEvent(Object? raw) {
    final reading = StepCounterReading.fromMap(raw);
    if (reading == null) return;
    _watchHeard = true;
    final dayBefore = _anchor?.day;
    _apply(reading);
    // Al cambiar de dia avisa ya, sin esperar el intervalo: lo ultimo de ayer solo esta en memoria hasta que readDays lo entrega.
    if (dayBefore != null && _anchor?.day != dayBefore) {
      _updates.add(null);
    } else {
      _announce();
    }
  }

  void _announce() {
    if (_cooldown != null) {
      _updatePending = true;
      return;
    }
    _updates.add(null);
    _cooldown = Timer(_updateInterval, () {
      _cooldown = null;
      if (!_updatePending) return;
      _updatePending = false;
      _announce();
    });
  }

  void _stopWatching() {
    unawaited(_watch?.cancel());
    _watch = null;
    _watchHeard = false;
    _cooldown?.cancel();
    _cooldown = null;
    _updatePending = false;
  }
}

Object? _decode(String raw) {
  try {
    return jsonDecode(raw);
  } on FormatException {
    return null;
  }
}
