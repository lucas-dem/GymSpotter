import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// The style [Text] really draws with: the inherited style, [style], and bold when the system asks for bold text.
TextStyle effectiveTextStyle(BuildContext context, TextStyle? style) {
  final s = DefaultTextStyle.of(context).style.merge(style);
  return MediaQuery.boldTextOf(context) ? s.merge(const TextStyle(fontWeight: FontWeight.bold)) : s;
}

/// Labels on the same level: every [FitText] inside shrinks by one factor, the one of the label with the least
/// room, so neighbours never end up at different sizes.
class FitTextGroup extends StatefulWidget {
  const FitTextGroup({super.key, required this.child});

  final Widget child;

  @override
  State<FitTextGroup> createState() => _FitTextGroupState();
}

class _FitTextGroupState extends State<FitTextGroup> {
  final _grupo = _Grupo();

  @override
  void dispose() {
    _grupo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _GrupoScope(grupo: _grupo, child: widget.child);
}

class _GrupoScope extends InheritedWidget {
  const _GrupoScope({required this.grupo, required super.child});

  final _Grupo grupo;

  @override
  bool updateShouldNotify(_GrupoScope old) => !identical(grupo, old.grupo);
}

/// Collects each member's own factor and, after the frame, publishes the smallest one.
class _Grupo extends ChangeNotifier {
  final _factores = <Object, double>{};
  double factor = 1;
  bool _pendiente = false, _cerrado = false;

  void informar(Object quien, double f) {
    if (_factores[quien] == f) return;
    _factores[quien] = f;
    _programar();
  }

  void quitar(Object quien) {
    if (_factores.remove(quien) != null) _programar();
  }

  void _programar() {
    if (_pendiente || _cerrado) return;
    _pendiente = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pendiente = false;
      if (_cerrado) return;
      final f = _factores.values.fold(1.0, math.min);
      if (f != factor) {
        factor = f;
        notifyListeners();
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _cerrado = true;
    super.dispose();
  }
}

/// A label that never splits a word or ends in "…": it wraps at spaces up to [maxLines] lines and, when a word
/// or the lines still do not fit, shrinks as a whole like a scale-down [FittedBox]. Inside a [FitTextGroup] it
/// shrinks by the group's factor.
class FitText extends StatelessWidget {
  const FitText(this.text, {super.key, this.style, this.maxLines = 2, this.textAlign = TextAlign.start});

  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final grupo = context.dependOnInheritedWidgetOfExactType<_GrupoScope>()?.grupo;
    if (grupo != null) {
      return _Achique(
        grupo: grupo,
        comparte: MediaQuery.textScalerOf(context).scale(10) > 10,
        medir: (disponible) => _anchoNecesario(context, disponible),
        alineacion: _alineacion.resolve(Directionality.of(context)),
        child: Text(text, style: style, maxLines: maxLines, textAlign: textAlign),
      );
    }
    return _solo();
  }

  Widget _solo() => LayoutBuilder(
    builder: (context, c) {
      final texto = Text(text, style: style, maxLines: maxLines, textAlign: textAlign);
      if (!c.hasBoundedWidth) return texto;
      final ancho = _anchoNecesario(context, c.maxWidth);
      if (ancho <= c.maxWidth) return texto;
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: _alineacion,
        child: SizedBox(width: ancho, child: texto),
      );
    },
  );

  /// The narrowest width at least [disponible] where no word breaks and the text takes at most [maxLines] lines.
  double _anchoNecesario(BuildContext context, double disponible) {
    final estilo = effectiveTextStyle(context, style);
    final p = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    );
    p.text = TextSpan(text: text, style: estilo);
    p.layout();
    final palabra = p.minIntrinsicWidth, natural = p.maxIntrinsicWidth;

    int lineas(double ancho) {
      p.text = TextSpan(text: text, style: estilo);
      p.layout(maxWidth: ancho);
      return p.computeLineMetrics().length;
    }

    var ancho = math.max(disponible, palabra + 0.5);
    if (lineas(ancho) > maxLines) {
      var bajo = ancho, alto = natural + 0.5;
      while (alto - bajo > 0.5) {
        final medio = (bajo + alto) / 2;
        if (lineas(medio) <= maxLines) {
          alto = medio;
        } else {
          bajo = medio;
        }
      }
      ancho = alto;
    }
    p.dispose();
    return ancho;
  }

  AlignmentGeometry get _alineacion => switch (textAlign) {
    TextAlign.center => Alignment.center,
    TextAlign.right => Alignment.centerRight,
    TextAlign.left => Alignment.centerLeft,
    TextAlign.end => AlignmentDirectional.centerEnd,
    _ => AlignmentDirectional.centerStart,
  };
}

/// Lays a group member out at the width [medir] gives for the room it has, and draws it scaled by the smaller of
/// its own factor and the group's.
class _Achique extends SingleChildRenderObjectWidget {
  const _Achique({
    required this.grupo,
    required this.comparte,
    required this.medir,
    required this.alineacion,
    required super.child,
  });

  final _Grupo grupo;

  /// Whether the group's factor applies: only with the system text enlarged, so normal size looks as before.
  final bool comparte;
  final double Function(double disponible) medir;
  final Alignment alineacion;

  @override
  _RenderAchique createRenderObject(BuildContext context) =>
      _RenderAchique(grupo, comparte, medir, alineacion);

  @override
  void updateRenderObject(BuildContext context, _RenderAchique render) {
    render
      ..grupo = grupo
      ..comparte = comparte
      ..medir = medir
      ..alineacion = alineacion;
  }
}

class _RenderAchique extends RenderProxyBox {
  _RenderAchique(this._grupo, this._comparte, this._medir, this._alineacion);

  _Grupo _grupo;
  bool _comparte;
  double Function(double) _medir;
  Alignment _alineacion;
  double _escala = 1;
  Offset _corrimiento = Offset.zero;

  set grupo(_Grupo g) {
    if (identical(g, _grupo)) return;
    if (attached) {
      _grupo
        ..removeListener(markNeedsLayout)
        ..quitar(this);
      g.addListener(markNeedsLayout);
    }
    _grupo = g;
    markNeedsLayout();
  }

  set comparte(bool c) {
    if (c == _comparte) return;
    _comparte = c;
    markNeedsLayout();
  }

  set medir(double Function(double) m) {
    _medir = m;
    markNeedsLayout();
  }

  set alineacion(Alignment a) {
    if (a == _alineacion) return;
    _alineacion = a;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _grupo.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _grupo
      ..removeListener(markNeedsLayout)
      ..quitar(this);
    super.detach();
  }

  double _ancho(double disponible) => disponible.isFinite ? _medir(disponible) : double.infinity;

  /// The member's own factor, like a scale-down FittedBox around the text as laid out ([dibujado] wide).
  double _propia(double disponible, double dibujado) =>
      dibujado > disponible && dibujado > 0 ? math.max(0, disponible) / dibujado : 1;

  double get _factorGrupo => _comparte ? _grupo.factor : 1;

  @override
  double computeMinIntrinsicHeight(double width) => _altoIntrinseco(width, child?.getMinIntrinsicHeight);

  @override
  double computeMaxIntrinsicHeight(double width) => _altoIntrinseco(width, child?.getMaxIntrinsicHeight);

  double _altoIntrinseco(double width, double Function(double)? hijo) {
    if (hijo == null) return 0;
    final ancho = _ancho(width);
    final alto = hijo(ancho);
    if (!_comparte || !ancho.isFinite) return alto;
    final dibujado = child!.getMaxIntrinsicWidth(double.infinity);
    return alto * math.min(_propia(width, math.min(ancho, dibujado)), _factorGrupo);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final c = child;
    if (c == null) return constraints.smallest;
    final ancho = _ancho(constraints.maxWidth);
    final s = c.getDryLayout(BoxConstraints(maxWidth: ancho));
    final escala = ancho.isFinite ? math.min(_propia(constraints.maxWidth, s.width), _factorGrupo) : 1.0;
    return constraints.constrain(s * escala);
  }

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    final ancho = _ancho(constraints.maxWidth);
    c.layout(BoxConstraints(maxWidth: ancho), parentUsesSize: true);
    var escala = 1.0;
    final propia = ancho.isFinite ? _propia(constraints.maxWidth, c.size.width) : 1.0;
    if (ancho.isFinite && _comparte && constraints.maxWidth > 0) {
      _grupo.informar(this, propia);
      escala = math.min(propia, _grupo.factor);
    } else {
      _grupo.quitar(this);
      escala = propia;
    }
    _escala = escala;
    size = constraints.constrain(c.size * escala);
    _corrimiento = _alineacion.alongOffset(size - c.size * escala as Offset);
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final b = child?.getDistanceToActualBaseline(baseline);
    return b == null ? null : b * _escala + _corrimiento.dy;
  }

  Matrix4 get _matriz =>
      Matrix4.translationValues(_corrimiento.dx, _corrimiento.dy, 0)..scaleByDouble(_escala, _escala, 1, 1);

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c == null) return;
    if (_escala == 1) {
      layer = null;
      context.paintChild(c, offset + _corrimiento);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _matriz,
      (ctx, o) => ctx.paintChild(c, o),
      oldLayer: layer is TransformLayer ? layer as TransformLayer : null,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null) return false;
    return result.addWithPaintTransform(
      transform: _matriz,
      position: position,
      hitTest: (r, p) => c.hitTest(r, position: p),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) => transform.multiply(_matriz);
}
