import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../l10n/l10n.dart';
import '../models/workout.dart';
import '../state/fit_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'fit_text.dart';
import 'ui_kit.dart';

const kFolderHues = [
  Color(0xFFF3C7B1),
  Color(0xFFA78BDA),
  Color(0xFFA8C99E),
  Color(0xFF9CC2E8),
  Color(0xFFE8CF98),
  Color(0xFFE6A4B9),
];

Color folderHue(Routine r) =>
    kFolderHues[(r.color >= 0 ? r.color : r.id.codeUnits.fold<int>(0, (a, c) => a + c)) % kFolderHues.length];

class RoutineFolder extends StatelessWidget {
  const RoutineFolder({super.key, required this.routine, required this.onMenu});

  final Routine routine;
  final VoidCallback onMenu;

  static const _tab = 16.0;
  static const _menu = 30.0;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    final r = routine;
    final n = r.exerciseIds.length;
    final hue = folderHue(r);
    final dark = gc.bg.computeLuminance() < 0.5;
    final back = Color.lerp(hue, Colors.black, dark ? 0.42 : 0.18)!;
    final front = Color.lerp(gc.bgRaised2, hue, dark ? 0.14 : 0.3)!;
    final ink = Color.lerp(hue, Colors.black, 0.35)!;
    final count = [if (r.group.isNotEmpty) r.group, t.exerciseCount(n)].join(' · ');
    final countStyle = AppTheme.f(11.5, weight: FontWeight.w600, color: gc.textSecondary);

    return Pressable(
      onTap: () => fit.openRoutine(r.id),
      scale: 0.975,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: 74,
            height: _tab + 24,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: gc.bgRaised,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
            ),
          ),
          Positioned.fill(
            top: _tab,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: gc.bgRaised,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(22),
                  bottomRight: Radius.circular(22),
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: _tab + 8,
            height: 64,
            child: Transform.rotate(
              angle: -0.018,
              child: DecoratedBox(
                decoration: BoxDecoration(color: back, borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            top: _tab + 16,
            height: 64,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 40, 0),
              decoration: BoxDecoration(color: hue, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _line(ink.withValues(alpha: 0.45), 1),
                  const SizedBox(height: 5),
                  _line(ink.withValues(alpha: 0.2), 0.55),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: _tab + 50),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
                  constraints: const BoxConstraints(minHeight: 84),
                  decoration: BoxDecoration(
                    color: front,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: dark ? 0.35 : 0.1),
                        blurRadius: 14,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 84 - 22),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _title(gc, r)),
                            Semantics(
                              button: true,
                              label: t.moreOptions,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: onMenu,
                                child: Container(
                                  width: _menu,
                                  height: _menu,
                                  decoration: BoxDecoration(
                                    color: gc.text.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(PhosphorIconsBold.dotsThreeVertical, size: 16, color: gc.text),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (r.group.isEmpty)
                          _count(countStyle, FitText(count, style: countStyle))
                        else if (_enlarged(context)) ...[
                          Text(r.group, maxLines: 1, overflow: TextOverflow.ellipsis, style: countStyle),
                          _count(countStyle, FitText(t.exerciseCount(n), style: countStyle)),
                        ] else
                          Text(count, maxLines: 1, overflow: TextOverflow.ellipsis, style: countStyle),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: n > 0 ? () => fit.startRoutine(r) : () => fit.openRoutine(r.id),
                  child: _startRoom(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          n > 0 ? PhosphorIconsFill.play : PhosphorIconsBold.plus,
                          size: 12,
                          color: gc.textSecondary,
                        ),
                        const SizedBox(width: 7),
                        Flexible(
                          child: FitText(
                            n > 0 ? titleCase(t.startWorkout) : t.addExercises,
                            textAlign: TextAlign.center,
                            style: _startStyle(gc),
                          ),
                        ),
                      ],
                    ),
                    gc,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static TextStyle _titleStyle(GymColors gc) =>
      AppTheme.f(16, weight: FontWeight.w800, color: gc.text, height: 1.15);

  /// The routine name in up to two lines (their room is always kept, so cards side by side match); when its
  /// longest word is wider than the room, it shrinks as a whole instead of breaking the word.
  Widget _title(GymColors gc, Routine r) => LayoutBuilder(
    builder: (context, c) {
      final title = Text.rich(
        TextSpan(
          children: [
            TextSpan(text: fit.routineTitle(r)),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(PhosphorIconsBold.caretRight, size: 13, color: gc.textSecondary),
              ),
            ),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: _titleStyle(gc),
      );
      if (!c.hasBoundedWidth) return title;
      final p = TextPainter(
        text: TextSpan(text: fit.routineTitle(r), style: effectiveTextStyle(context, _titleStyle(gc))),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
      )..layout();
      final palabra = p.minIntrinsicWidth;
      p.text = TextSpan(text: 'A\nA', style: effectiveTextStyle(context, _titleStyle(gc)));
      p.layout();
      final dosLineas = p.height;
      p.dispose();
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: dosLineas),
        child: palabra <= c.maxWidth || !_enlarged(context)
            ? title
            : FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.topStart,
                child: SizedBox(width: math.max(c.maxWidth, palabra + 0.5), child: title),
              ),
      );
    },
  );

  static bool _enlarged(BuildContext context) => MediaQuery.textScalerOf(context).scale(10) > 10;

  static TextStyle _startStyle(GymColors gc) =>
      AppTheme.f(13.5, weight: FontWeight.w700, color: gc.textSecondary);

  /// The start strip: 46 dp, or with large text the room of the taller of its two labels ("Empezar" and "Añadir
  /// ejercicios"), so a new empty routine is as tall as the full one beside it.
  Widget _startRoom(Widget row, GymColors gc) => LayoutBuilder(
    builder: (context, c) {
      var alto = 46.0;
      if (c.hasBoundedWidth && _enlarged(context)) {
        for (final label in [titleCase(t.startWorkout), t.addExercises]) {
          final p = TextPainter(
            text: TextSpan(text: label, style: effectiveTextStyle(context, _startStyle(gc))),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            locale: Localizations.maybeLocaleOf(context),
            maxLines: 2,
          )..layout(maxWidth: math.max(0, c.maxWidth - 16 - 12 - 7));
          alto = math.max(alto, p.height + 8);
          p.dispose();
        }
      }
      return Container(
        constraints: BoxConstraints(minHeight: alto),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        child: row,
      );
    },
  );

  /// The exercise count at the bottom, with the room a two-digit count needs at this width, so cards side by side
  /// keep one height when the label wraps in one of them only.
  Widget _count(TextStyle style, Widget child) => LayoutBuilder(
    builder: (context, c) {
      if (!c.hasBoundedWidth) return child;
      final p = TextPainter(
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 2,
      );
      var alto = 0.0;
      for (final k in const [1, 88, 888]) {
        p.text = TextSpan(text: t.exerciseCount(k), style: effectiveTextStyle(context, style));
        p.layout(maxWidth: c.maxWidth);
        alto = math.max(alto, p.height);
      }
      p.dispose();
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: alto),
        child: Align(alignment: AlignmentDirectional.bottomStart, child: child),
      );
    },
  );

  Widget _line(Color c, double width) => FractionallySizedBox(
    alignment: Alignment.centerLeft,
    widthFactor: width,
    child: Container(
      height: 2.5,
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
    ),
  );
}
