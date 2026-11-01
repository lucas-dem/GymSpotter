// El aviso de rescate en el inicio (sesión 26, decisión 2 de Braian): no bloquea la pantalla, ofrece Restaurar y
// Cerrar, y desaparece al usar cualquiera de los dos. Datos inventados; las copias van a un directorio temporal.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/app/infyter_app.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/services/progress_reminder.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:infyter/widgets/ui_kit.dart';
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

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('infyter_aviso');
    Store.rescueDirectory = '${tmp.path}/data_rescue';
    ProgressReminder.instance.enabled = false;
    setAppLanguage('es');
    fit.resetAllData();

    // Primera apertura: datos con un ítem ilegible, que dejan una copia útil. Segunda: datos ilegibles.
    final antes = await boot({
      kKey: jsonEncode({
        'onboarded': true,
        'language': 'es',
        'routines': [
          {
            'id': 'r1',
            'n': 'Empuje',
            'ex': ['EIeI8Vf'],
          },
          42,
        ],
      }),
    });
    fit.loadFromStore();
    fit.persistNow();
    await pumpEventQueue();
    // La app se cierra: la memoria vuelve a la de una instalación nueva y el disco queda como estaba.
    final disco = diskOf(antes);
    final copias = {
      for (final f in Directory('${tmp.path}/data_rescue').listSync())
        if (f is File) f.path: f.readAsStringSync(),
    };
    fit.resetAllData();
    Directory('${tmp.path}/data_rescue').createSync(recursive: true);
    copias.forEach((path, raw) => File(path).writeAsStringSync(raw));
    await boot({...disco, kKey: '{roto'});
    fit.loadFromStore();
    fit.onboarded = true; // la persona ya volvió a pasar la bienvenida
    fit.route = 'home';
  });

  tearDown(() {
    fit.saveAndExit();
    Store.instance.debugReset();
    Store.rescueDirectory = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> abrirInicio(WidgetTester tester) async {
    await tester.pumpWidget(const InfyterApp());
    await tester.pump(const Duration(milliseconds: 600));
  }

  // Deja pasar el aviso flotante de confirmación antes de terminar.
  Future<void> esperarAviso(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  testWidgets('el inicio muestra el aviso y Restaurar trae la copia', (tester) async {
    await abrirInicio(tester);
    expect(find.text(t.rescueTitle), findsOneWidget);

    await tester.tap(find.text(titleCase(t.rescueRestore)));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text(t.rescueTitle), findsNothing);
    expect(fit.routines.map((r) => r.name), ['Empuje']);
    await tester.pump(const Duration(milliseconds: 600)); // el aviso flotante tarda 650 ms en entrar
    expect(find.text(t.rescueRestored), findsOneWidget);
    await esperarAviso(tester);
  });

  testWidgets('Cerrar oculta el aviso sin restaurar', (tester) async {
    await abrirInicio(tester);
    expect(find.text(t.rescueTitle), findsOneWidget);

    await tester.tap(find.text(titleCase(t.close)));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text(t.rescueTitle), findsNothing);
    expect(fit.routines, isEmpty);
    expect(Store.instance.rescueCopies, isNotEmpty, reason: 'cerrar no borra copias');
  });
}
