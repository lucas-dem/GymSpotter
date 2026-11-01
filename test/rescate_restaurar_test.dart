// Restaurar la copia de rescate y "Borrar todos los datos" (sesión 26, decisiones 1 y 2 de Braian).
// - Si los datos guardados no se pudieron usar (ilegibles, no son un objeto o de una versión más nueva) y hay una
//   copia que esta versión puede cargar, se ofrece restaurarla. Antes de restaurar se guarda una copia del estado
//   actual. "Cerrar" deja de ofrecerla sin borrar nada.
// - "Borrar todos los datos" también borra las copias de rescate y el indicador.
// Cada `abrir` simula una apertura de la app. Datos inventados; las copias van a un directorio temporal.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/services/store_migrations.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kKey = 'gymmane_v1';

/// Un blob con una rutina y un ítem ilegible: al abrirlo queda una copia útil (itemsSkipped).
String _conRutina(String nombre) => jsonEncode({
  'profile': {'name': 'Persona Prueba'},
  'onboarded': true,
  'routines': [
    {
      'id': 'r1',
      'n': nombre,
      'ex': ['EIeI8Vf'],
    },
    42,
  ],
});

List<String> _rutinas(String raw) => [
  for (final r in (jsonDecode(raw) as Map)['routines'] as List)
    if (r is Map) r['n'] as String,
];

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

  // Cierra la app: la memoria vuelve a la de una instalación nueva y el disco (SharedPreferences y data_rescue/)
  // queda como estaba.
  Map<String, Object> cerrar(SharedPreferences prefs) {
    final disco = diskOf(prefs);
    final dir = Directory('${tmp.path}/data_rescue');
    final archivos = {
      if (dir.existsSync())
        for (final f in dir.listSync())
          if (f is File) f.path: f.readAsStringSync(),
    };
    fit.resetAllData();
    dir.createSync(recursive: true);
    archivos.forEach((path, raw) => File(path).writeAsStringSync(raw));
    return disco;
  }

  // Abre la app con [blob] sobre lo que dejó en disco la apertura [antes], y la carga como al arrancar.
  Future<SharedPreferences> abrir(String blob, {SharedPreferences? antes}) async {
    final prefs = await boot({if (antes != null) ...cerrar(antes), kKey: blob});
    fit.loadFromStore();
    return prefs;
  }

  // Primera apertura con datos sanos que dejan una copia útil; la app guarda; segunda apertura con datos ilegibles.
  Future<SharedPreferences> ilegiblesConCopiaUtil() async {
    final antes = await abrir(_conRutina('Empuje'));
    fit.persistNow();
    await pumpEventQueue();
    return abrir('{roto', antes: antes);
  }

  List<String?> copias() => [for (final id in Store.instance.rescueCopies) Store.instance.readRescueCopy(id)];

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('infyter_restaurar');
    Store.rescueDirectory = '${tmp.path}/data_rescue';
    fit.resetAllData();
  });

  tearDown(() async {
    fit.saveAndExit();
    Store.instance.debugReset();
    Store.rescueDirectory = null;
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('Borrar todos los datos', () {
    test('también borra las copias de rescate, su carpeta y el indicador', () async {
      await abrir('{roto');
      expect(Store.instance.rescueCopies, isNotEmpty);
      expect(Directory('${tmp.path}/data_rescue').existsSync(), isTrue);

      fit.resetAllData();

      expect(Store.instance.rescueCopies, isEmpty);
      expect(Store.instance.rescue, isNull);
      expect(Directory('${tmp.path}/data_rescue').existsSync(), isFalse);
    });

    test('también las copias que quedaron en SharedPreferences', () async {
      Store.rescueDirectory = null;
      final prefs = await abrir('{roto');
      expect(prefs.getKeys().where((k) => k.startsWith('${kKey}_rescue')), isNotEmpty);

      fit.resetAllData();

      expect(prefs.getKeys().where((k) => k.startsWith('${kKey}_rescue')), isEmpty);
    });
  });

  group('aviso para restaurar', () {
    test('tras datos ilegibles se ofrece la última copia que se puede cargar', () async {
      await ilegiblesConCopiaUtil();

      final oferta = fit.rescueOffer;
      expect(oferta, isNotNull);
      expect(Store.instance.readRescueCopy(oferta!), _conRutina('Empuje'));
    });

    test('si la única copia es la ilegible, no hay nada para ofrecer', () async {
      await abrir('{roto');

      expect(Store.instance.rescue!.reason, 'unreadable');
      expect(fit.rescueOffer, isNull);
    });

    test('si solo se saltearon ítems no se ofrece: los datos ya están en la app', () async {
      await abrir(_conRutina('Empuje'));

      expect(Store.instance.rescue!.reason, 'itemsSkipped');
      expect(fit.rescueOffer, isNull);
    });

    test('con datos de una versión más nueva no se ofrece: lo conocido ya se cargó', () async {
      final antes = await abrir(_conRutina('Empuje'));
      fit.persistNow();
      await pumpEventQueue();
      final nuevo = jsonEncode({
        kSchemaVersionKey: kStoreSchemaVersion + 1,
        'onboarded': true,
        'units': 'lb',
      });
      final prefs = await abrir(nuevo, antes: antes);

      expect(Store.instance.rescue!.reason, 'unsupportedVersion');
      expect(fit.units, 'lb', reason: 'se cargó lo conocido');
      expect(fit.rescueOffer, isNull, reason: 'restaurar una copia anterior pisaría lo que se cargó');

      // Tampoco después de actualizar a la versión que entiende ese formato.
      fit.persistNow();
      await pumpEventQueue();
      await boot(cerrar(prefs));
      Store.instance.debugSchema(kStoreSchemaVersion + 1, {kStoreSchemaVersion: (data) => data});
      fit.loadFromStore();
      expect(fit.rescueOffer, isNull);
    });

    test('en cuanto hay datos propios nuevos deja de ofrecerse: restaurar los reemplazaría', () async {
      final prefs = await ilegiblesConCopiaUtil();
      expect(fit.rescueOffer, isNotNull);

      fit.createRoutine('Nueva');
      expect(fit.rescueOffer, isNull);

      fit.persistNow();
      await pumpEventQueue();
      await boot(cerrar(prefs));
      fit.loadFromStore();
      expect(fit.routines.map((r) => r.name), ['Nueva']);
      expect(fit.rescueOffer, isNull, reason: 'tampoco en el próximo arranque');
    });

    test('importar un backup deja de ofrecer la copia', () async {
      await ilegiblesConCopiaUtil();
      expect(fit.rescueOffer, isNotNull);

      expect(fit.importJson(jsonEncode({'onboarded': true, 'units': 'lb'})), isTrue);

      expect(fit.rescueOffer, isNull);
    });

    test('una vez cerrado, no se ofrece otra copia aunque la cerrada ya no esté', () async {
      final uno = await abrir(_conRutina('Uno'));
      fit.persistNow();
      await pumpEventQueue();
      final dos = await abrir(_conRutina('Dos'), antes: uno);
      fit.persistNow();
      await pumpEventQueue();
      final prefs = await abrir('{roto', antes: dos);
      final cerrada = fit.rescueOffer!;
      expect(_rutinas(Store.instance.readRescueCopy(cerrada)!), ['Dos']);

      fit.dismissRescue();
      File('${tmp.path}/data_rescue/$cerrada.json').deleteSync();
      fit.persistNow();
      await pumpEventQueue();
      await boot(cerrar(prefs));
      fit.loadFromStore();

      expect(fit.rescueOffer, isNull);
    });

    test('restaurar guarda primero lo que hay como otra copia y después carga la copia', () async {
      final prefs = await ilegiblesConCopiaUtil();
      fit.updateProfile(name: 'Nueva');

      expect(fit.restoreRescue(), isTrue);

      expect(fit.routines.map((r) => r.name), ['Empuje']);
      expect(fit.profile.name, 'Persona Prueba');
      expect(fit.rescueOffer, isNull, reason: 'ya se restauró');
      expect(
        ((jsonDecode(copias().last!) as Map)['profile'] as Map)['name'],
        'Nueva',
        reason: 'el estado de antes de restaurar quedó en una copia',
      );
      await pumpEventQueue();
      expect(_rutinas(prefs.getString(kKey)!), ['Empuje'], reason: 'lo restaurado queda guardado');
    });

    test('si la copia ya no se puede leer, restaurar no cambia nada', () async {
      await ilegiblesConCopiaUtil();
      fit.updateProfile(name: 'Nueva');
      expect(fit.rescueOffer, isNotNull);
      for (final f in Directory('${tmp.path}/data_rescue').listSync()) {
        if (f is File) f.writeAsStringSync('{dañada');
      }

      expect(fit.restoreRescue(), isFalse);

      expect(fit.profile.name, 'Nueva');
      expect(fit.routines, isEmpty);
    });

    test('Cerrar deja de ofrecerla, también en el próximo arranque, y no borra copias', () async {
      final prefs = await ilegiblesConCopiaUtil();
      final guardadas = copias();
      expect(fit.rescueOffer, isNotNull);

      fit.dismissRescue();

      expect(fit.rescueOffer, isNull);
      expect(copias(), guardadas);
      fit.persistNow();
      await pumpEventQueue();
      await boot(cerrar(prefs));
      fit.loadFromStore();
      expect(fit.rescueOffer, isNull);
    });

    test('con un entrenamiento abierto no se ofrece', () async {
      await ilegiblesConCopiaUtil();
      expect(fit.rescueOffer, isNotNull);

      fit.sessionPicks
        ..clear()
        ..add('EIeI8Vf');
      fit.startSession();

      expect(fit.session, isNotNull);
      expect(fit.rescueOffer, isNull);
    });
  });
}
