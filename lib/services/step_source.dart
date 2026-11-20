import 'dart:async';

import 'package:flutter/foundation.dart';

const int kMaxStepsPerDay = 345600;

final RegExp _stepDay = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

bool isPlausibleStepDay(String day) {
  final m = _stepDay.firstMatch(day);
  if (m == null) return false;
  final year = int.parse(m[1]!);
  final month = int.parse(m[2]!);
  final d = int.parse(m[3]!);
  return year >= 2000 && year <= DateTime.now().year + 1 && month >= 1 && month <= 12 && d >= 1 && d <= 31;
}

enum StepPermission { granted, denied, notDetermined }

class StepDayReading {
  const StepDayReading(this.day, this.steps, {this.fromMinute});

  final String day;
  final int steps;
  final int? fromMinute;
}

class StepCounterReading {
  const StepCounterReading({
    required this.counter,
    required this.wallMs,
    required this.elapsedMs,
    required this.bootCount,
  });

  final int counter;
  final int wallMs;
  final int elapsedMs;
  final int bootCount;

  static StepCounterReading? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final counter = raw['counter'];
    final wallMs = raw['wallMs'];
    final elapsedMs = raw['elapsedMs'];
    if (counter is! num || wallMs is! num || elapsedMs is! num) return null;
    final boot = raw['bootCount'];
    return StepCounterReading(
      counter: counter.toInt(),
      wallMs: wallMs.toInt(),
      elapsedMs: elapsedMs.toInt(),
      bootCount: boot is num ? boot.toInt() : -1,
    );
  }
}

/// Contrato del canal de plataforma que siguen Android (readCounter) e iOS (readDays).
class StepChannel {
  StepChannel._();

  /// MethodChannel; el canal solo existe en el telefono: el reloj Wear OS no tiene AppShell y no llama a isAvailable.
  static const name = 'infyter/steps';

  /// EventChannel solo de Android: eventos con el mapa de readCounter, sin permiso no emite; Dart hace listen en primer plano y cancel en segundo.
  static const eventsName = 'infyter/steps/events';

  /// Sin argumentos -> bool: Android hay TYPE_STEP_COUNTER; iOS CMPedometer.isStepCountingAvailable().
  static const isAvailable = 'isAvailable';

  /// Sin argumentos -> 'granted' | 'denied' | 'notDetermined', sin mostrar ningun dialogo.
  /// Android: concedido o Android 9 o anterior (no hay permiso) -> granted; negado y el nativo ya lo pidio alguna vez -> denied; nunca pedido -> notDetermined.
  /// Android sabe si ya lo pidio por una marca propia en SharedPreferences nativas que escribe requestPermission, no por stepsAskedAt (que es de Dart y no ve el nativo).
  /// iOS CMAuthorizationStatus: authorized -> granted, notDetermined -> notDetermined, denied y restricted -> denied.
  static const permissionStatus = 'permissionStatus';

  /// Sin argumentos -> los mismos tres textos, despues de que la persona responde; si ya estaba decidido responde sin dialogo.
  /// Si falla lanza PlatformException y Dart lo trata como no concedido sin activar nada.
  static const requestPermission = 'requestPermission';

  /// Solo Android, sin argumentos -> {counter, wallMs, elapsedMs, bootCount} (enteros; bootCount -1 si no se puede leer).
  /// Devuelve null si no llego un evento en 3 s o si falta el permiso (nunca lo pide).
  static const readCounter = 'readCounter';

  /// Solo iOS, argumento {days: 1..7} -> [{day, steps}], del mas viejo al de hoy, un item por dia local con dato.
  /// day es AAAA-MM-DD con calendario gregoriano y Locale en_US_POSIX, en el dia local del telefono.
  /// Un dia cuya consulta falla o no tiene datos se OMITE: nunca se manda steps 0 inventado.
  /// fromMinute no se manda en iOS: Core Motion da el dia completo; solo lo usa la regla de ancla de Android dentro de Dart.
  static const readDays = 'readDays';

  /// Del lado de iOS (U5) quedan el minimo de 5 minutos entre consultas y la lectura al pasar a segundo plano.
  static const iosThrottle = Duration(minutes: 5);

  static StepPermission parsePermission(Object? raw) => switch (raw) {
    'granted' => StepPermission.granted,
    'notDetermined' => StepPermission.notDetermined,
    _ => StepPermission.denied,
  };

  static List<StepDayReading> parseDays(Object? raw) {
    if (raw is! List) return const [];
    final out = <StepDayReading>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final day = item['day'];
      final steps = item['steps'];
      if (day is! String || !isPlausibleStepDay(day) || steps is! num || steps < 0) continue;
      final from = item['fromMinute'];
      out.add(StepDayReading(day, steps.toInt(), fromMinute: from is num ? from.toInt() : null));
    }
    return out;
  }
}

abstract class StepSource {
  Future<bool> isAvailable();

  Future<StepPermission> permission();

  Future<StepPermission> requestPermission();

  /// Los dias con dato, en el dia local del telefono; un dia sin lectura no figura.
  Future<List<StepDayReading>> readDays();

  /// Borra lo que la fuente guarda en este telefono; el historial de la app no.
  Future<void> forget();
}

class UnavailableStepSource implements StepSource {
  const UnavailableStepSource();

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<StepPermission> permission() async => StepPermission.denied;

  @override
  Future<StepPermission> requestPermission() async => StepPermission.denied;

  @override
  Future<List<StepDayReading>> readDays() async => const [];

  @override
  Future<void> forget() async {}
}

/// La fuente de la plataforma actual; hasta que existan Android e iOS es la no disponible.
StepSource createStepSource() => const UnavailableStepSource();

@visibleForTesting
class FakeStepSource implements StepSource {
  bool available = true;
  StepPermission permissionValue = StepPermission.granted;
  StepPermission requestResult = StepPermission.granted;
  List<StepDayReading> days = [];
  bool fail = false;
  Completer<void>? readGate;
  Completer<void>? requestGate;
  int reads = 0;
  int forgotten = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<StepPermission> permission() async => permissionValue;

  @override
  Future<StepPermission> requestPermission() async {
    await requestGate?.future;
    if (fail) throw StateError('fallo del pedido');
    return permissionValue = requestResult;
  }

  @override
  Future<List<StepDayReading>> readDays() async {
    reads++;
    await readGate?.future;
    if (fail) throw StateError('fallo de la fuente');
    return List.of(days);
  }

  @override
  Future<void> forget() async => forgotten++;
}
