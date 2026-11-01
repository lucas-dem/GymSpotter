// Rotación de las copias de rescate (sesión 26, decisión 4 de Braian): como mucho 3 copias. Cuando sobra una, se
// descarta primero la más vieja de las que no se pueden recuperar, y nunca la última copia útil (la más reciente que
// es un objeto JSON) ni la que se acaba de escribir. Cada `boot` simula una apertura de la app. Datos inventados;
// las copias van a un directorio temporal.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/services/store_migrations.dart';
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

  // Abre la app una vez por blob, como varios arranques seguidos con datos que no se pueden usar tal cual.
  Future<SharedPreferences> arrancar(List<String> blobs, {Map<String, Object> disk = const {}}) async {
    var actual = Map<String, Object>.of(disk);
    late SharedPreferences prefs;
    for (final blob in blobs) {
      prefs = await boot({...actual, kKey: blob});
      Store.instance.load();
      actual = diskOf(prefs);
    }
    return prefs;
  }

  List<String?> copias() => [for (final id in Store.instance.rescueCopies) Store.instance.readRescueCopy(id)];

  // Un blob de una versión futura: esta app no lo usa tal cual, pero es un objeto JSON, o sea una copia útil.
  String futuro(String marca) => jsonEncode({kSchemaVersionKey: kStoreSchemaVersion + 1, 'marca': marca});

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('infyter_rotacion');
    Store.rescueDirectory = '${tmp.path}/data_rescue';
  });

  tearDown(() async {
    Store.instance.debugReset();
    Store.rescueDirectory = null;
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('como mucho 3 copias: quedan las 3 más recientes', () async {
    await arrancar(['{a', '{b', '{c', '{d', '{e']);

    expect(copias(), ['{c', '{d', '{e']);
    expect(Store.instance.rescue!.count, 5);
    expect(Store.instance.readRescueCopy(Store.instance.rescue!.slot), '{e');
  });

  test('la última copia útil no se descarta aunque después lleguen copias ilegibles', () async {
    final util = futuro('u');
    await arrancar([util, '{a', '{b', '{c', '{d']);

    expect(copias(), [util, '{c', '{d']);
  });

  test('se descartan primero las ilegibles, aunque sean más nuevas que una útil', () async {
    final u1 = futuro('1');
    final u2 = futuro('2');
    await arrancar([u1, '{a', '{b', u2]);

    expect(copias(), [u1, '{b', u2]);
  });

  test('si todas son útiles, se va la más vieja', () async {
    final utiles = [
      for (final m in ['1', '2', '3', '4']) futuro(m),
    ];
    await arrancar(utiles);

    expect(copias(), utiles.sublist(1));
  });

  test('el mismo crudo en otro arranque no ocupa otra copia', () async {
    await arrancar(['{x', '{x']);

    expect(copias(), ['{x']);
    expect(Store.instance.rescue!.count, 2);
  });

  test('la copia previa a una migración entra en la misma rotación', () async {
    final old = jsonEncode({'units': 'lb'});
    final prefs = await arrancar(['{a', '{b', '{c']);
    await boot({...diskOf(prefs), kKey: old});
    Store.instance.debugSchema(2, {
      1: (data) => {...data, 'v2': true},
    });

    expect(Store.instance.load()['v2'], isTrue);
    expect(copias(), ['{b', '{c', old]);
    expect(
      Store.instance.readRescueCopy(Store.instance.rescue!.slot),
      '{c',
      reason: 'migrar no es un incidente',
    );
  });

  test('sin directorio, las copias en SharedPreferences también rotan', () async {
    Store.rescueDirectory = null;
    final prefs = await arrancar(['{a', '{b', '{c', '{d']);

    expect(copias(), ['{b', '{c', '{d']);
    expect(prefs.getKeys().where((k) => k.startsWith('${kKey}_rescue_')), hasLength(3));
    expect(Store.instance.rescue!.where, 'prefs');
  });

  test('un archivo ajeno con un número enorme de nombre no es una copia y no rompe el arranque', () async {
    Directory('${tmp.path}/data_rescue').createSync(recursive: true);
    final ajeno = File('${tmp.path}/data_rescue/123456789012345678901234567890.json')
      ..writeAsStringSync('{ajeno');

    await arrancar(['{a']);

    expect(copias(), ['{a']);
    expect(ajeno.readAsStringSync(), '{ajeno', reason: 'no se toca');
  });

  test('una copia con el nombre anterior (first.json) se sigue leyendo y cuenta como la más vieja', () async {
    Directory('${tmp.path}/data_rescue').createSync(recursive: true);
    File('${tmp.path}/data_rescue/first.json').writeAsStringSync('{viejo');

    final prefs = await arrancar(['{a', '{b']);
    expect(copias(), ['{viejo', '{a', '{b']);

    await arrancar(['{c'], disk: diskOf(prefs));
    expect(copias(), ['{a', '{b', '{c']);
  });
}
