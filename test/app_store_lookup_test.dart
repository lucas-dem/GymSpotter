// Validador de versión en iPhone (sesión 28): el lookup público de Apple, con respuestas grabadas.
// - test/app_store_lookup_responses/ar-2026-11-01.json: la respuesta real de
//   https://itunes.apple.com/lookup?bundleId=com.infyter.app&country=ar del 2026-11-01 (Infyter 1.3.1, publicada el
//   2026-10-27), con artistName, sellerName, artistId y artistViewUrl tachados para no copiar al repo los datos del
//   vendedor. El validador no los usa.
// - test/app_store_lookup_responses/us-2026-11-01.json: la respuesta real con country=us (la app no está en esa
//   tienda: 0 resultados).
// Los casos "mayor" y "gracia" cambian la versión y la fecha de la respuesta real. Las consultas van a un servidor
// HTTP local; este archivo no inicializa el binding de Flutter, porque haría que toda consulta devuelva 400.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/services/app_store_lookup.dart';
import 'package:infyter/services/update_check.dart';
import 'package:infyter/state/update_gate.dart';

final _ar = File('test/app_store_lookup_responses/ar-2026-11-01.json').readAsStringSync();
final _us = File('test/app_store_lookup_responses/us-2026-11-01.json').readAsStringSync();

// Un iPhone con iOS 17.5.1, como lo cuenta Platform.operatingSystemVersion.
const _ios17 = 'Version 17.5.1 (Build 21F90)';
final _ahora = DateTime.utc(2026, 11, 1, 20);

// La respuesta real de AR con otra versión y otra fecha de publicación.
String conVersion(String version, {DateTime? publicada, String? minimoIos}) {
  final data = jsonDecode(_ar) as Map<String, dynamic>;
  final app = (data['results'] as List).single as Map<String, dynamic>;
  app['version'] = version;
  if (publicada != null) app['currentVersionReleaseDate'] = publicada.toUtc().toIso8601String();
  if (minimoIos != null) app['minimumOsVersion'] = minimoIos;
  return jsonEncode(data);
}

UpdateCheck evaluar(String body, {String instalada = '1.3.1', String ios = _ios17}) =>
    evaluateLookup(body, installed: instalada, osVersion: ios, now: _ahora);

// Servidor local que responde según el país pedido y anota las consultas.
class _Tienda {
  _Tienda._(this._server);
  final HttpServer _server;
  final pedidos = <Uri>[];
  final respuestas = <String, String>{};
  int status = 200;
  bool colgada = false;

  static Future<_Tienda> abrir() async {
    final t = _Tienda._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    t._server.listen((req) async {
      t.pedidos.add(req.uri);
      if (t.colgada) return; // Nunca contesta.
      req.response.statusCode = t.status;
      req.response.headers.contentType = ContentType('text', 'javascript', charset: 'utf-8');
      req.response.write(t.respuestas[req.uri.queryParameters['country']] ?? _us);
      await req.response.close();
    });
    return t;
  }

  String get base => 'http://${_server.address.address}:${_server.port}';

  Future<void> cerrar() => _server.close(force: true);
}

void main() {
  group('respuestas grabadas (evaluateLookup)', () {
    test('versión mayor en la tienda bloquea', () {
      final r = evaluar(conVersion('1.3.2', publicada: _ahora.subtract(const Duration(hours: 72))));
      expect(r.mustUpdate, isTrue);
      expect(r.reason, UpdateReason.newer);
      expect(r.storeVersion, '1.3.2');
    });

    test('versión igual no bloquea (la respuesta real: 1.3.1 con 1.3.1 instalada)', () {
      final r = evaluar(_ar);
      expect(r.mustUpdate, isFalse);
      expect(r.reason, UpdateReason.equal);
      expect(r.storeVersion, '1.3.1');
    });

    test('instalada mayor que la de la tienda no bloquea (TestFlight 1.3.2 con 1.3.1 publicada)', () {
      final r = evaluar(_ar, instalada: '1.3.2');
      expect(r.mustUpdate, isFalse);
      expect(r.reason, UpdateReason.older);
    });

    test('sin resultados no bloquea (la respuesta real de la tienda de US)', () {
      final r = evaluar(_us);
      expect(r.mustUpdate, isFalse);
      expect(r.reason, UpdateReason.noResults);
    });

    test('JSON roto no bloquea', () {
      expect(evaluar(_ar.substring(0, 120)).reason, UpdateReason.badJson);
      expect(evaluar('').reason, UpdateReason.badJson);
      expect(evaluar('<html>Service Unavailable</html>').reason, UpdateReason.badJson);
      expect(evaluar('{"resultCount": 1, "results": "x"}').reason, UpdateReason.badJson);
      expect(evaluar(conVersion('uno.tres')).reason, UpdateReason.badJson);
    });

    test('la respuesta de otra app no bloquea', () {
      final otra = conVersion(
        '9.0.0',
        publicada: DateTime.utc(2026),
      ).replaceFirst('"bundleId":"com.infyter.app"', '"bundleId":"com.otra.app"');
      expect(evaluar(otra).reason, UpdateReason.otherApp);
    });

    test('gracia de 48 h: una versión publicada hace 47 h no bloquea; hace 49 h, sí', () {
      final hace47 = evaluar(conVersion('1.3.2', publicada: _ahora.subtract(const Duration(hours: 47))));
      expect(hace47.mustUpdate, isFalse);
      expect(hace47.reason, UpdateReason.grace);
      final hace49 = evaluar(conVersion('1.3.2', publicada: _ahora.subtract(const Duration(hours: 49))));
      expect(hace49.mustUpdate, isTrue);
    });

    test('sin fecha de publicación no se puede contar la gracia: no bloquea', () {
      final data = jsonDecode(conVersion('1.3.2')) as Map<String, dynamic>;
      ((data['results'] as List).single as Map<String, dynamic>).remove('currentVersionReleaseDate');
      expect(evaluar(jsonEncode(data)).reason, UpdateReason.grace);
    });

    test('mínimo de iOS mayor que el del teléfono no bloquea: no podría actualizar', () {
      final pideIos18 = conVersion('1.3.2', publicada: DateTime.utc(2026, 10, 1), minimoIos: '18.0');
      expect(evaluar(pideIos18).reason, UpdateReason.minOs);
      expect(evaluar(pideIos18, ios: 'Version 18.1 (Build 22B83)').mustUpdate, isTrue);
      expect(evaluar(pideIos18, ios: 'iOS desconocido').reason, UpdateReason.minOs);
    });

    test('una versión instalada ilegible no bloquea', () {
      expect(evaluar(_ar, instalada: '1.3.0+1').reason, UpdateReason.noVersion);
      expect(evaluar(_ar, instalada: '').reason, UpdateReason.noVersion);
    });
  });

  group('regionOf', () {
    test('toma la región de 2 letras del idioma del teléfono', () {
      expect(regionOf('es_AR'), 'ar');
      expect(regionOf('en-US'), 'us');
      expect(regionOf('es_AR.UTF-8'), 'ar');
      expect(regionOf('zh_Hant_TW'), 'tw');
      expect(regionOf('es'), isNull);
      expect(regionOf('es_419'), isNull);
      expect(regionOf(''), isNull);
    });

    test('si el teléfono trae la región aparte ("@rg="), usa esa', () {
      expect(regionOf('en_US@rg=arzzzz'), 'ar');
      expect(regionOf('es@rg=arzzzz'), 'ar');
    });
  });

  group('iPhone: compara la versión real del binario (updateSourceFor)', () {
    late _Tienda tienda;

    setUp(() async => tienda = await _Tienda.abrir());
    tearDown(() => tienda.cerrar());

    UpdateSource fuente(Future<String?> Function() binario) => updateSourceFor(
      os: 'ios',
      storeBuild: true,
      installedVersion: binario,
      lookup: AppStoreLookup(base: tienda.base),
      country: () => 'ar',
      osVersion: () => _ios17,
      now: () => _ahora,
    )!;

    test(
      'un binario 1.3.0 frente a la 1.3.1 publicada bloquea (la versión sale del binario, no del define)',
      () async {
        tienda.respuestas['ar'] = _ar;
        final r = await fuente(() async => '1.3.0')();
        expect(r.reason, UpdateReason.newer);
        expect(r.storeVersion, '1.3.1');
      },
    );

    test('un binario igual a la versión publicada no bloquea', () async {
      tienda.respuestas['ar'] = _ar;
      expect((await fuente(() async => '1.3.1')()).reason, UpdateReason.equal);
    });

    test('si no se puede leer la versión del binario, no consulta ni bloquea', () async {
      tienda.respuestas['ar'] = _ar;
      expect((await fuente(() async => null)()).reason, UpdateReason.noVersion);
      expect((await fuente(() async => throw StateError('sin canal'))()).reason, UpdateReason.noVersion);
      expect(tienda.pedidos, isEmpty);
    });
  });

  group('consulta de verdad a un servidor local (AppStoreLookup.check)', () {
    late _Tienda tienda;

    setUp(() async => tienda = await _Tienda.abrir());
    tearDown(() => tienda.cerrar());

    Future<UpdateCheck> consultar(String? pais, {Duration timeout = const Duration(seconds: 5)}) =>
        AppStoreLookup(
          base: tienda.base,
          timeout: timeout,
        ).check(installed: '1.3.1', country: pais, osVersion: _ios17, now: _ahora);

    test('pide el bundle de Infyter en el país de la región y bloquea si hay una versión mayor', () async {
      tienda.respuestas['ar'] = conVersion('1.3.2', publicada: DateTime.utc(2026, 10, 28));

      final r = await consultar('ar');

      expect(r.mustUpdate, isTrue);
      expect(tienda.pedidos.single.path, '/lookup');
      expect(tienda.pedidos.single.queryParameters, {'bundleId': 'com.infyter.app', 'country': 'ar'});
    });

    test('región sin app no bloquea y consulta ese país', () async {
      tienda.respuestas['ar'] = conVersion('1.3.2', publicada: DateTime.utc(2026, 10, 28));
      tienda.respuestas['es'] = _us; // En España la app no está publicada: 0 resultados.

      final r = await consultar('es');

      expect(r.mustUpdate, isFalse);
      expect(r.reason, UpdateReason.noResults);
      expect(tienda.pedidos.single.queryParameters['country'], 'es');
    });

    test('sin región no consulta ni bloquea', () async {
      final r = await consultar(null);
      expect(r.reason, UpdateReason.noRegion);
      expect(tienda.pedidos, isEmpty);
    });

    test('timeout no bloquea', () async {
      tienda.colgada = true;
      final reloj = Stopwatch()..start();

      final r = await consultar('ar', timeout: const Duration(milliseconds: 300));

      expect(r.reason, UpdateReason.timeout);
      expect(r.mustUpdate, isFalse);
      expect(reloj.elapsed, lessThan(const Duration(seconds: 3)));
    });

    test('HTTP 503 no bloquea', () async {
      tienda.status = 503;
      tienda.respuestas['ar'] = conVersion('1.3.2', publicada: DateTime.utc(2026, 10, 28));
      expect((await consultar('ar')).reason, UpdateReason.http);
    });

    test('sin conexión (nadie escucha en el puerto) no bloquea', () async {
      final base = tienda.base;
      await tienda.cerrar();
      final r = await AppStoreLookup(
        base: base,
        timeout: const Duration(seconds: 2),
      ).check(installed: '1.3.1', country: 'ar', osVersion: _ios17, now: _ahora);
      expect(r.reason, anyOf(UpdateReason.network, UpdateReason.timeout));
      expect(r.mustUpdate, isFalse);
    });
  });
}
