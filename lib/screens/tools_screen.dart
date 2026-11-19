import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../catalog/exercise_catalog.dart';
import '../l10n/l10n.dart';
import '../models/exercise.dart';
import '../state/fit_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/fit_text.dart';
import '../widgets/ui_kit.dart';

IconData _toolIcon(String id) => switch (id) {
      'rm' => PhosphorIconsRegular.barbell,
      'bmi' => PhosphorIconsRegular.scales,
      'cal' => PhosphorIconsRegular.fire,
      'bf' => PhosphorIconsRegular.percent,
      'plate' => PhosphorIconsRegular.circlesThree,
      _ => PhosphorIconsRegular.trendUp,
    };

class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        clipBehavior: Clip.none,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenHeader(
              title: t.tools,
              onBack: fit.backFromTools,
              titleSize: 22,
              subtitle: t.calculatorsCount(kToolMeta.length),
            ),
            const SizedBox(height: 22),
            LayoutBuilder(builder: (context, box) {
              final inner = (box.maxWidth - 12) / 2 - 32;
              int most(String Function(ToolMeta) text, TextStyle style) =>
                  kToolMeta.map((m) => _lines(context, text(m), style, inner)).fold(0, math.max);
              final nameLines = most((m) => t.toolName(m.id), _nameStyle(gc)).clamp(1, 2);
              final descLines = most((m) => t.toolDesc(m.id), _descStyle(gc)).clamp(2, 4);
              return GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent:
                      math.max((box.maxWidth - 12) / 2 / 1.12, _cardContent(context, nameLines, descLines)),
                ),
                children: [for (final tool in kToolMeta) _card(context, gc, tool, nameLines, descLines)],
              );
            }),
          ],
        ),
      ),
    );
  }

  TextStyle _nameStyle(GymColors gc) => AppTheme.f(14.5, weight: FontWeight.w700, color: gc.text);

  TextStyle _descStyle(GymColors gc) =>
      AppTheme.f(11.5, weight: FontWeight.w500, color: gc.textSecondary, height: 1.3);

  /// Lines [text] takes at [width] when, as in [FitText], a word wider than [width] shrinks instead of breaking.
  int _lines(BuildContext context, String text, TextStyle style, double width) {
    final p = TextPainter(textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context));
    p.text = TextSpan(text: text, style: effectiveTextStyle(context, style));
    p.layout();
    final widest = math.max(width, p.minIntrinsicWidth);
    p.layout(maxWidth: widest > width ? widest + 0.5 : width);
    final n = p.computeLineMetrics().length;
    p.dispose();
    return n;
  }

  double _descHeight(BuildContext context, int lines) =>
      (MediaQuery.textScalerOf(context).scale(11.5) * 1.3 * lines + 1).ceilToDouble();

  double _cardContent(BuildContext context, int nameLines, int descLines) =>
      (32 + 36 + 10 + MediaQuery.textScalerOf(context).scale(14.5) * 1.15 * nameLines + 2 +
              _descHeight(context, descLines))
          .ceilToDouble();

  Widget _card(BuildContext context, GymColors gc, ToolMeta tool, int nameLines, int descLines) {
    final name = t.toolName(tool.id);
    return GestureDetector(
      onTap: () => fit.openTool(tool.id),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: gc.bgRaised,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration:
                  BoxDecoration(color: gc.bgRaised2, borderRadius: BorderRadius.circular(12)),
              child: Center(child: Icon(_toolIcon(tool.id), size: 19, color: gc.textSecondary)),
            ),
            const Spacer(),
            if (nameLines == 1)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(name, maxLines: 1, style: _nameStyle(gc)),
              )
            else
              FitText(name, style: _nameStyle(gc)),
            const SizedBox(height: 2),
            SizedBox(
              height: _descHeight(context, descLines),
              child: FitText(t.toolDesc(tool.id), maxLines: descLines, style: _descStyle(gc)),
            ),
          ],
        ),
      ),
    );
  }
}
