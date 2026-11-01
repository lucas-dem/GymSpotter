// Protección contra pérdida silenciosa del blob `gymmane_v1` (sesión 16).
//
// Cada test simula un arranque con `boot`: lo que haya "en disco" pasa a
// SharedPreferences y el Store se vuelve a inicializar. Las copias de rescate
// van a un directorio temporal; nunca se tocan datos reales.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/services/store_migrations.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kKey = 'gymmane_v1';

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

  List<String> filesIn(Directory dir) {
    if (!dir.existsSync()) return [];
    return [for (final f in dir.listSync()) f.uri.pathSegments.last]..sort();
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('infyter_rescue');
    Store.rescueDirectory = '${tmp.path}/data_rescue';
  });

  tearDown(() async {
    Store.instance.debugReset();
    Store.rescueDirectory = null;
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Directory rescueDir() => Directory('${tmp.path}/data_rescue');

  test('un blob sano de 1.3.x (sin versión) se lee igual y no deja copias ni claves nuevas', () async {
    final raw = jsonEncode({'units': 'lb', 'rest': 120, 'routines': [], 'sessions': []});
    final prefs = await boot({kKey: raw});

    expect(Store.instance.load(), jsonDecode(raw));
    expect(prefs.getKeys(), {kKey});
    expect(Store.instance.rescue, isNull);
    expect(rescueDir().existsSync(), isFalse, reason: 'con datos sanos no se crea nada en disco');
  });

  test('guardar escribe la versión de formato y cargar la quita', () async {
    final prefs = await boot({});
    await Store.instance.save({'units': 'kg'});

    expect(jsonDecode(prefs.getString(kKey)!), {'units': 'kg', kSchemaVersionKey: kStoreSchemaVersion});
    expect(Store.instance.load(), {'units': 'kg'});
    expect(kStoreSchemaVersion, 1, reason: 'el formato 1.3.x es la versión 1');
  });

  test('JSON ilegible: el crudo queda en cuarentena antes de que un guardado lo pise', () async {
    const corrupt = '{"profile":{"name":"Ana"},"sessions":[{"d":"2026-10-20T18:30:00.000"';
    final prefs = await boot({kKey: corrupt});

    expect(Store.instance.load(), isEmpty);
    final rescue = Store.instance.rescue!;
    expect(rescue.reason, 'unreadable');
    expect(rescue.slot, 'first');
    expect(rescue.count, 1);
    expect(File('${rescueDir().path}/first.json').readAsStringSync(), corrupt);
    expect(prefs.getString(kKey), corrupt, reason: 'cargar no reescribe el original');

    await Store.instance.save({'units': 'kg'});
    expect(prefs.getString(kKey), isNot(corrupt));
    expect(Store.instance.readRescueCopy('first'), corrupt, reason: 'la copia sobrevive al guardado');
  });

  test('JSON válido que no es un objeto: también va a cuarentena', () async {
    await boot({kKey: '[1,2,3]'});

    expect(Store.instance.load(), isEmpty);
    expect(Store.instance.rescue!.reason, 'notAMap');
    expect(Store.instance.readRescueCopy('first'), '[1,2,3]');
  });

  test('blob de una versión más nueva: carga lo conocido y conserva el crudo con lo desconocido', () async {
    final newer = jsonEncode({
      kSchemaVersionKey: kStoreSchemaVersion + 1,
      'units': 'lb',
      'futuro': {'x': 1},
    });
    await boot({kKey: newer});

    final data = Store.instance.load();
    expect(data['units'], 'lb');
    expect(data.containsKey(kSchemaVersionKey), isFalse);
    final rescue = Store.instance.rescue!;
    expect(rescue.reason, 'unsupportedVersion');
    expect(rescue.version, kStoreSchemaVersion + 1);
    expect(Store.instance.readRescueCopy(rescue.slot), newer);
  });

  test(
    'migración falsa: respaldo del crudo antes de migrar, no destructiva, y se guarda con la versión nueva',
    () async {
      final old = jsonEncode({'units': 'lb', 'rest': 90});
      final prefs = await boot({kKey: old});
      final backupSeenByMigration = <String?>[];
      Store.instance.debugSchema(2, {
        1: (data) {
          backupSeenByMigration.add(Store.instance.readRescueCopy('premigration'));
          return {...data, 'restV2': data['rest']};
        },
      });

      final data = Store.instance.load();
      expect(backupSeenByMigration, [old], reason: 'el respaldo existe antes de que corra la migración');
      expect(data['restV2'], 90);
      expect(data['rest'], 90);
      expect(prefs.getString(kKey), old, reason: 'migrar en memoria no reescribe el original');
      expect(Store.instance.rescue, isNull, reason: 'migrar no es un incidente');

      await Store.instance.save(data);
      expect(jsonDecode(prefs.getString(kKey)!)[kSchemaVersionKey], 2);
      expect(Store.instance.readRescueCopy('premigration'), old);
      expect(filesIn(rescueDir()), ['premigration.json']);
    },
  );

  test('una migración que falla conserva el crudo y la carga sigue con lo que hay', () async {
    final old = jsonEncode({'units': 'lb'});
    await boot({kKey: old});
    Store.instance.debugSchema(2, {1: (_) => throw StateError('bug de migración')});

    expect(Store.instance.load()['units'], 'lb');
    final rescue = Store.instance.rescue!;
    expect(rescue.reason, 'migrationFailed');
    expect(Store.instance.readRescueCopy(rescue.slot), old);
  });

  test('copias acotadas: la primera se conserva y después solo se reemplaza la última', () async {
    var disk = <String, Object>{};
    for (final junk in ['{a', '{b', '{c']) {
      final prefs = await boot({...disk, kKey: junk});
      Store.instance.load();
      disk = diskOf(prefs);
    }

    expect(Store.instance.readRescueCopy('first'), '{a');
    expect(Store.instance.readRescueCopy('last'), '{c');
    expect(filesIn(rescueDir()), ['first.json', 'last.json']);
    expect(Store.instance.rescue!.count, 3);
    expect(Store.instance.rescue!.slot, 'last');
  });

  test('sin directorio disponible, la copia queda en SharedPreferences', () async {
    Store.rescueDirectory = null;
    final prefs = await boot({kKey: '{oops'});

    Store.instance.load();
    expect(prefs.getString('${kKey}_rescue_first'), '{oops');
    expect(Store.instance.readRescueCopy('first'), '{oops');
    expect(Store.instance.rescue!.where, 'prefs');
  });

  test('la misma carga repetida no duplica la copia', () async {
    await boot({kKey: '{x'});
    Store.instance.load();
    Store.instance.load();
    Store.instance.preserveStored('loadFailed');

    expect(Store.instance.rescue!.count, 1);
    expect(filesIn(rescueDir()), ['first.json']);
  });

  test('guardia: cada versión anterior a la actual tiene su migración', () {
    for (var v = 1; v < kStoreSchemaVersion; v++) {
      expect(kStoreMigrations.containsKey(v), isTrue, reason: 'falta la migración $v -> ${v + 1}');
    }
  });

  group('FitState', () {
    test('un tipo inesperado ya no impide abrir y el crudo queda a salvo antes de guardar', () async {
      fit.resetAllData();
      final raw = jsonEncode({
        'units': 5,
        'onboarded': true,
        'routines': [
          {'id': 'r1', 'n': 'Empuje', 'ex': []},
        ],
      });
      final prefs = await boot({kKey: raw});

      expect(() => fit.loadFromStore(), returnsNormally);
      expect(prefs.getString(kKey), raw, reason: 'cargar no escribe');
      final rescue = Store.instance.rescue!;
      expect(rescue.reason, 'loadFailed');
      expect(Store.instance.readRescueCopy(rescue.slot), raw);

      fit.persistNow();
      await pumpEventQueue();
      expect(prefs.getString(kKey), isNot(raw), reason: 'la app quedó usable: vuelve a guardar');
      expect(Store.instance.readRescueCopy(rescue.slot), raw);
    });

    test('actualización simulada: blob viejo -> código nuevo -> guardar -> reiniciar -> recargar', () async {
      fit.resetAllData();
      fit.createRoutine('Empuje');
      fit.addBodyweight(80);
      fit.persistNow();
      final old = jsonDecode(jsonEncode(fit.toJson())) as Map<String, dynamic>;
      expect(
        old.containsKey(kSchemaVersionKey),
        isFalse,
        reason: 'toJson no lleva versión: el backup no cambia',
      );

      var prefs = await boot({kKey: jsonEncode(old)});
      fit.loadFromStore();
      fit.persistNow();
      await pumpEventQueue();
      final saved = jsonDecode(prefs.getString(kKey)!) as Map<String, dynamic>;
      expect(saved[kSchemaVersionKey], kStoreSchemaVersion);
      expect(saved.keys.toSet(), {...old.keys, kSchemaVersionKey}, reason: 'mismas claves más la versión');
      expect(saved['routines'], old['routines']);
      expect(saved['bodyweight'], old['bodyweight']);

      fit.resetAllData();
      prefs = await boot({kKey: jsonEncode(saved)});
      fit.loadFromStore();
      expect(fit.routines.single.name, 'Empuje');
      expect(fit.latestBodyweight!.kg, 80);
      expect(Store.instance.rescue, isNull);
      expect(prefs.getKeys(), {kKey});
    });
  });
}
