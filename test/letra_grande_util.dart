import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
  var hijo = r;
  for (RenderObject? a = r.parent; a != null; hijo = a, a = a.parent) {
    if (a is RenderOffstage && a.offstage) return true;
    if (a is RenderOpacity && a.opacity == 0) return true;
    if (a is RenderAnimatedOpacity && a.opacity.value == 0) return true;
    if (a is RenderIndexedStack && a.getChildrenAsList().indexOf(hijo as RenderBox) != a.index) return true;
  }
  return false;
}

Iterable<RenderParagraph> _visibles(WidgetTester tester) => tester.allRenderObjects
    .whereType<RenderParagraph>()
    .where((r) => r.attached && r.hasSize && !r.size.isEmpty && !_oculto(r) && r.text.toPlainText().trim().isNotEmpty);

String _origen(RenderObject r) {
  final c = r.debugCreator;
  if (c is! DebugCreator) return '';
  final chain = <String>[];
  c.element.visitAncestorElements((e) {
    final w = e.widget.runtimeType.toString();
    if (!w.startsWith('_') &&
        !w.startsWith('NotificationListener') &&
        !const {
          'Padding',
          'IndexedSemantics',
          'KeepAlive',
          'AutomaticKeepAlive',
          'StretchEffect',
          'RiseScope',
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
      final lista = a is RenderViewportBase ? a.axis : null;
      if (a is RenderAbstractViewport && lista == null) break;
      if (a is! RenderBox || (lista == null && !_recorta(a)) || !a.hasSize) continue;
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
      final vertical = arriba > tol || abajo > tol, horizontal = izq > tol || der > tol;
      if (lista == Axis.vertical ? horizontal : lista == Axis.horizontal ? vertical : vertical || horizontal) {
        out.add(
          'recorte ${a.runtimeType} "$txt": sobra arriba ${arriba.toStringAsFixed(1)}, abajo '
          '${abajo.toStringAsFixed(1)}, izq ${izq.toStringAsFixed(1)}, der ${der.toStringAsFixed(1)} [$donde]',
        );
        break;
      }
      if (lista != null) break;
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

int _cierre(String s, int i) {
  var d = 0;
  for (var k = i; k < s.length; k++) {
    if (s[k] == '{') d++;
    if (s[k] == '}' && --d == 0) return k;
  }
  return s.length - 1;
}

/// Every literal form an ARB message can take, with each placeholder as \u0000.
List<String> _variantes(String m) {
  final i = m.indexOf('{');
  if (i < 0) return [m];
  final j = _cierre(m, i);
  final dentro = m.substring(i + 1, j);
  final partes = dentro.split(',');
  final medio = <String>[];
  if (partes.length >= 3 && const {'plural', 'select'}.contains(partes[1].trim())) {
    final cuerpo = dentro.substring(partes[0].length + partes[1].length + 2);
    for (var k = cuerpo.indexOf('{'); k >= 0; k = cuerpo.indexOf('{', _cierre(cuerpo, k) + 1)) {
      medio.addAll(_variantes(cuerpo.substring(k + 1, _cierre(cuerpo, k)).replaceAll('#', '\u0000')));
    }
  } else {
    medio.add('\u0000');
  }
  final pre = m.substring(0, i);
  return [
    for (final x in medio)
      for (final y in _variantes(m.substring(j + 1))) '$pre$x$y',
  ];
}

final _letra = RegExp(r'\p{L}', unicode: true);
final _sinEspacios = RegExp(
  r'[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}\p{Script=Thai}]',
  unicode: true,
);
final _rotulos = <String, List<RegExp>>{};

/// The app's fixed copy for [idioma] (its ARB file), as whole-text patterns that ignore case.
List<RegExp> rotulosDe(String idioma) => _rotulos.putIfAbsent(idioma, () {
  final arb = jsonDecode(File('lib/l10n/app_$idioma.arb').readAsStringSync()) as Map<String, dynamic>;
  return [
    for (final MapEntry(:key, :value) in arb.entries)
      if (!key.startsWith('@') && value is String)
        for (final v in _variantes(value))
          if (_letra.allMatches(v).length >= 3)
            RegExp(
              '^${v.trim().split('\u0000').map(RegExp.escape).join('.+')}\$',
              caseSensitive: false,
              unicode: true,
            ),
  ];
});

/// Whether [txt] is app copy (a label) rather than user or catalog content.
bool esRotulo(String txt, String idioma) {
  final pat = rotulosDe(idioma);
  bool uno(String s) => pat.any((p) => p.hasMatch(s.trim()));
  return uno(txt) || (txt.contains(' · ') && txt.split(' · ').every(uno));
}

/// Words that wrap in the middle ("Calentamien|to"): two letters on different lines with no space between.
List<String> palabrasPartidas(WidgetTester tester) {
  final out = <String>{};
  for (final r in _visibles(tester)) {
    final txt = r.text.toPlainText();
    double? arribaAntes;
    for (var i = 0; i < txt.length; i++) {
      final cajas = r.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
      if (cajas.isEmpty) {
        arribaAntes = null;
        continue;
      }
      final arriba = cajas.first.top;
      final letras = i > 0 && _letra.hasMatch(txt[i - 1]) && _letra.hasMatch(txt[i]);
      if (arribaAntes != null && arriba > arribaAntes + 1 && letras && !_sinEspacios.hasMatch(txt[i])) {
        var a = i - 1, b = i;
        while (a > 0 && _letra.hasMatch(txt[a - 1])) {
          a--;
        }
        while (b < txt.length - 1 && _letra.hasMatch(txt[b + 1])) {
          b++;
        }
        out.add(
          'partida "${txt.substring(a, i)}|${txt.substring(i, b + 1)}" en "${txt.replaceAll('\n', ' ')}" [${_origen(r)}]',
        );
      }
      arribaAntes = arriba;
    }
  }
  return out.toList();
}

bool _seAdapta(RenderParagraph r) {
  for (RenderObject? a = r.parent; a != null; a = a.parent) {
    if (a is RenderFittedBox) return true;
    if (a is RenderAbstractViewport) return false;
  }
  return false;
}

/// Labels (app copy) shortened with "…", cut at their line limit, or one line that fills more than [borde] of
/// its width: phones measure a little wider than tests, so those end in "…" on a device.
List<String> rotulosAcortados(WidgetTester tester, String idioma, {double borde = 0.97}) => [
  for (final r in _visibles(tester))
    if (esRotulo(r.text.toPlainText(), idioma))
      if (r.didExceedMaxLines)
        '${r.overflow == TextOverflow.ellipsis ? 'puntos' : 'lineas de mas'} "${r.text.toPlainText()}" [${_origen(r)}]'
      else if (r.maxLines == 1 &&
          r.constraints.hasBoundedWidth &&
          !_seAdapta(r) &&
          r.getMaxIntrinsicWidth(double.infinity) > borde * r.constraints.maxWidth)
        'al borde "${r.text.toPlainText()}": ${(100 * r.getMaxIntrinsicWidth(double.infinity) / r.constraints.maxWidth).toStringAsFixed(1)} % '
            'del ancho [${_origen(r)}]',
];

/// Whether a row or wrap lays [a] and [b] out next to each other (not one layer drawn over another).
bool _ladoALado(RenderObject a, RenderObject b) {
  final deA = <RenderObject>{};
  for (RenderObject? x = a.parent; x != null; x = x.parent) {
    deA.add(x);
  }
  for (RenderObject? x = b.parent; x != null; x = x.parent) {
    if (deA.contains(x)) return x is RenderFlex || x is RenderWrap;
  }
  return false;
}

/// Two labels on the same line whose glyphs touch or overlap (less than [minimo] dp apart).
List<String> rotulosPegados(WidgetTester tester, String idioma, {double minimo = 3}) {
  final lineas = <(RenderParagraph, Rect)>[];
  for (final r in _visibles(tester)) {
    final txt = r.text.toPlainText();
    if (!esRotulo(txt, idioma)) continue;
    final m = r.getTransformTo(null);
    var visible = Rect.largest;
    for (RenderObject? a = r.parent; a != null; a = a.parent) {
      if (a is RenderBox && a.hasSize && (_recorta(a) || a is RenderAbstractViewport)) {
        visible = visible.intersect(MatrixUtils.transformRect(a.getTransformTo(null), Offset.zero & a.size));
      }
    }
    final propias = <Rect>[];
    for (final b in r.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: txt.trimRight().length))) {
      final rect = MatrixUtils.transformRect(m, b.toRect());
      final k = propias.indexWhere((p) => (p.top - rect.top).abs() < 1);
      if (k < 0) {
        propias.add(rect);
      } else {
        propias[k] = propias[k].expandToInclude(rect);
      }
    }
    lineas.addAll([
      for (final p in propias.map(visible.intersect))
        if (p.width > 0 && p.height > 0) (r, p),
    ]);
  }
  final out = <String>{};
  for (var i = 0; i < lineas.length; i++) {
    for (var j = i + 1; j < lineas.length; j++) {
      final (ra, a) = lineas[i];
      final (rb, b) = lineas[j];
      if (identical(ra, rb) || !_ladoALado(ra, rb)) continue;
      final solape = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
      if (solape < 0.5 * math.min(a.height, b.height)) continue;
      final hueco = math.max(b.left - a.right, a.left - b.right);
      if (hueco < minimo) {
        out.add(
          'pegados "${ra.text.toPlainText()}" y "${rb.text.toPlainText()}": separacion ${hueco.toStringAsFixed(1)} '
          '[${_origen(ra)}]',
        );
      }
    }
  }
  return out.toList();
}

/// Everything the large-text checks flag: clipped, split, shortened and touching text.
List<String> problemasDeTexto(WidgetTester tester, String idioma) => [
  ...textoCortado(tester),
  ...palabrasPartidas(tester),
  ...rotulosAcortados(tester, idioma),
  ...rotulosPegados(tester, idioma),
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
