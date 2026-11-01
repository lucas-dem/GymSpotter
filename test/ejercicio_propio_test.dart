// Un ejercicio propio que se llama igual que uno del catálogo se muestra con "(propio)" (sesión 28, decisión e3 de
// Braian). Caso real: el "Bíceps en polea" que la persona creó en 1.3.1, cuando el catálogo pasó a llamar así al
// curl en polea (G08RZcQ). No se unen ni se tocan sus datos: el sufijo es solo de pantalla. La búsqueda, las
// exportaciones, la plantilla para la IA y lo que se comparte (texto de rutinas, sticker) usan el nombre guardado.
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/catalog/exercise_catalog.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/models/exercise.dart';
import 'package:infyter/models/workout.dart';
import 'package:infyter/screens/sticker_screen.dart';
import 'package:infyter/services/backup_zip.dart';
import 'package:infyter/services/exercise_match.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/services/media_store.dart';
import 'package:infyter/services/progress_reminder.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:infyter/theme/app_theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _biceps = 'G08RZcQ';

// Mismo formato de id que addCustomExercise ("c<microsegundos>-<n>").
Exercise propio(String nombre, {String id = 'c1760000000000002-2'}) => Exercise(
  id: id,
  name: nombre,
  primary: 'biceps',
  secondary: const [],
  equipment: 'Cable',
  difficulty: 'Beginner',
  art: '',
  steps: const [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => setAppLanguage('en'));
  final byId = {for (final e in kExercises) e.id: e};

  group('cómo se ve', () {
    test('el "Bíceps en polea" propio se muestra como "Bíceps en polea (propio)" en español', () {
      setAppLanguage('es');
      final mio = propio('Bíceps en polea');

      expect(exerciseName(mio), 'Bíceps en polea (propio)');
      // El historial y la sesión usan catalogName directamente.
      expect(t.catalogName(mio.id, mio.name), 'Bíceps en polea (propio)');
    });

    test('mayúsculas, tildes y espacios de más no evitan el sufijo', () {
      setAppLanguage('es');
      expect(exerciseName(propio('biceps  en POLEA')), 'biceps  en POLEA (propio)');
    });

    test('un ejercicio propio con nombre único no lleva sufijo', () {
      setAppLanguage('es');
      expect(exerciseName(propio('Bici fija del club')), 'Bici fija del club');
    });

    test('el ejercicio del catálogo se sigue llamando "Bíceps en polea"', () {
      setAppLanguage('es');
      expect(exerciseName(byId[_biceps]!), 'Bíceps en polea');
    });

    test('un id provisorio de importación ("imp:") no lleva sufijo: no es un ejercicio propio', () {
      setAppLanguage('es');
      expect(t.catalogName('imp:biceps-en-polea', 'Bíceps en polea'), 'Bíceps en polea');
    });

    test(
      'en los 16 idiomas, el propio que repite el nombre del catálogo lleva un sufijo y conserva su nombre',
      () {
        expect(appLanguages, hasLength(16));
        for (final code in appLanguages) {
          setAppLanguage(code);
          final delCatalogo = exerciseName(byId[_biceps]!);
          final visto = exerciseName(propio(delCatalogo));
          expect(visto, isNot(delCatalogo), reason: code);
          expect(visto, contains(delCatalogo), reason: code);
        }
      },
    );

    test('guardia: en los 16 idiomas, ningún ejercicio del catálogo lleva sufijo', () {
      for (final code in appLanguages) {
        setAppLanguage(code);
        for (final e in kExercises) {
          expect(exerciseName(e), t.catalogNameRaw(e.id, e.name), reason: '$code ${e.id}');
        }
      }
    });

    test(
      'un propio que repite un nombre del gimnasio (que se ve en todos los idiomas) lleva sufijo en inglés',
      () {
        setAppLanguage('en');
        expect(exerciseName(propio('Press plano')), 'Press plano (custom)');
      },
    );

    test('en inglés el propio "Cable Curl" se distingue del curl del catálogo', () {
      setAppLanguage('en');
      expect(exerciseName(propio('Cable Curl')), 'Cable Curl (custom)');
      expect(exerciseName(byId[_biceps]!), 'Cable Curl');
    });
  });

  group('sus datos no cambian', () {
    late Directory tmp;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Store.instance.init();
      tmp = await Directory.systemTemp.createTemp('infyter_propio');
      MediaStore.directory = tmp.path;
      ProgressReminder.instance.enabled = false;
      fit.resetAllData();
      setAppLanguage('es');
    });

    tearDown(() async {
      MediaStore.directory = null;
      fit.resetAllData();
      if (tmp.existsSync()) await tmp.delete(recursive: true);
    });

    String crearPropio() =>
        fit.addCustomExercise(name: 'Bíceps en polea', primary: 'biceps', equipment: 'Cable');

    test('guardia: mostrarlo no cambia el nombre guardado ni el JSON', () {
      final id = crearPropio();
      final mio = fit.customExercises.single;

      expect(exerciseName(mio), 'Bíceps en polea (propio)');
      expect(mio.id, id);
      expect(mio.name, 'Bíceps en polea');
      expect(mio.toJson()['n'], 'Bíceps en polea');
      expect((fit.toJson()['custom'] as List).single['n'], 'Bíceps en polea');
    });

    test('guardia: buscar "Bíceps en polea" sigue encontrando el propio y el del catálogo', () {
      final id = crearPropio();
      final encontrados = fit.allExercises.where(exerciseSearch('Bíceps en polea')).map((e) => e.id);
      expect(encontrados, containsAll([id, _biceps]));
    });

    test('la búsqueda usa el nombre guardado: escribir "propio" no lo encuentra', () {
      final id = crearPropio();
      expect(fit.allExercises.where(exerciseSearch('propio')).map((e) => e.id), isNot(contains(id)));
    });

    testWidgets('el sticker para compartir un entreno usa el nombre guardado, sin "(propio)"', (
      tester,
    ) async {
      final id = crearPropio();
      final entreno = LoggedSession(DateTime(2026, 11, 1, 18), 1800, [
        LoggedExercise(id, 'Bíceps en polea', 'biceps', [LoggedSet(12, 20)]),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: StickerEditor(session: entreno),
        ),
      );
      await tester.pump();
      final lista = find.byIcon(PhosphorIconsRegular.listBullets); // El diseño que lista los ejercicios.
      await tester.ensureVisible(lista);
      await tester.tap(lista);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Bíceps en polea'), findsOneWidget);
      expect(find.textContaining('propio'), findsNothing);
      fit.persistNow(); // Sin el guardado diferido de crearPropio pendiente al terminar.
    });

    test('el texto para compartir rutinas usa el nombre guardado, sin "(propio)"', () {
      final id = crearPropio();
      final texto = fit.planSummaryText([
        Routine('r-propio', 'Brazos', [id]),
      ]);

      expect(texto, contains('• Bíceps en polea — '));
      expect(texto, isNot(contains('propio')));
    });

    test('la lista para pedirle un plan a la IA usa el nombre guardado, sin "(propio)"', () {
      crearPropio();
      final texto = fit.planRequestText();

      expect(texto, contains('\nBíceps en polea | biceps | Cable | Beginner'));
      expect(texto, isNot(contains('propio')));
    });

    test('la copia ZIP nombra sus fotos con el nombre guardado, sin "(propio)"', () async {
      final id = crearPropio();
      final foto = File('${tmp.path}/IMG_1.png')
        ..writeAsBytesSync(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 1]));
      await fit.attachExerciseMedia(id, foto.path);

      final nombres = ZipDecoder().decodeBytes(await buildBackupZip()).files.map((f) => f.name).toList();

      expect(nombres, contains('media/images/biceps-en-polea.png'));
      expect(nombres.where((n) => n.contains('propio')), isEmpty);
    });
  });
}
