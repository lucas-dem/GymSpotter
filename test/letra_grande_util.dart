import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const kEscalas = [1.0, 1.15, 1.3, 1.5, 2.0];

/// Loads the app's real Nunito files so text is measured as on a phone, not with the test font.
Future<void> cargarNunito() async {
  final loader = FontLoader('Nunito');
  for (final f in Directory('assets/fonts').listSync().whereType<File>()) {
    if (f.path.contains('Nunito')) loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
  }
  await loader.load();
}

bool _oculto(RenderObject r) {
  for (RenderObject? a = r.parent; a != null; a = a.parent) {
    if (a is RenderOffstage && a.offstage) return true;
    if (a is RenderOpacity && a.opacity == 0) return true;
    if (a is RenderAnimatedOpacity && a.opacity.value == 0) return true;
  }
  return false;
}

String _origen(RenderObject r) {
  final c = r.debugCreator;
  if (c is! DebugCreator) return '';
  final chain = <String>[];
  c.element.visitAncestorElements((e) {
    final w = e.widget.runtimeType.toString();
    if (!w.startsWith('_') &&
        !const {
          'Padding',
          'Align',
          'Center',
          'SizedBox',
          'Container',
          'Semantics',
          'DefaultTextStyle',
          'Builder',
          'KeyedSubtree',
          'MediaQuery',
          'RepaintBoundary',
          'ConstrainedBox',
          'DecoratedBox',
          'Transform',
          'Opacity',
          'AnimatedBuilder',
          'ListenableBuilder',
          'Flexible',
          'Expanded',
          'Row',
          'Column',
          'Stack',
          'Positioned',
          'GestureDetector',
          'RawGestureDetector',
          'Listener',
          'ClipRect',
          'LimitedBox',
          'IgnorePointer',
          'AbsorbPointer',
          'MouseRegion',
          'Actions',
          'Focus',
          'Shortcuts',
          'AnimatedSwitcher',
          'AnimatedSize',
          'TickerMode',
          'Offstage',
          'IconTheme',
          'Material',
          'Ink',
          'InkWell',
          'AnimatedDefaultTextStyle',
          'NotificationListener',
          'ValueListenableBuilder',
          'FadeTransition',
          'Wrap',
          'FittedBox',
          'Flex',
          'Text',
          'RichText',
          'ExcludeSemantics',
          'MergeSemantics',
          'CustomPaint',
          'AnimatedContainer',
          'AnimatedOpacity',
          'Rise',
          'ClipRRect',
          'AnimatedPadding',
          'SliverToBoxAdapter',
          'IntrinsicHeight',
          'IntrinsicWidth',
          'Visibility',
          'SafeArea',
          'Baseline',
          'Spacer',
          'BackdropFilter',
          'AnimatedScale',
          'ScaleTransition',
          'SlideTransition',
          'AnimatedSlide',
          'TweenAnimationBuilder',
          'AnimatedAlign',
          'AnimatedPositioned',
          'LayoutBuilder',
          'ColoredBox',
          'PhysicalModel',
          'StatefulBuilder',
          'AnimatedRotation',
          'RotationTransition',
          'OverflowBox',
          'UnconstrainedBox',
          'SizedOverflowBox',
          'FractionallySizedBox',
          'AspectRatio',
          'Card',
          'Hero',
          'Dismissible',
          'PageStorage',
          'Scrollable',
          'Viewport',
          'SingleChildScrollView',
          'ListView',
          'CustomScrollView',
          'SliverList',
          'SliverPadding',
          'ScrollConfiguration',
          'PrimaryScrollController',
          'GlowingOverscrollIndicator',
          'StretchingOverscrollIndicator',
        }.contains(w)) {
      chain.add(w);
    }
    return chain.length < 4;
  });
  return chain.join(' < ');
}

Rect _en(RenderBox hijo, RenderBox ancestro) =>
    MatrixUtils.transformRect(hijo.getTransformTo(ancestro), Offset.zero & hijo.size);

bool _recorta(RenderObject a) => switch (a) {
  RenderClipRect() || RenderClipRRect() || RenderClipPath() => true,
  RenderStack(:final clipBehavior) => clipBehavior != Clip.none,
  RenderAnimatedSize(:final clipBehavior) => clipBehavior != Clip.none,
  RenderFlex(:final clipBehavior) => clipBehavior != Clip.none,
  _ => false,
};

/// Every visible text whose glyph box does not fit in its own box or in a clipping ancestor.
List<String> textoCortado(WidgetTester tester) {
  const tol = 0.5;
  final out = <String>{};
  for (final r in tester.allRenderObjects.whereType<RenderParagraph>()) {
    if (!r.attached || !r.hasSize || r.size.isEmpty || _oculto(r)) continue;
    final txt = r.text.toPlainText().replaceAll('\n', ' ');
    if (txt.trim().isEmpty) continue;
    final ts = r.textSize;
    final donde = _origen(r);
    if (ts.height > r.size.height + tol) {
      out.add(
        'alto "$txt": texto ${ts.height.toStringAsFixed(1)} > caja ${r.size.height.toStringAsFixed(1)} [$donde]',
      );
    }
    if (ts.width > r.size.width + tol) {
      out.add(
        'ancho "$txt": texto ${ts.width.toStringAsFixed(1)} > caja ${r.size.width.toStringAsFixed(1)} [$donde]',
      );
    }
    for (RenderObject? a = r.parent; a != null; a = a.parent) {
      if (a is RenderAbstractViewport) break;
      if (a is! RenderBox || !_recorta(a) || !a.hasSize) continue;
      final rect = _en(r, a);
      final caja = Offset.zero & a.size;
      final arriba = caja.top - rect.top, abajo = rect.bottom - caja.bottom;
      final izq = caja.left - rect.left, der = rect.right - caja.right;
      if (rect.width <= 0 || rect.height <= 0) break;
      final fuera =
          rect.bottom <= caja.top ||
          rect.top >= caja.bottom ||
          rect.right <= caja.left ||
          rect.left >= caja.right;
      if (fuera) break;
      if (arriba > tol || abajo > tol || izq > tol || der > tol) {
        out.add(
          'recorte ${a.runtimeType} "$txt": sobra arriba ${arriba.toStringAsFixed(1)}, abajo '
          '${abajo.toStringAsFixed(1)}, izq ${izq.toStringAsFixed(1)}, der ${der.toStringAsFixed(1)} [$donde]',
        );
      }
      break;
    }
  }
  return out.toList();
}

/// Text that was shortened with an ellipsis (reported, not always a defect).
List<String> textoConPuntos(WidgetTester tester) => [
  for (final r in tester.allRenderObjects.whereType<RenderParagraph>())
    if (r.attached && r.hasSize && !_oculto(r) && r.didExceedMaxLines && r.overflow == TextOverflow.ellipsis)
      '"${r.text.toPlainText()}" [${_origen(r)}]',
];

/// Runs [body] collecting layout errors (overflows) instead of failing on the first one.
Future<List<String>> conErrores(Future<void> Function() body) async {
  final errores = <String>[];
  final antes = FlutterError.onError;
  FlutterError.onError = (d) {
    final s = d.toString();
    final loc = RegExp(r'(lib/[\w/]+\.dart:\d+)').firstMatch(s)?.group(1) ?? '';
    errores.add('${d.exceptionAsString().split('\n').first} $loc');
  };
  try {
    await body();
  } finally {
    FlutterError.onError = antes;
  }
  return errores;
}

void usarPantalla(WidgetTester tester, {required double ancho, required double alto, double escala = 1.0}) {
  tester.view.devicePixelRatio = 2.625;
  tester.view.physicalSize = Size(ancho * 2.625, alto * 2.625);
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}
