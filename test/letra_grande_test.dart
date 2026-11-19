import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/theme/app_theme.dart';
import 'package:infyter/widgets/entrance.dart';
import 'package:infyter/widgets/fit_text.dart';
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

  double dibujado(WidgetTester tester, String texto) {
    final r = tester.renderObject<RenderParagraph>(find.text(texto));
    return r.textScaler.scale(r.text.style!.fontSize!) *
        MatrixUtils.transformRect(r.getTransformTo(null), const Rect.fromLTWH(0, 0, 1, 1)).height;
  }

  Widget fila(List<(String, double)> rotulos, {bool grupo = true}) {
    final row = SizedBox(
      width: 200,
      child: Row(
        children: [
          for (final (texto, tam) in rotulos)
            Expanded(
              child: FitText(texto, maxLines: 1, style: TextStyle(fontSize: tam)),
            ),
        ],
      ),
    );
    return grupo ? FitTextGroup(child: row) : row;
  }

  for (final escala in kEscalas.where((e) => e > 1)) {
    testWidgets('labels in one group shrink by the factor of the one with least room at text scale $escala', (
      tester,
    ) async {
      await _pump(tester, escala, fila([('REPS', 11), ('PESO (KG) EXTRA LARGO', 11)]));
      await tester.pump();
      final corto = dibujado(tester, 'REPS'), largo = dibujado(tester, 'PESO (KG) EXTRA LARGO');
      expect(largo, lessThan(11 * escala), reason: 'el largo no entra y se achica');
      expect(corto, closeTo(largo, 0.01), reason: 'el corto usa el mismo factor');
      expect(gruposDesparejos(tester), isEmpty);
      await _pump(tester, escala, fila([('REPS', 11), ('PESO (KG) EXTRA LARGO', 11)], grupo: false));
      expect(
        dibujado(tester, 'REPS'),
        closeTo(11 * escala, 0.01),
        reason: 'sin grupo, cada uno con su tamaño',
      );
    });
  }

  testWidgets('at normal size a group draws its labels exactly like plain text', (tester) async {
    await _pump(tester, 1.0, fila([('REPS', 11), ('PESO', 11)]));
    final conGrupo = [
      for (final t in ['REPS', 'PESO']) tester.getTopLeft(find.text(t)),
    ];
    await _pump(tester, 1.0, fila([('REPS', 11), ('PESO', 11)], grupo: false));
    final sinGrupo = [
      for (final t in ['REPS', 'PESO']) tester.getTopLeft(find.text(t)),
    ];
    expect(conGrupo, sinGrupo);
  });

  testWidgets('at normal size a label that does not fit leaves its neighbours at their own size', (
    tester,
  ) async {
    await _pump(tester, 1.0, fila([('REPS', 11), ('WIEDERHOLUNGEN GEWICHT', 11)]));
    await tester.pump();
    expect(dibujado(tester, 'REPS'), closeTo(11, 0.01));
    expect(dibujado(tester, 'WIEDERHOLUNGEN GEWICHT'), lessThan(11));
  });

  testWidgets(
    'at normal size a group under IntrinsicHeight lays out like the scale-down FittedBox it replaced',
    (tester) async {
      Widget tiles(bool grupo) {
        Widget label(String x) => grupo
            ? FitText(x, maxLines: 1, style: const TextStyle(fontSize: 10, letterSpacing: 0.9))
            : FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(x, maxLines: 1, style: const TextStyle(fontSize: 10, letterSpacing: 0.9)),
              );
        final row = IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final x in ['ТРЕНИРОВОК', 'ПОДХОДОВ', 'ВРЕМЯ'])
                Expanded(child: Column(children: [label(x), const Text('12')])),
            ],
          ),
        );
        return SizedBox(width: 150, child: grupo ? FitTextGroup(child: row) : row);
      }

      Rect dibujo(String x) {
        final r = tester.renderObject<RenderParagraph>(find.text(x));
        return MatrixUtils.transformRect(r.getTransformTo(null), Offset.zero & r.textSize);
      }

      const rotulos = ['ТРЕНИРОВОК', 'ПОДХОДОВ', 'ВРЕМЯ'];
      await _pump(tester, 1.0, tiles(false));
      final antes = {for (final x in rotulos) x: dibujo(x)};
      final alto = tester.getSize(find.byType(IntrinsicHeight)).height;
      expect(antes['ТРЕНИРОВОК']!.height, lessThan(antes['ВРЕМЯ']!.height), reason: 'el caso: uno no entra');
      await _pump(tester, 1.0, tiles(true));
      await tester.pump();
      for (final x in rotulos) {
        final ahora = dibujo(x);
        for (final (a, b) in [
          (ahora.left, antes[x]!.left),
          (ahora.top, antes[x]!.top),
          (ahora.right, antes[x]!.right),
          (ahora.bottom, antes[x]!.bottom),
        ]) {
          expect(a, closeTo(b, 0.01), reason: x);
        }
      }
      expect(tester.getSize(find.byType(IntrinsicHeight)).height, alto);
    },
  );

  testWidgets('the detector flags a group whose labels are drawn at different sizes', (tester) async {
    await _pump(tester, 1.5, fila([('REPS', 11), ('PESO', 13)]));
    expect(gruposDesparejos(tester), hasLength(1));
  });

  testWidgets('the detector flags text drawn over another text or over a button', (tester) async {
    await _pump(
      tester,
      1.0,
      SizedBox(
        width: 200,
        height: 60,
        child: Stack(
          children: [
            const Positioned(left: 0, top: 0, child: Text('4 ejercicios')),
            Positioned(
              left: 0,
              top: 6,
              child: GestureDetector(onTap: () {}, child: const Text('Empezar')),
            ),
            const Positioned(left: 120, top: 0, child: Text('solo')),
          ],
        ),
      ),
    );
    final f = encimados(tester);
    expect(f.where((x) => x.startsWith('encimados "4 ejercicios" y "Empezar"')), hasLength(1));
    expect(f.where((x) => x.startsWith('sobre boton "4 ejercicios"')), hasLength(1));
    expect(f.where((x) => x.contains('"solo"')), isEmpty);
  });
}
