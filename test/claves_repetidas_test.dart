import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/app/infyter_app.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/services/progress_reminder.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:infyter/wear/wear_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    ProgressReminder.instance.enabled = false;
    setAppLanguage('es');
    fit.session = null;
    fit.bgPattern = 'dynamic';
    fit.resetRoute('home');
  });

  tearDown(() => fit.onboarded = true);

  testWidgets('en el reloj, tres cambios de pantalla en menos de 220 ms no repiten claves', (tester) async {
    tester.view.physicalSize = const Size(454, 454);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const WearApp());
    await tester.pump();

    fit.pushRoute('routines');
    await tester.pump(const Duration(milliseconds: 60));
    fit.popRoute();
    await tester.pump(const Duration(milliseconds: 60));
    fit.pushRoute('settings');
    await tester.pump(const Duration(milliseconds: 60));

    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'en la bienvenida, ir y volver dos veces entre el fondo de puntos y el de Inicio en menos de 420 ms no repite claves',
    (tester) async {
      fit.onboarded = false;
      expect(fit.backgroundForRoute('home'), isNot('dots'));
      await tester.pumpWidget(const InfyterApp());
      await tester.pump();
      final pagina = tester.widget<PageView>(find.byType(PageView)).controller!;

      pagina.jumpToPage(5);
      await tester.pump(const Duration(milliseconds: 100));
      pagina.jumpToPage(4);
      await tester.pump(const Duration(milliseconds: 100));
      pagina.jumpToPage(5);
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );
}
