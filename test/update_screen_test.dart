// Validador de versión (sesión 28): la pantalla "Actualiza Infyter" en la app de verdad (AppShell). Aparece cuando la
// tienda tiene una versión más nueva, nunca durante un entrenamiento, y "Actualizar" abre la tienda. La fuente de la
// respuesta es falsa; Play y el lookup de Apple tienen sus propios tests.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/app/infyter_app.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/screens/update_required_screen.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/services/progress_reminder.dart';
import 'package:infyter/services/update_check.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:infyter/state/update_gate.dart';
import 'package:infyter/theme/app_theme.dart';
import 'package:infyter/widgets/ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Store.instance.debugReset();
    await Store.instance.init();
    ProgressReminder.instance.enabled = false;
    setAppLanguage('es');
    fit.resetAllData();
    fit.onboarded = true;
  });

  tearDown(() {
    fit.resetAllData();
    setAppLanguage('en');
    updateGate = UpdateGate();
  });

  Future<void> abrirApp(WidgetTester tester) async {
    await tester.pumpWidget(const InfyterApp());
    await tester.pump(); // Primer frame: la consulta corre después de él.
    await tester.pump(const Duration(milliseconds: 100));
  }

  // Se arma al usarlo: el idioma de la app es el que deja cada setUp.
  Finder titulo() => find.text(t.updateRequiredTitle);

  group('en la app', () {
    testWidgets(
      'si la tienda tiene una versión más nueva, la app muestra "Actualiza Infyter" con la versión',
      (tester) async {
        updateGate = UpdateGate(
          source: () async => const UpdateCheck(UpdateReason.newer, storeVersion: '1.3.3'),
        );

        await abrirApp(tester);

        expect(titulo(), findsOneWidget);
        expect(find.text(t.updateRequiredVersion('1.3.3')), findsOneWidget);
        expect(find.text(t.updateRequiredData), findsOneWidget);
      },
    );

    testWidgets('en Android, sin número de versión, la pantalla no inventa uno', (tester) async {
      updateGate = UpdateGate(source: () async => const UpdateCheck(UpdateReason.newer));

      await abrirApp(tester);

      expect(titulo(), findsOneWidget);
      expect(find.textContaining(t.updateRequiredVersion('').trim()), findsNothing);
    });

    testWidgets('al día o sin respuesta, la app se usa normal', (tester) async {
      for (final reason in [UpdateReason.equal, UpdateReason.offline, UpdateReason.timeout]) {
        var consultas = 0;
        updateGate = UpdateGate(
          source: () async {
            consultas++;
            return UpdateCheck(reason);
          },
        );
        await tester.pumpWidget(
          const SizedBox(),
        ); // Cierra la app anterior: cada vuelta es un arranque nuevo.
        await abrirApp(tester);
        expect(consultas, 1, reason: reason.name);
        expect(titulo(), findsNothing, reason: reason.name);
      }
    });

    testWidgets('durante un entrenamiento no aparece; al descartarlo, sí', (tester) async {
      final id = fit.createRoutine('Empuje');
      fit.toggleRoutineExercise(id, 'EIeI8Vf');
      fit.startRoutine(fit.routines.first);
      updateGate = UpdateGate(
        source: () async => const UpdateCheck(UpdateReason.newer, storeVersion: '1.3.3'),
      );

      await abrirApp(tester);
      expect(fit.session, isNotNull);
      expect(titulo(), findsNothing);

      fit.parkSession(); // En pausa sigue siendo un entrenamiento abierto.
      await tester.pump(const Duration(milliseconds: 500));
      expect(titulo(), findsNothing);

      fit.discardSession();
      await tester.pump(const Duration(milliseconds: 500));
      expect(titulo(), findsOneWidget);
    });

    testWidgets('con una nota a medio escribir no aparece; al cerrar el editor, sí', (tester) async {
      updateGate = UpdateGate(source: () async => const UpdateCheck(UpdateReason.newer));
      fit.openNoteEditor();

      await abrirApp(tester);
      expect(fit.route, 'note-edit');
      expect(titulo(), findsNothing);

      fit.closeNoteEditor();
      await tester.pump(const Duration(milliseconds: 500));
      expect(titulo(), findsOneWidget);
    });

    testWidgets('al volver a la app después de 1 hora vuelve a consultar la tienda', (tester) async {
      var ahora = DateTime(2026, 11, 1, 10);
      var consultas = 0;
      updateGate = UpdateGate(
        source: () async {
          consultas++;
          return const UpdateCheck(UpdateReason.equal);
        },
        clock: () => ahora,
      );
      await abrirApp(tester);
      expect(consultas, 1);

      ahora = ahora.add(const Duration(minutes: 61));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 100));

      expect(consultas, 2);
    });

    testWidgets('si una consulta posterior falla, la app vuelve a usarse (fail-open)', (tester) async {
      var respuesta = const UpdateCheck(UpdateReason.newer);
      updateGate = UpdateGate(source: () async => respuesta);
      await abrirApp(tester);
      expect(titulo(), findsOneWidget);

      respuesta = const UpdateCheck(UpdateReason.offline);
      await updateGate.checkNow();
      await tester.pump(const Duration(milliseconds: 500));

      expect(titulo(), findsNothing);
    });
  });

  group('el botón Actualizar', () {
    Future<void> pantalla(WidgetTester tester, Future<bool> Function() abrir) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: UpdateRequiredScreen(version: '1.3.3', openStore: abrir),
      ),
    );

    testWidgets('abre la tienda', (tester) async {
      var veces = 0;
      await pantalla(tester, () async {
        veces++;
        return true;
      });

      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();

      expect(veces, 1);
      expect(find.text(t.updateStoreFailed), findsNothing);
    });

    testWidgets('si no se puede abrir la tienda, lo dice y deja reintentar', (tester) async {
      var veces = 0;
      await pantalla(tester, () async {
        veces++;
        return false;
      });

      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();
      expect(find.text(t.updateStoreFailed), findsOneWidget);

      await tester.tap(find.byType(PrimaryButton));
      await tester.pump();
      expect(veces, 2);
    });
  });

  group('qué abre "Actualizar" en cada sistema', () {
    test('en Android prueba la app Play Store y, si no está, Google Play en la web', () async {
      final abiertos = <String>[];
      final ok = await openStoreForUpdate(
        os: 'android',
        launch: (uri) async {
          abiertos.add('$uri');
          return uri.scheme == 'https';
        },
      );
      expect(ok, isTrue);
      expect(abiertos, [
        'market://details?id=com.infyter.app',
        'https://play.google.com/store/apps/details?id=com.infyter.app',
      ]);
    });

    test('en iPhone abre la ficha fija de Infyter en la App Store', () async {
      final abiertos = <String>[];
      await openStoreForUpdate(
        os: 'ios',
        launch: (uri) async {
          abiertos.add('$uri');
          return true;
        },
      );
      expect(abiertos, ['https://apps.apple.com/app/id6820268450']);
    });

    test('si ningún enlace abre (o falla), devuelve false sin romper', () async {
      final ok = await openStoreForUpdate(os: 'android', launch: (_) async => throw StateError('sin tienda'));
      expect(ok, isFalse);
    });
  });
}
