import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/app/infyter_app.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/services/progress_reminder.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    ProgressReminder.instance.enabled = false;
    setAppLanguage('es');
    fit.onboarded = true;
    fit.session = null;
    fit.bgPattern = 'dynamic';
    fit.resetRoute('home');
  });

  testWidgets('tres cambios de pestaña en menos de 420 ms con fondo dinámico no repiten claves', (tester) async {
    await tester.pumpWidget(const InfyterApp());
    await tester.pump();

    fit.goProgress();
    await tester.pump(const Duration(milliseconds: 100));
    fit.goHome();
    await tester.pump(const Duration(milliseconds: 100));
    fit.goExercises();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
