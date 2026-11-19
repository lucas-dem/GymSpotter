import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The style [Text] really draws with: the inherited style, [style], and bold when the system asks for bold text.
TextStyle effectiveTextStyle(BuildContext context, TextStyle? style) {
  final s = DefaultTextStyle.of(context).style.merge(style);
  return MediaQuery.boldTextOf(context) ? s.merge(const TextStyle(fontWeight: FontWeight.bold)) : s;
}

/// A label that never splits a word or ends in "…": it wraps at spaces up to [maxLines] lines and, when a word
/// or the lines still do not fit, shrinks as a whole like a scale-down [FittedBox].
class FitText extends StatelessWidget {
  const FitText(this.text, {super.key, this.style, this.maxLines = 2, this.textAlign = TextAlign.start});

  final String text;
  final TextStyle? style;
  final int maxLines;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
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
