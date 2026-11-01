// Carga tolerante por ítem (sesión 26, decisión 3 de Braian): al abrir la app, un ítem que no se puede leer se
// saltea, el resto se carga y el JSON original queda en una copia de rescate antes del siguiente guardado. Importar
// un backup sigue siendo todo o nada. Datos inventados; las copias van a un directorio temporal.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kKey = 'gymmane_v1';

Map<String, dynamic> _sesion(String d) => {
  'd': d,
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
};

/// Blob sano, con lo mínimo de cada parte.
Map<String, dynamic> _sano() => {
  'profile': {'name': 'Persona Prueba'},
  'units': 'lb',
  'onboarded': true,
  'favorites': <String, dynamic>{'EIeI8Vf': true},
  'exRest': <String, dynamic>{'EIeI8Vf': 150},
  'weeklyPlan': <String, dynamic>{'1': 'r1'},
  'checkins': <dynamic>['2026-10-20'],
  'routines': <dynamic>[
    {
      'id': 'r1',
      'n': 'Empuje',
      'ex': ['EIeI8Vf'],
    },
  ],
  'sessions': <dynamic>[_sesion('2026-10-20T18:30:00.000'), _sesion('2026-10-22T18:30:00.000')],
  'bodyweight': <dynamic>[
    {'d': '2026-10-01T08:00:00.000', 'kg': 80.0},
  ],
};

/// El mismo blob con un ítem ilegible en cada lista y en cada mapa, y un entrenamiento en curso ilegible.
Map<String, dynamic> _conItemsRaros() {
  final m = _sano();
  (m['favorites'] as Map)['zG0zs85'] = 'sí';
  (m['exRest'] as Map)['zG0zs85'] = 'mucho';
  (m['weeklyPlan'] as Map)['lunes'] = 'r1';
  (m['checkins'] as List).add(7);
  (m['routines'] as List).add(42);
  (m['sessions'] as List).insert(1, {'d': 12345, 'dur': 60, 'ex': []});
  (m['bodyweight'] as List).add('x');
  for (final k in ['notes', 'places', 'custom', 'athletes', 'measures', 'shots', 'moments']) {
    m[k] = [42];
  }
  m['awards'] = {'raro': 9};
  m['live'] = 42;
  return m;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  Future<SharedPreferences> boot(Map<String, Object> disk) async {
    SharedPreferences.setMockInitialValues(disk);
    Store.instance.debugReset();
    await Store.instance.init();
    return SharedPreferences.getInstance();
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('infyter_tolerante');
    Store.rescueDirectory = '${tmp.path}/data_rescue';
    fit.resetAllData();
  });

  tearDown(() async {
    fit.saveAndExit();
    Store.instance.debugReset();
    Store.rescueDirectory = null;
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('un ítem ilegible se saltea y todo lo demás se carga', () async {
    await boot({kKey: jsonEncode(_conItemsRaros())});
    fit.loadFromStore();

    expect(fit.units, 'lb');
    expect(fit.onboarded, isTrue);
    expect(fit.profile.name, 'Persona Prueba');
    expect(fit.favorites, {'EIeI8Vf': true});
    expect(fit.exerciseRest, {'EIeI8Vf': 150});
    expect(fit.weeklyPlan, {1: 'r1'});
    expect(fit.checkins, ['2026-10-20']);
    expect(fit.routines.map((r) => r.name), ['Empuje']);
    expect(fit.sessions.map((s) => s.date), [DateTime(2026, 10, 20, 18, 30), DateTime(2026, 10, 22, 18, 30)]);
    expect(fit.bodyweight.single.kg, 80);
    expect([
      fit.notes,
      fit.places,
      fit.customExercises,
      fit.athletes,
      fit.measures,
      fit.shots,
      fit.moments,
    ], everyElement(isEmpty));
    expect(fit.session, isNull, reason: 'el entrenamiento en curso ilegible no se retoma');
  });

  test('el original queda en una copia antes del primer guardado, y la copia sobrevive', () async {
    final crudo = jsonEncode(_conItemsRaros());
    final prefs = await boot({kKey: crudo});
    fit.loadFromStore();

    final rescue = Store.instance.rescue!;
    expect(rescue.reason, 'itemsSkipped');
    expect(Store.instance.readRescueCopy(rescue.slot), crudo);
    expect(prefs.getString(kKey), crudo, reason: 'cargar no escribe');

    fit.persistNow();
    await pumpEventQueue();
    final guardado = jsonDecode(prefs.getString(kKey)!) as Map<String, dynamic>;
    expect(guardado['sessions'] as List, hasLength(2));
    expect(guardado['routines'] as List, hasLength(1));
    expect(
      Store.instance.readRescueCopy(rescue.slot),
      crudo,
      reason: 'el original completo sigue en la copia',
    );
  });

  test('un ajuste o el perfil con otro tipo vuelven al valor de siempre y no frenan la carga', () async {
    final m = _sano()
      ..['units'] = 5
      ..['rest'] = 'mucho'
      ..['showFocus'] = 'no'
      ..['profile'] = [1];
    await boot({kKey: jsonEncode(m)});
    fit.loadFromStore();

    expect(fit.units, 'kg');
    expect(fit.restSeconds, 90);
    expect(fit.showFocus, isTrue);
    expect(fit.onboarded, isTrue);
    expect(fit.sessions, hasLength(2));
    expect(Store.instance.rescue!.reason, 'itemsSkipped');
  });

  test('un blob sano no deja copia ni incidente', () async {
    final prefs = await boot({kKey: jsonEncode(_sano())});
    fit.loadFromStore();

    expect(fit.sessions, hasLength(2));
    expect(Store.instance.rescue, isNull);
    expect(Store.instance.rescueCopies, isEmpty);
    expect(prefs.getKeys(), {kKey});
  });

  group('importar un backup sigue siendo todo o nada', () {
    test('con ítems ilegibles se rechaza y no cambia nada', () async {
      await boot({kKey: jsonEncode(_sano())});
      fit.loadFromStore();

      final otro = _conItemsRaros()..['profile'] = {'name': 'Otra'};
      expect(fit.importJson(jsonEncode(otro)), isFalse);
      expect(fit.profile.name, 'Persona Prueba');
      expect(fit.sessions, hasLength(2));
      expect(Store.instance.rescue, isNull, reason: 'un backup rechazado no es un incidente del almacén');
    });

    test('también si lo único raro es un ítem de una parte con cargador compartido (notas)', () async {
      await boot({kKey: jsonEncode(_sano())});
      fit.loadFromStore();

      final otro = _sano()
        ..['profile'] = {'name': 'Otra'}
        ..['notes'] = [42];
      expect(fit.importJson(jsonEncode(otro)), isFalse);
      expect(fit.profile.name, 'Persona Prueba');
    });
  });
}
