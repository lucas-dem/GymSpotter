import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'step_source_android.dart';
import 'step_source_ios.dart';

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

  /// Sin argumentos -> bool: Android true si hay TYPE_STEP_COUNTER o FEATURE_SENSOR_STEP_COUNTER (sin permiso el sensor puede no figurar) y false en el reloj (FEATURE_WATCH); iOS CMPedometer.isStepCountingAvailable().
  static const isAvailable = 'isAvailable';

  /// Sin argumentos -> 'granted' | 'denied' | 'notDetermined', sin mostrar ningun dialogo.
  /// Android: concedido o Android 9 o anterior (no hay permiso) -> granted; nunca pedido, o negado una vez y el sistema todavia muestra el dialogo (shouldShowRequestPermissionRationale) -> notDetermined; negado y el sistema ya no lo muestra -> denied.
  /// Android sabe si ya lo negaron por una marca propia en SharedPreferences nativas que escribe el resultado del pedido ante una negativa real o dos seguidas sin explicacion del sistema (un toque afuera del dialogo se tolera una vez) y que se borra al estar concedido, no por stepsAskedAt (que es de Dart y no ve el nativo).
  /// iOS CMAuthorizationStatus: authorized -> granted, notDetermined -> notDetermined, denied y restricted -> denied.
  static const permissionStatus = 'permissionStatus';

  /// Sin argumentos -> los mismos tres textos, despues de que la persona responde; si ya estaba decidido responde sin dialogo.
  /// Si falla lanza PlatformException y Dart lo trata como no concedido sin activar nada.
  /// iOS no tiene un pedido propio: una consulta de hoy muestra el dialogo y se espera la respuesta hasta 60 s; si no llega, responde notDetermined.
  static const requestPermission = 'requestPermission';

  /// Solo Android, sin argumentos -> {counter, wallMs, elapsedMs, bootCount} (enteros; bootCount -1 si no se puede leer).
  /// Devuelve null si no llego un evento en 3 s o si falta el permiso (nunca lo pide).
  static const readCounter = 'readCounter';

  /// Solo iOS, argumentos {days: 1..7, fromMs: int opcional} -> [{day, steps}], del mas viejo al de hoy, un item por dia local con dato.
  /// Cada dia va de su medianoche a la siguiente (hoy, hasta ahora); con fromMs no se cuenta nada anterior y los dias previos no se mandan.
  /// Dart manda fromMs despues de apagar el conteo o de borrar los datos (clave infyter_steps_ios_start_v1, fuera de gymmane_v1 y del ZIP): la primera lectura con permiso fija ahora.
  /// day es AAAA-MM-DD con calendario gregoriano y Locale en_US_POSIX, en el dia local del telefono.
  /// Un dia cuya consulta falla, no tiene datos o da 0 pasos se OMITE: Core Motion no distingue 0 de "sin dato", asi que queda hueco.
  /// fromMinute no lo manda el Swift: Core Motion da el dia completo; Dart lo pone solo en el dia de fromMs (y Android en su regla de ancla).
  static const readDays = 'readDays';

  /// Solo Android, sin argumentos -> String o null: el ancla de step_anchor.dart en JSON, guardada en las preferencias nativas infyter_steps (fuera de la copia y de la transferencia a otro telefono).
  static const loadAnchor = 'loadAnchor';

  /// Solo Android, argumento {anchor: String} -> null: guarda el ancla en JSON.
  static const saveAnchor = 'saveAnchor';

  /// Solo Android, sin argumentos -> null: borra solo el ancla; la marca de que el permiso ya se pidio queda.
  static const clearAnchor = 'clearAnchor';

  /// Solo Android, sin argumentos -> null: borra el ancla, la marca nativa permission_asked y el contador silent_denials.
  static const forget = 'forget';

  /// iOS: minimo entre dos consultas de los 7 dias; entre medio, y si no cambio el dia, se consulta solo hoy.
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

  /// Borra lo que la fuente guarda en este telefono; el historial de la app no. Al volver a contar no se recupera nada anterior (en iOS, ni los 7 dias de Core Motion).
  Future<void> forget();

  /// Para "Contar pasos" apagado: deja de escuchar y borra solo el ancla (en iOS marca un arranque nuevo), asi lo caminado mientras tanto no se suma; lo del permiso queda.
  Future<void> stopCounting();

  /// Avisa que hay pasos nuevos para leer, como mucho cada 60 s y solo con la app en primer plano.
  Stream<void> get updates;
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

  @override
  Future<void> stopCounting() async {}

  @override
  Stream<void> get updates => const Stream.empty();
}

/// La fuente de la plataforma actual: el sensor en Android (el reloj responde que no esta disponible), Core Motion en iOS y, en las demas, la no disponible.
StepSource createStepSource() {
  if (kIsWeb) return const UnavailableStepSource();
  if (Platform.isAndroid) return AndroidStepSource();
  if (Platform.isIOS) return IosStepSource();
  return const UnavailableStepSource();
}

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
  int stopped = 0;
  final StreamController<void> updatesController = StreamController<void>.broadcast();

  @override
  Stream<void> get updates => updatesController.stream;

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

  @override
  Future<void> stopCounting() async => stopped++;
}
