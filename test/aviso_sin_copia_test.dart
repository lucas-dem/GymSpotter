// Primer daño sin ninguna copia útil anterior (sesión 27, decisión 2a de Braian). El JSON ilegible queda copiado en
// data_rescue/ antes de cualquier guardado, y el inicio avisa que se guardó, sin "Restaurar" porque no hay nada que
// restaurar. "Cerrar" lo oculta también en los próximos arranques; importar un backup o "Borrar todos los datos"
// también lo quitan. Cada `abrir` simula una apertura de la app. Datos inventados; las copias van a un directorio
// temporal.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/app/infyter_app.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/services/progress_reminder.dart';
import 'package:infyter/services/store_migrations.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:infyter/widgets/ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kKey = 'gymmane_v1';
const kRoto = '{"profile":{"name":"Ana"},"sessions":[{"d":"2026-10-20T18:30:00.000"';

/// Un blob con una rutina y un ítem ilegible: al abrirlo queda una copia útil (itemsSkipped).
String _conRutina(String nombre) => jsonEncode({
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

  // La persona pasa la bienvenida y la app guarda (lo primero que se escribe después de un arranque vacío).
  Future<void> bienvenidaYGuardar() async {
    fit.onboarded = true;
    fit.persistNow();
    await pumpEventQueue();
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('infyter_sin_copia');
    Store.rescueDirectory = '${tmp.path}/data_rescue';
    ProgressReminder.instance.enabled = false;
    fit.resetAllData();
  });

  tearDown(() async {
    fit.saveAndExit();
    Store.instance.debugReset();
    Store.rescueDirectory = null;
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('primer daño sin copia útil', () {
    test(
      'el JSON ilegible queda en data_rescue/ antes de cualquier guardado y sobrevive al primero',
      () async {
        final prefs = await abrir(kRoto);

        final incidente = Store.instance.rescue!;
        expect(incidente.reason, 'unreadable');
        expect(incidente.where, 'file');
        expect(File('${tmp.path}/data_rescue/${incidente.slot}.json').readAsStringSync(), kRoto);
        expect(prefs.getString(kKey), kRoto, reason: 'abrir todavía no escribió nada');

        await bienvenidaYGuardar();

        expect(prefs.getString(kKey), isNot(kRoto));
        expect(
          Store.instance.readRescueCopy(incidente.slot),
          kRoto,
          reason: 'la copia sobrevive al primer guardado',
        );
      },
    );

    test('se avisa que se guardó una copia, sin ofrecer restaurar', () async {
      await abrir(kRoto);

      expect(fit.rescueOffer, isNull, reason: 'no hay ninguna copia útil para restaurar');
      expect(fit.rescueSaved, Store.instance.rescue!.slot);
    });

    test('también si el JSON es válido pero no es un objeto', () async {
      await abrir('[1,2,3]');

      expect(Store.instance.rescue!.reason, 'notAMap');
      expect(fit.rescueOffer, isNull);
      expect(fit.rescueSaved, isNotNull);
    });

    test('el aviso sigue aunque la persona ya cargue datos nuevos: no hay nada que pisar', () async {
      await abrir(kRoto);

      fit.createRoutine('Nueva');

      expect(fit.rescueSaved, isNotNull);
    });

    test('Cerrar lo oculta, también en el próximo arranque, y no borra la copia', () async {
      final prefs = await abrir(kRoto);
      final copia = Store.instance.rescue!.slot;

      fit.dismissRescue();

      expect(fit.rescueSaved, isNull);
      await bienvenidaYGuardar();
      await boot(cerrar(prefs));
      fit.loadFromStore();
      expect(fit.rescueSaved, isNull, reason: 'ya lo cerró');
      expect(Store.instance.readRescueCopy(copia), kRoto, reason: 'cerrar no borra la copia');
    });

    test('importar un backup quita el aviso, también en el próximo arranque', () async {
      final prefs = await abrir(kRoto);
      expect(fit.rescueSaved, isNotNull);

      expect(fit.importJson(jsonEncode({'onboarded': true, 'units': 'lb'})), isTrue);

      expect(fit.rescueSaved, isNull);
      fit.persistNow();
      await pumpEventQueue();
      await boot(cerrar(prefs));
      fit.loadFromStore();
      expect(fit.rescueSaved, isNull);
    });

    test('la copia que promete el aviso no se descarta al rotar las copias', () async {
      await abrir(kRoto);
      final copia = Store.instance.rescue!.slot;

      for (var i = 0; i < Store.maxRescueCopies + 1; i++) {
        Store.instance.keepCopy({'units': 'kg', 'rest': 60 + i});
      }

      expect(Store.instance.readRescueCopy(copia), kRoto);
      expect(Store.instance.rescueSaved, copia);
    });

    test('"Borrar todos los datos" lo quita junto con las copias', () async {
      await abrir(kRoto);
      expect(fit.rescueSaved, isNotNull);

      fit.resetAllData();

      expect(fit.rescueSaved, isNull);
      expect(Store.instance.rescueCopies, isEmpty);
    });
  });

  group('cuándo no aparece', () {
    test('con datos sanos', () async {
      await abrir(jsonEncode({'onboarded': true, 'units': 'lb'}));

      expect(fit.rescueSaved, isNull);
    });

    test('si solo se saltearon ítems: los datos ya están en la app', () async {
      await abrir(_conRutina('Empuje'));

      expect(Store.instance.rescue!.reason, 'itemsSkipped');
      expect(fit.rescueSaved, isNull);
    });

    test('con datos de una versión más nueva: lo conocido ya se cargó', () async {
      await abrir(jsonEncode({kSchemaVersionKey: kStoreSchemaVersion + 1, 'onboarded': true}));

      expect(Store.instance.rescue!.reason, 'unsupportedVersion');
      expect(fit.rescueSaved, isNull);
    });

    test('si hay una copia útil anterior: se ofrece restaurarla, no este aviso', () async {
      final antes = await abrir(_conRutina('Empuje'));
      fit.persistNow();
      await pumpEventQueue();
      await abrir(kRoto, antes: antes);

      expect(fit.rescueOffer, isNotNull);
      expect(fit.rescueSaved, isNull);
    });
  });

  group('en el inicio', () {
    Future<void> abrirInicio(WidgetTester tester) async {
      setAppLanguage('es');
      await abrir(kRoto);
      fit.onboarded = true; // la persona ya pasó la bienvenida
      fit.route = 'home';
      await tester.pumpWidget(const InfyterApp());
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('avisa que se guardó una copia, con Cerrar y sin Restaurar', (tester) async {
      await abrirInicio(tester);

      expect(find.text(t.rescueSavedTitle), findsOneWidget);
      expect(find.text(t.rescueSavedBody), findsOneWidget);
      expect(find.text(titleCase(t.rescueRestore)), findsNothing);
      expect(find.text(t.rescueTitle), findsNothing);
    });

    testWidgets('Cerrar oculta el aviso', (tester) async {
      await abrirInicio(tester);

      await tester.tap(find.text(titleCase(t.close)));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text(t.rescueSavedTitle), findsNothing);
      expect(Store.instance.rescueCopies, isNotEmpty, reason: 'cerrar no borra la copia');
    });
  });
}
