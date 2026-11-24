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

Iterable<RenderParagraph> _visibles(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderParagraph>().where(
      (r) =>
          r.attached && r.hasSize && !r.size.isEmpty && !_oculto(r) && r.text.toPlainText().trim().isNotEmpty,
    );

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
      if (lista == Axis.vertical
          ? horizontal
          : lista == Axis.horizontal
          ? vertical
          : vertical || horizontal) {
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
    if (a is RenderFittedBox || a.runtimeType.toString() == '_RenderAchique') return true;
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

/// The part of the screen where [r] can be seen: its clipping ancestors and scroll views, in global coordinates.
Rect _zonaVisible(RenderObject r) {
  var visible = Rect.largest;
  for (RenderObject? a = r.parent; a != null; a = a.parent) {
    if (a is RenderBox && a.hasSize && (_recorta(a) || a is RenderAbstractViewport)) {
      visible = visible.intersect(MatrixUtils.transformRect(a.getTransformTo(null), Offset.zero & a.size));
    }
  }
  return visible;
}

/// Each drawn line of [r] as a global rectangle, cut to the part that can be seen.
List<Rect> _lineasVisibles(RenderParagraph r) {
  final txt = r.text.toPlainText();
  final m = r.getTransformTo(null);
  final visible = _zonaVisible(r).intersect(MatrixUtils.transformRect(m, Offset.zero & r.size).inflate(0.5));
  final propias = <Rect>[];
  for (final b in r.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: txt.trimRight().length),
  )) {
    final rect = MatrixUtils.transformRect(m, b.toRect());
    final k = propias.indexWhere((p) => (p.top - rect.top).abs() < 1);
    if (k < 0) {
      propias.add(rect);
    } else {
      propias[k] = propias[k].expandToInclude(rect);
    }
  }
  return [
    for (final p in propias.map(visible.intersect))
      if (p.width > 0 && p.height > 0) p,
  ];
}

/// Two labels on the same line whose glyphs touch or overlap (less than [minimo] dp apart).
List<String> rotulosPegados(WidgetTester tester, String idioma, {double minimo = 3}) {
  final lineas = <(RenderParagraph, Rect)>[];
  for (final r in _visibles(tester)) {
    if (!esRotulo(r.text.toPlainText(), idioma)) continue;
    lineas.addAll([for (final p in _lineasVisibles(r)) (r, p)]);
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

bool _desciende(RenderObject hijo, RenderObject ancestro) {
  for (RenderObject? a = hijo.parent; a != null; a = a.parent) {
    if (identical(a, ancestro)) return true;
  }
  return false;
}

/// Whether [a] and [b] belong to different overlay entries (a sheet over a screen), not to one layout.
bool _otraCapa(RenderObject a, RenderObject b) {
  final deA = <RenderObject>{};
  for (RenderObject? x = a.parent; x != null; x = x.parent) {
    deA.add(x);
  }
  for (RenderObject? x = b.parent; x != null; x = x.parent) {
    if (deA.contains(x)) return x.runtimeType.toString() == '_RenderTheater';
  }
  return true;
}

String _r(Rect r) =>
    '(${r.left.toStringAsFixed(1)}, ${r.top.toStringAsFixed(1)}, ${r.right.toStringAsFixed(1)}, '
    '${r.bottom.toStringAsFixed(1)})';

/// The nearest scroll view around [r] (null for fixed chrome such as the tab bar).
RenderObject? _vista(RenderObject r) {
  for (RenderObject? a = r.parent; a != null; a = a.parent) {
    if (a is RenderAbstractViewport) return a;
  }
  return null;
}

/// Whether [a] and [b] can be drawn over each other on purpose: different overlay entries, or one scrolls under
/// the other (list content passing beneath the floating tab bar or a celebration).
bool _capasDistintas(RenderObject a, RenderObject b) => _otraCapa(a, b) || !identical(_vista(a), _vista(b));

bool _seMontan(Rect a, Rect b, {double minimo = 2}) {
  final i = a.intersect(b);
  return i.width > minimo && i.height > math.max(minimo, 0.25 * math.min(a.height, b.height));
}

/// Tappable areas of buttons (a tap handler and a text or icon of their own), in global coordinates cut to what
/// can be seen. Bare tappable surfaces such as a banner under its own buttons are not buttons.
List<(RenderBox, Rect)> _botones(WidgetTester tester) {
  final textos = _visibles(tester).toList();
  final pantalla = tester.view.physicalSize / tester.view.devicePixelRatio;
  final out = <(RenderBox, Rect)>[];
  for (final e in tester.allElements) {
    final w = e.widget;
    final toca = switch (w) {
      GestureDetector(:final onTap, :final onLongPress) => onTap != null || onLongPress != null,
      _ => w.runtimeType.toString() == 'InkWell' || w.runtimeType.toString() == 'InkResponse',
    };
    if (!toca) continue;
    final r = e.renderObject;
    if (r is! RenderBox || !r.attached || !r.hasSize || r.size.isEmpty || _oculto(r)) continue;
    final rect = MatrixUtils.transformRect(
      r.getTransformTo(null),
      Offset.zero & r.size,
    ).intersect(_zonaVisible(r));
    if (rect.width <= 0 || rect.height <= 0) continue;
    if (rect.width * rect.height > 0.25 * pantalla.width * pantalla.height) continue;
    if (!textos.any((p) => _desciende(p, r))) continue;
    out.add((r, rect));
  }
  return out;
}

/// Text drawn over another text, or over a button it does not belong to.
List<String> encimados(WidgetTester tester) {
  final lineas = <(RenderParagraph, Rect)>[
    for (final r in _visibles(tester))
      for (final p in _lineasVisibles(r)) (r, p),
  ];
  final out = <String>{};
  for (var i = 0; i < lineas.length; i++) {
    final (ra, a) = lineas[i];
    for (var j = i + 1; j < lineas.length; j++) {
      final (rb, b) = lineas[j];
      if (identical(ra, rb) || _desciende(ra, rb) || _desciende(rb, ra) || _capasDistintas(ra, rb)) continue;
      if (_seMontan(a, b)) {
        out.add(
          'encimados "${ra.text.toPlainText().replaceAll('\n', ' ')}" y "${rb.text.toPlainText().replaceAll('\n', ' ')}" '
          '${_r(a)} ${_r(b)} [${_origen(ra)}] [${_origen(rb)}]',
        );
      }
    }
  }
  final botones = _botones(tester);
  for (final (r, linea) in lineas) {
    for (final (boton, zona) in botones) {
      if (_desciende(r, boton) || _desciende(boton, r) || _capasDistintas(r, boton)) continue;
      if (_seMontan(linea, zona)) {
        final propio = [
          for (final p in _visibles(tester))
            if (_desciende(p, boton)) p.text.toPlainText().replaceAll('\n', ' '),
        ].join(' / ');
        out.add(
          'sobre boton "${r.text.toPlainText().replaceAll('\n', ' ')}" encima de [$propio]: texto ${_r(linea)}, '
          'boton ${_r(zona)} [${_origen(r)}]',
        );
      }
    }
  }
  return out.toList();
}

/// Labels of one [FitTextGroup] drawn at different sizes (more than [tolerancia] apart), with the system text
/// enlarged (at normal size each label keeps its own size, as before groups existed).
List<String> gruposDesparejos(WidgetTester tester, {double tolerancia = 0.01}) {
  final grupos = <Element, List<(String, double)>>{};
  for (final r in _visibles(tester)) {
    final c = r.debugCreator;
    if (c is! DebugCreator) continue;
    var enFit = false;
    Element? grupo;
    c.element.visitAncestorElements((e) {
      final w = e.widget.runtimeType.toString();
      if (w == 'FitText') enFit = true;
      if (w == 'FitTextGroup') {
        grupo = e;
        return false;
      }
      return true;
    });
    final tam = r.text.style?.fontSize;
    if (!enFit || grupo == null || tam == null || r.textScaler.scale(10) <= 10) continue;
    final escala = MatrixUtils.transformRect(r.getTransformTo(null), const Rect.fromLTWH(0, 0, 1, 1)).height;
    grupos.putIfAbsent(grupo!, () => []).add((r.text.toPlainText(), r.textScaler.scale(tam) * escala));
  }
  return [
    for (final g in grupos.values)
      if (g.length > 1 &&
          g.map((x) => x.$2).reduce(math.max) > (1 + tolerancia) * g.map((x) => x.$2).reduce(math.min))
        'grupo desparejo: ${g.map((x) => '"${x.$1}" ${x.$2.toStringAsFixed(2)}').join(', ')}',
  ];
}

final _letraOCifra = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// A text right under a row of three or more short, spread-out labels no bigger than it (axis letters, dates) with
/// less than [minimo] dp between them: a note needs its own spacing, not the row's.
List<String> notasPegadas(WidgetTester tester, {double minimo = 8}) {
  final lineas = <(RenderParagraph, Rect)>[
    for (final r in _visibles(tester))
      for (final p in _lineasVisibles(r)) (r, p),
  ];
  bool mismaLinea(Rect a, Rect b) =>
      math.min(a.bottom, b.bottom) - math.max(a.top, b.top) >= 0.5 * math.min(a.height, b.height);
  bool mismoLugar(Rect a, Rect b) => (a.left - b.left).abs() < 1 && (a.right - b.right).abs() < 1;
  final out = <String>{};
  for (final (ra, a) in lineas) {
    final fila = [
      for (final (rb, b) in lineas)
        if (identical(ra, rb) || (mismaLinea(a, b) && _ladoALado(ra, rb) && !_capasDistintas(ra, rb)))
          (rb, b),
    ];
    final palabras = [
      for (final (r, _) in fila)
        if (_letraOCifra.hasMatch(r.text.toPlainText())) r.text.toPlainText().trim(),
    ];
    if (palabras.any((w) => w.length > 5)) continue;
    final orden = <Rect>[];
    for (final r in [
      for (final (r, l) in fila)
        if (_letraOCifra.hasMatch(r.text.toPlainText())) l,
    ]..sort((x, y) => x.left.compareTo(y.left))) {
      if (orden.isEmpty || !mismoLugar(orden.last, r)) orden.add(r);
    }
    if (orden.length < 3) continue;
    var separados = true;
    for (var k = 1; k < orden.length; k++) {
      if (orden[k].left - orden[k - 1].right < 4) separados = false;
    }
    if (!separados) continue;
    final abajo = fila.map((x) => x.$2.bottom).reduce(math.max);
    final izq = fila.map((x) => x.$2.left).reduce(math.min),
        der = fila.map((x) => x.$2.right).reduce(math.max);
    for (final (rn, n) in lineas) {
      if (fila.any((x) => identical(x.$1, rn)) || _capasDistintas(ra, rn)) continue;
      if (n.right <= izq || n.left >= der || orden.any((r) => r.height > 1.25 * n.height)) continue;
      final hueco = n.top - abajo;
      if (hueco < -0.5 || hueco >= minimo) continue;
      if (lineas.any(
        (x) => !identical(x.$1, rn) && mismaLinea(x.$2, n) && !mismoLugar(x.$2, n) && _ladoALado(x.$1, rn),
      )) {
        continue;
      }
      if (_lineasVisibles(rn).any((l) => l.top < n.top - 0.5)) continue;
      out.add(
        'nota pegada "${rn.text.toPlainText().replaceAll('\n', ' ')}" a ${hueco.toStringAsFixed(1)} dp de la fila de '
        '"${ra.text.toPlainText()}" [${_origen(rn)}]',
      );
    }
  }
  return out.toList();
}

/// Rounded, filled backgrounds around a single short text (chips, pills) drawn next to each other with less than
/// [minimo] dp between them (layered copies of one chip overlap by far more and are not flagged).
List<String> chipsPegados(WidgetTester tester, {double minimo = 4}) {
  final textos = _visibles(tester).toList();
  final chips = <(RenderDecoratedBox, Rect, String)>[];
  for (final r in tester.allRenderObjects.whereType<RenderDecoratedBox>()) {
    if (!r.attached || !r.hasSize || r.size.isEmpty || _oculto(r)) continue;
    final d = r.decoration;
    if (d is! BoxDecoration || d.color == null || d.color!.a == 0 || d.borderRadius == null) continue;
    final dentro = {
      for (final p in textos)
        if (_desciende(p, r)) p.text.toPlainText(),
    };
    if (dentro.length != 1 || r.size.height > 72) continue;
    final rect = MatrixUtils.transformRect(
      r.getTransformTo(null),
      Offset.zero & r.size,
    ).intersect(_zonaVisible(r));
    if (rect.width <= 0 || rect.height <= 0) continue;
    chips.add((r, rect, dentro.single));
  }
  final out = <String>{};
  for (var i = 0; i < chips.length; i++) {
    for (var j = i + 1; j < chips.length; j++) {
      final (ca, a, ta) = chips[i];
      final (cb, b, tb) = chips[j];
      if (_desciende(ca, cb) || _desciende(cb, ca) || !_ladoALado(ca, cb) || _capasDistintas(ca, cb))
        continue;
      final solape = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
      if (solape < 0.5 * math.min(a.height, b.height)) continue;
      final hueco = math.max(b.left - a.right, a.left - b.right);
      if (hueco > -1 && hueco < minimo) {
        out.add('chips pegados "$ta" y "$tb": separacion ${hueco.toStringAsFixed(1)} [${_origen(ca)}]');
      }
    }
  }
  return out.toList();
}

/// Everything the large-text checks flag: clipped, split, shortened, touching and overlapping text, notes pressed
/// under a row of labels, touching chips, and labels of one group drawn at different sizes.
List<String> problemasDeTexto(WidgetTester tester, String idioma) => [
  ...textoCortado(tester),
  ...palabrasPartidas(tester),
  ...rotulosAcortados(tester, idioma),
  ...rotulosPegados(tester, idioma),
  ...encimados(tester),
  ...notasPegadas(tester),
  ...chipsPegados(tester),
  ...gruposDesparejos(tester),
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

/// Texts inside [zonas] that lose lines to `maxLines` without an ellipsis.
List<String> lineasExcedidas(WidgetTester tester, Iterable<Finder> zonas) => [
  for (final zona in zonas)
    for (final texto in find.descendant(of: zona, matching: find.byType(RichText)).evaluate())
      if ((texto.renderObject as RenderParagraph).didExceedMaxLines)
        'cortado por maxLines: "${(texto.renderObject as RenderParagraph).text.toPlainText()}"',
];
