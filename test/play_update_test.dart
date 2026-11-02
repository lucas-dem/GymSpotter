// Validador de versión en Android (sesión 28): Google Play In-App Updates a través del canal infyter/store_update
// (MainActivity → StoreUpdate.kt). "device" dice si hay internet de verdad y el versionCode instalado; "play" es la
// respuesta de la app Play Store. El canal está simulado acá; en el emulador se prueba el código nativo.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/services/play_update.dart';
import 'package:infyter/services/update_check.dart';

const _canal = MethodChannel('infyter/store_update');

// UpdateAvailability de Play Core: 1 = UPDATE_NOT_AVAILABLE, 2 = UPDATE_AVAILABLE.
Map<String, Object?> play({int availability = 2, int code = 5, bool allowed = true, int? stale = 3}) => {
  'availability': availability,
  'availableVersionCode': code,
  'immediateAllowed': allowed,
  'stalenessDays': stale,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> llamadas;

  // El teléfono: con o sin internet, con la 1.3.2 (versionCode 4) instalada.
  void telefono({bool online = true, int instalada = 4, FutureOr<Object?> Function()? respuestaPlay}) {
    messenger.setMockMethodCallHandler(_canal, (call) async {
      llamadas.add(call.method);
      return switch (call.method) {
        'device' => {'online': online, 'installedVersionCode': instalada},
        'play' => await (respuestaPlay ?? () => play())(),
        _ => throw MissingPluginException(),
      };
    });
  }

  setUp(() => llamadas = []);
  tearDown(() => messenger.setMockMethodCallHandler(_canal, null));

  Future<UpdateCheck> consultar({bool simulada = false, Future<String?> Function()? archivo}) =>
      PlayUpdateSource(
        timeout: const Duration(milliseconds: 300),
        simulated: simulada,
        readSimulated: archivo,
      ).check();

  group('respuesta de Google Play', () {
    test('Play ofrece una versión mayor desde hace 3 días: bloquea', () async {
      telefono();
      final r = await consultar();
      expect(r.mustUpdate, isTrue);
      expect(r.reason, UpdateReason.newer);
      expect(llamadas, ['device', 'play']);
    });

    test('Play responde "desconocido" (0) o "actualización en curso" (3): no bloquea', () async {
      for (final disponibilidad in [0, 3]) {
        telefono(respuestaPlay: () => play(availability: disponibilidad));
        final r = await consultar();
        expect(r.reason, UpdateReason.notAvailable, reason: 'availability $disponibilidad');
        expect(r.mustUpdate, isFalse);
      }
    });

    test('Play no ofrece actualización (instalada igual a la publicada): no bloquea', () async {
      telefono(respuestaPlay: () => play(availability: 1, code: 0, allowed: false, stale: null));
      expect((await consultar()).reason, UpdateReason.notAvailable);
    });

    test('Play dice "disponible" pero con el mismo versionCode: no bloquea', () async {
      telefono(respuestaPlay: () => play(code: 4));
      expect((await consultar()).reason, UpdateReason.equal);
    });

    test('gracia de 48 h: Play la conoce desde hace 1 día, o no sabe desde cuándo: no bloquea', () async {
      telefono(respuestaPlay: () => play(stale: 1));
      expect((await consultar()).reason, UpdateReason.grace);
      telefono(respuestaPlay: () => play(stale: null));
      expect((await consultar()).reason, UpdateReason.grace);
      telefono(respuestaPlay: () => play(stale: 2));
      expect((await consultar()).mustUpdate, isTrue);
    });

    test('Play no permite actualizar ahora: no bloquea', () async {
      telefono(respuestaPlay: () => play(allowed: false));
      expect((await consultar()).reason, UpdateReason.notAllowed);
    });

    test('sin internet no bloquea y ni le pregunta a Play', () async {
      telefono(online: false);
      final r = await consultar();
      expect(r.reason, UpdateReason.offline);
      expect(llamadas, ['device']);
    });

    test('error de Play (sin Play Store, app no instalada desde Play) no bloquea', () async {
      telefono(
        respuestaPlay: () => throw PlatformException(code: 'play-failed', message: 'Install Error(-9)'),
      );
      expect((await consultar()).reason, UpdateReason.playError);
    });

    test('Play que no contesta no bloquea', () async {
      telefono(respuestaPlay: () => Completer<Object?>().future);
      expect((await consultar()).reason, UpdateReason.timeout);
    });

    test('una build sin el canal nativo no bloquea', () async {
      expect((await consultar()).reason, UpdateReason.playError);
    });
  });

  group('tienda simulada (solo en una build de prueba)', () {
    test('versión publicada mayor que la instalada: bloquea sin preguntarle a Play', () async {
      telefono();
      final r = await consultar(
        simulada: true,
        archivo: () async => '{"versionCode": 5, "stalenessDays": 3}',
      );
      expect(r.mustUpdate, isTrue);
      expect(llamadas, ['device']);
    });

    test('versión publicada igual o menor que la instalada: no bloquea', () async {
      telefono();
      expect(
        (await consultar(
          simulada: true,
          archivo: () async => '{"versionCode": 4, "stalenessDays": 3}',
        )).mustUpdate,
        isFalse,
      );
      expect(
        (await consultar(
          simulada: true,
          archivo: () async => '{"versionCode": 3, "stalenessDays": 3}',
        )).mustUpdate,
        isFalse,
      );
    });

    test('sin internet, la tienda simulada tampoco bloquea', () async {
      telefono(online: false);
      final r = await consultar(
        simulada: true,
        archivo: () async => '{"versionCode": 5, "stalenessDays": 3}',
      );
      expect(r.reason, UpdateReason.offline);
    });

    test('la gracia también vale en la tienda simulada', () async {
      telefono();
      final r = await consultar(
        simulada: true,
        archivo: () async => '{"versionCode": 5, "stalenessDays": 1}',
      );
      expect(r.reason, UpdateReason.grace);
    });

    test('sin archivo de tienda simulada, pregunta a Play como siempre', () async {
      telefono(respuestaPlay: () => play(availability: 1, code: 0, allowed: false, stale: null));
      final r = await consultar(simulada: true, archivo: () async => null);
      expect(r.reason, UpdateReason.notAvailable);
      expect(llamadas, ['device', 'play']);
    });

    test('un archivo de tienda simulada roto no bloquea', () async {
      telefono();
      expect(
        (await consultar(simulada: true, archivo: () async => '{"versionCode": "cinco"}')).mustUpdate,
        isFalse,
      );
    });

    test('si la build no habilita la tienda simulada, el archivo se ignora', () async {
      telefono(respuestaPlay: () => play(availability: 1, code: 0, allowed: false, stale: null));
      var leido = false;
      final r = await consultar(
        archivo: () async {
          leido = true;
          return '{"versionCode": 5, "stalenessDays": 3}';
        },
      );
      expect(r.reason, UpdateReason.notAvailable);
      expect(leido, isFalse);
    });

    test('guardia: las builds normales no traen la tienda simulada', () {
      expect(kTiendaSimulada, isFalse);
    });
  });
}
