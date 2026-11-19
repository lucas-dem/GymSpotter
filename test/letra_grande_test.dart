import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/theme/app_theme.dart';
import 'package:infyter/widgets/entrance.dart';
import 'package:infyter/widgets/rolling_text.dart';
import 'package:infyter/widgets/timer_panel.dart';
import 'package:infyter/widgets/ui_kit.dart';

import 'letra_grande_util.dart';

Future<void> _pump(WidgetTester tester, double escala, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(size: const Size(411, 914), textScaler: TextScaler.linear(escala)),
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
}

Future<void> _sinCortes(WidgetTester tester, double escala, Widget child) async {
  final errores = await conErrores(() => _pump(tester, escala, child));
  expect(errores, isEmpty, reason: 'desborde a escala $escala');
  expect(textoCortado(tester), isEmpty, reason: 'texto cortado a escala $escala');
}

void main() {
  setUpAll(cargarNunito);

  for (final escala in kEscalas) {
    testWidgets('the stepper shows whole digits at text scale $escala', (tester) async {
      await _sinCortes(tester, escala, StepperControl(value: '12', onDec: () {}, onInc: () {}));
      if (escala == 1.0) {
        expect(
          tester.getSize(find.byType(StepperControl)).height,
          30,
          reason: 'a 100 % mide lo mismo que antes',
        );
      }
      await _sinCortes(
        tester,
        escala,
        StepperControl(value: '102.5', fontSize: 22, onDec: () {}, onInc: () {}),
      );
    });

    testWidgets('the rest clock and its stats show whole digits at text scale $escala', (tester) async {
      await _sinCortes(
        tester,
        escala,
        TimerPanel(
          label: 'Descanso',
          remaining: 75,
          total: 90,
          elapsed: '12:34',
          elapsedLabel: 'TRANSCURRIDO',
          sets: '3/12',
          setsLabel: 'SERIES',
          hint: 'Tocá para saltar',
          onTap: () {},
          onMinus: () {},
          onPlus: () {},
        ),
      );
    });

    testWidgets('a rolling clock keeps its box as tall as its digits at text scale $escala', (tester) async {
      final style = AppTheme.f(18, weight: FontWeight.w700);
      await _pump(tester, escala, RollingText('1:02:45', style: style));
      final box = tester.getSize(find.byType(RollingText));
      final painted = TextPainter(
        text: TextSpan(text: '0', style: style),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.linear(escala),
      )..layout();
      expect(box.height, greaterThanOrEqualTo(painted.height - 0.5));
      painted.dispose();
      expect(box.height, closeTo(18 * 1.15 * escala, 0.01), reason: 'a 100 % mide lo mismo que antes');
      expect(textoCortado(tester), isEmpty);
    });

    testWidgets('a counting-in number shows whole digits while it rolls at text scale $escala', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: MediaQueryData(size: const Size(411, 914), textScaler: TextScaler.linear(escala)),
            child: Scaffold(
              body: Center(
                child: RollIn('1240', style: AppTheme.f(28, weight: FontWeight.w800)),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(RollingText), findsNothing, reason: 'todavía está girando');
      expect(
        textoCortado(tester).where((c) => c.startsWith('alto')),
        isEmpty,
        reason: 'mientras gira, cada rueda tiene el alto de un dígito entero',
      );
      await tester.pump(const Duration(milliseconds: 1500));
      expect(textoCortado(tester), isEmpty, reason: 'al terminar');
    });
  }
}
