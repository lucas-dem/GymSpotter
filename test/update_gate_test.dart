// Validador de versión (sesión 28): cuándo se consulta la tienda y cuándo se tapa la app con "Actualiza Infyter".
// La fuente (Play en Android, el lookup de Apple en iPhone) es falsa acá; sus respuestas tienen sus propios tests.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/models/live_session.dart';
import 'package:infyter/services/update_check.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:infyter/state/update_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    fit.session = null;
    fit.resetRoute('home');
  });

  group('UpdateGate', () {
    test('bloquea cuando la tienda tiene una versión más nueva', () async {
      final gate = UpdateGate(
        source: () async => const UpdateCheck(UpdateReason.newer, storeVersion: '1.3.3'),
      );

      await gate.checkNow();

      expect(gate.mustUpdate, isTrue);
      expect(gate.storeVersion, '1.3.3');
      expect(gate.blocks(fit), isTrue);
    });

    test('no bloquea si está al día o si no se pudo saber', () async {
      for (final reason in [
        UpdateReason.equal,
        UpdateReason.older,
        UpdateReason.timeout,
        UpdateReason.offline,
      ]) {
        final gate = UpdateGate(source: () async => UpdateCheck(reason));
        await gate.checkNow();
        expect(gate.blocks(fit), isFalse, reason: reason.name);
      }
    });

    test('no bloquea durante un entrenamiento (abierto o en pausa) y bloquea al terminarlo', () async {
      final gate = UpdateGate(source: () async => const UpdateCheck(UpdateReason.newer));
      await gate.checkNow();

      fit.session = WorkoutSession();
      expect(gate.blocks(fit), isFalse);
      fit.session = WorkoutSession()..complete = true; // El resumen, todavía sin guardar.
      expect(gate.blocks(fit), isFalse);

      fit.session = null;
      expect(gate.blocks(fit), isTrue);
    });

    test('una consulta fallida después de un bloqueo lo levanta: manda la última respuesta', () async {
      var respuesta = const UpdateCheck(UpdateReason.newer);
      final gate = UpdateGate(source: () async => respuesta);
      await gate.checkNow();
      expect(gate.mustUpdate, isTrue);

      respuesta = const UpdateCheck(UpdateReason.offline);
      await gate.checkNow();

      expect(gate.mustUpdate, isFalse);
    });

    test('no tapa una nota ni un plan a medio escribir: espera a que se cierre el editor', () async {
      final gate = UpdateGate(source: () async => const UpdateCheck(UpdateReason.newer));
      await gate.checkNow();

      for (final editor in ['note-edit', 'ai-plan']) {
        fit.resetRoute('home');
        fit.pushRoute(editor);
        expect(gate.blocks(fit), isFalse, reason: editor);
      }
      fit.resetRoute('home');
      expect(gate.blocks(fit), isTrue);
    });

    test('si la fuente falla con una excepción, no bloquea', () async {
      final gate = UpdateGate(source: () async => throw StateError('roto'));
      await gate.checkNow();
      expect(gate.mustUpdate, isFalse);
      expect(gate.last?.verdict, UpdateVerdict.unknown);
    });

    test('avisa a la pantalla cuando llega la respuesta', () async {
      final gate = UpdateGate(source: () async => const UpdateCheck(UpdateReason.newer));
      var avisos = 0;
      gate.addListener(() => avisos++);
      await gate.checkNow();
      expect(avisos, 1);
    });

    test('una consulta a la vez', () async {
      final respuesta = Completer<UpdateCheck>();
      var consultas = 0;
      final gate = UpdateGate(
        source: () {
          consultas++;
          return respuesta.future;
        },
      );

      final primera = gate.checkNow();
      final segunda = gate.checkNow();
      respuesta.complete(const UpdateCheck(UpdateReason.equal));
      await Future.wait([primera, segunda]);

      expect(consultas, 1);
    });

    test('al volver a la app consulta de nuevo solo si pasó al menos 1 hora', () async {
      var ahora = DateTime(2026, 11, 2, 10);
      var consultas = 0;
      final gate = UpdateGate(
        source: () async {
          consultas++;
          return const UpdateCheck(UpdateReason.equal);
        },
        clock: () => ahora,
      );

      await gate.checkNow();
      ahora = ahora.add(const Duration(minutes: 59));
      await gate.resumed();
      expect(consultas, 1);

      ahora = ahora.add(const Duration(minutes: 1));
      await gate.resumed();
      expect(consultas, 2);
    });

    test('sin fuente nunca consulta ni bloquea', () async {
      final gate = UpdateGate();
      await gate.checkNow();
      await gate.resumed();
      expect(gate.last, isNull);
      expect(gate.blocks(fit), isFalse);
    });
  });

  group('qué fuente usa cada sistema', () {
    test('Android pregunta a Google Play, aunque la build no traiga los defines de versión', () {
      expect(updateSourceFor(os: 'android', storeBuild: false), isNotNull);
    });

    test('iPhone usa el lookup de Apple en las builds de tienda (las que traen los defines de versión)', () {
      expect(updateSourceFor(os: 'ios', storeBuild: true), isNotNull);
    });

    test('en una build de desarrollo (sin defines de versión), el iPhone no consulta ni bloquea', () {
      expect(updateSourceFor(os: 'ios', storeBuild: false), isNull);
    });

    test('en otros sistemas (tests, escritorio) no hay validador', () {
      expect(updateSourceFor(os: 'windows', storeBuild: true), isNull);
      expect(updateSourceFor(os: 'linux', storeBuild: false), isNull);
    });
  });

  group('versión del binario en iPhone (canal infyter/app_version)', () {
    const canal = MethodChannel('infyter/app_version');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(canal, null));

    test('devuelve la versión que trae el binario (CFBundleShortVersionString)', () async {
      messenger.setMockMethodCallHandler(
        canal,
        (call) async => call.method == 'versionName' ? '1.3.2' : null,
      );
      expect(await bundleVersionName(), '1.3.2');
    });

    test('si el canal falla o no existe, devuelve null y no se consulta', () async {
      messenger.setMockMethodCallHandler(canal, (call) async => throw PlatformException(code: 'falla'));
      expect(await bundleVersionName(), isNull);
      messenger.setMockMethodCallHandler(canal, null);
      expect(await bundleVersionName(), isNull);
    });
  });
}
