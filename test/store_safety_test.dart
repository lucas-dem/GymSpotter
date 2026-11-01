// Auditoría de persistencia (sesión 17): huecos que no cubrían
// store_rescue_test.dart ni formato_131_test.dart.
//
// - Un backup con un tipo inesperado no puede quedar aplicado a medias ni
//   dejar la app sin guardar (applyBackup dejaba `_loading` en true).
// - Una migración que falla después de tocar datos anidados no puede dejar
//   datos migrados a medias: se carga el crudo sin migrar.
// - Casos de versión, cadenas de migración, incidentes encadenados, guardados
//   superpuestos y un guardado diferido agendado antes de la carga.
//
// Datos inventados. Las copias de rescate van a un directorio temporal.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/services/store_migrations.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kKey = 'gymmane_v1';

/// Blob sano con perfil, una rutina y una sesión del historial.
String sano() => jsonEncode({
  'profile': {'name': 'Persona Prueba'},
  'units': 'kg',
  'onboarded': true,
  'favorites': {'EIeI8Vf': true},
  'exRest': {'EIeI8Vf': 150},
  'routines': [
    {
      'id': 'r1',
      'n': 'Empuje',
      'ex': ['EIeI8Vf'],
    },
  ],
  'sessions': [
    {
      'd': '2026-10-20T18:30:00.000',
      'dur': 1800,
      'ex': [
        {
          'id': 'EIeI8Vf',
          'n': 'Barbell Bench Press',
          'p': 'chest',
          's': [
            {'r': 8, 'w': 60.0},
          ],
        },
      ],
    },
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  Future<SharedPreferences> boot(Map<String, Object> disk) async {
    SharedPreferences.setMockInitialValues(disk);
    Store.instance.debugReset();
    await Store.instance.init();
    return SharedPreferences.getInstance();
  }

  Map<String, Object> diskOf(SharedPreferences prefs) => {for (final k in prefs.getKeys()) k: prefs.get(k)!};

  Map<String, dynamic> stored(SharedPreferences prefs) =>
      jsonDecode(prefs.getString(kKey)!) as Map<String, dynamic>;

  List<String?> copias() => [for (final id in Store.instance.rescueCopies) Store.instance.readRescueCopy(id)];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('infyter_s17');
    Store.rescueDirectory = '${tmp.path}/data_rescue';
  });

  tearDown(() async {
    fit.saveAndExit();
    Store.instance.debugReset();
    Store.rescueDirectory = null;
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('backup con un tipo inesperado', () {
    // `weeklyPlan` con un día que no es número: int.parse falla DESPUÉS de que
    // applyBackup ya reemplazó el perfil y las rutinas.
    final roto = jsonEncode({
      'profile': {'name': 'Otra'},
      'routines': [],
      'weeklyPlan': {'lunes': 'r9'},
    });

    test('importJson lo rechaza (false) y deja todo como estaba', () async {
      await boot({kKey: sano()});
      fit.loadFromStore();

      late bool ok;
      expect(() => ok = fit.importJson(roto), returnsNormally);
      expect(ok, isFalse);
      expect(fit.profile.name, 'Persona Prueba');
      expect(fit.routines.single.name, 'Empuje');
      expect(fit.sessions, hasLength(1));
      expect(fit.favorites, {'EIeI8Vf': true}, reason: 'toJson() comparte este mapa y applyBackup lo vacía');
      expect(fit.exerciseRest, {'EIeI8Vf': 150});
    });

    test(
      'applyBackup (camino del ZIP) relanza, vuelve al estado anterior y la app sigue guardando',
      () async {
        final prefs = await boot({kKey: sano()});
        fit.loadFromStore();

        expect(() => fit.applyBackup(jsonDecode(roto) as Map<String, dynamic>), throwsA(anything));
        expect(fit.profile.name, 'Persona Prueba', reason: 'no queda aplicado a medias');
        expect(fit.routines.single.name, 'Empuje');

        fit.setUnits('lb');
        fit.persistNow();
        await pumpEventQueue();
        final saved = stored(prefs);
        expect(saved['units'], 'lb', reason: 'con `_loading` trabado en true no se guardaba nada más');
        expect(((saved['routines'] as List).single as Map)['n'], 'Empuje');
        expect(saved['sessions'] as List, hasLength(1));
        expect(saved['favorites'], {'EIeI8Vf': true});
      },
    );
  });

  group('migraciones', () {
    test('si un paso falla después de tocar datos anidados, se carga el crudo sin migrar', () async {
      final old = jsonEncode({
        'units': 'lb',
        'sessions': [
          {'d': '2026-10-01T10:00:00.000'},
          {'d': '2026-10-02T10:00:00.000'},
        ],
      });
      await boot({kKey: old});
      Store.instance.debugSchema(2, {
        1: (data) {
          (data['sessions'] as List).removeLast();
          throw StateError('bug de migración');
        },
      });

      final data = Store.instance.load();
      expect(Store.instance.rescue!.reason, 'migrationFailed');
      expect(
        data,
        jsonDecode(old),
        reason: 'el paso recibe una copia superficial: la lista anidada era la misma',
      );
    });

    test('si falta un paso de la cadena, se registra migrationFailed y se carga sin migrar', () async {
      final old = jsonEncode({'units': 'lb'});
      await boot({kKey: old});
      Store.instance.debugSchema(3, {
        1: (data) => {...data, 'v2': true},
      });

      expect(Store.instance.load(), {'units': 'lb'});
      expect(Store.instance.rescue!.reason, 'migrationFailed');
      expect(copias(), [old], reason: 'la copia previa a migrar y la del incidente son la misma: una sola');
    });

    test('versión que no es un entero o es menor que 1: copia cruda y se carga lo conocido', () async {
      for (final tag in <Object>['2', 0, 1.5]) {
        final raw = jsonEncode({kSchemaVersionKey: tag, 'units': 'lb'});
        await boot({kKey: raw});

        expect(Store.instance.load(), {'units': 'lb'}, reason: 'versión $tag');
        final rescue = Store.instance.rescue!;
        expect(rescue.reason, 'unsupportedVersion', reason: 'versión $tag');
        expect(Store.instance.readRescueCopy(rescue.slot), raw, reason: 'versión $tag');
      }
    });

    test(
      'caracterización: tras una migración fallida, el siguiente guardado estampa la versión actual',
      () async {
        final old = jsonEncode({'units': 'lb', 'rest': 90});
        final prefs = await boot({kKey: old});
        Store.instance.debugSchema(2, {1: (_) => throw StateError('bug de migración')});

        fit.loadFromStore();
        fit.persistNow();
        await pumpEventQueue();
        expect(
          stored(prefs)[kSchemaVersionKey],
          2,
          reason: 'una versión posterior con la migración corregida no la vuelve a correr',
        );
        expect(copias(), [old], reason: 'el original queda en las copias');
        expect(Store.instance.readRescueCopy(Store.instance.rescue!.slot), old);
      },
    );
  });

  group('incidentes y escrituras', () {
    test('corrupción -> la persona guarda datos nuevos -> otra corrupción: quedan las dos copias', () async {
      var prefs = await boot({kKey: '{"viejo":'});
      fit.loadFromStore();
      fit.persistNow();
      await pumpEventQueue();
      expect(prefs.getString(kKey), isNot('{"viejo":'), reason: 'la clave principal ya se pisó');

      prefs = await boot({...diskOf(prefs), kKey: '{"nuevo":'});
      fit.loadFromStore();
      expect(copias(), ['{"viejo":', '{"nuevo":']);
      expect(Store.instance.rescue!.count, 2);
    });

    test(
      'una sesión rara se saltea: el resto del historial y lo que se carga después quedan, y el original se copia',
      () async {
        fit.resetAllData();
        final raw = jsonEncode({
          'profile': {'name': 'Persona Prueba'},
          'routines': [
            {'id': 'r1', 'n': 'Empuje', 'ex': []},
          ],
          'sessions': [
            {'d': 12345, 'dur': 60, 'ex': []},
            {'d': '2026-10-20T18:30:00.000', 'dur': 1800, 'ex': []},
          ],
          'bodyweight': [
            {'d': '2026-10-01T08:00:00.000', 'kg': 80.0},
          ],
        });
        final prefs = await boot({kKey: raw});

        fit.loadFromStore();
        final rescue = Store.instance.rescue!;
        expect(rescue.reason, 'itemsSkipped');
        expect(
          Store.instance.readRescueCopy(rescue.slot),
          raw,
          reason: 'copiado antes de cualquier guardado',
        );
        fit.persistNow();
        await pumpEventQueue();
        final saved = stored(prefs);
        expect(((saved['routines'] as List).single as Map)['n'], 'Empuje');
        expect(
          [for (final s in saved['sessions'] as List) (s as Map)['d']],
          ['2026-10-20T18:30:00.000'],
          reason: 'solo se saltea la sesión rara',
        );
        expect(
          saved['bodyweight'] as List,
          hasLength(1),
          reason: 'lo que se carga después de las sesiones queda',
        );
        expect(
          Store.instance.readRescueCopy(rescue.slot),
          raw,
          reason: 'el original completo sigue en la copia',
        );
      },
    );

    test('un guardado diferido agendado antes de la carga escribe recién después de la copia', () async {
      final prefs = await boot({kKey: '{"roto":'});
      fit.setUnits('lb');
      fit.loadFromStore();
      final slot = Store.instance.rescue!.slot;
      expect(File('${tmp.path}/data_rescue/$slot.json').readAsStringSync(), '{"roto":');

      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(
        prefs.getString(kKey),
        isNot('{"roto":'),
        reason: 'el guardado diferido pisó la clave principal',
      );
      expect(Store.instance.readRescueCopy(slot), '{"roto":', reason: 'pero la copia ya estaba en disco');
    });

    test('dos guardados superpuestos: queda el último, sin mezclar', () async {
      final prefs = await boot({});
      final a = Store.instance.save({'units': 'kg', 'rest': 60});
      final b = Store.instance.save({'units': 'lb'});
      await Future.wait([a, b]);

      expect(stored(prefs), {'units': 'lb', kSchemaVersionKey: kStoreSchemaVersion});
    });
  });
}
