import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/l10n.dart';
import '../state/energy.dart';
import '../state/fit_state.dart';
import '../state/steps_range.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'entrance.dart';
import 'fit_text.dart';
import 'steps_card.dart';

String _count(int n) => NumberFormat.decimalPattern(intlLocale).format(n);

/// The step and calorie blocks of Progress only exist for people who use the feature or already have steps saved.
bool showStepsProgress() => fit.stepsOn || fit.steps.isNotEmpty;

StepsPeriod _period(StepsSpan span) => stepsPeriod(
  span: span,
  today: DateTime.now(),
  steps: fit.steps,
  stepsFrom: fit.stepsFrom,
  goal: fit.stepGoal,
  sessions: fit.sessions,
  bodyweight: fit.bodyweight,
  profileWeightKg: fit.profile.weightKg,
);

String _spanLabel(StepsSpan span) => switch (span) {
  StepsSpan.week => t.days7,
  StepsSpan.month => t.days30,
  StepsSpan.year => t.months12,
};

class _Frame extends StatelessWidget {
  const _Frame({required this.title, required this.span, required this.onSpan, required this.children});

  final String title;
  final StepsSpan span;
  final ValueChanged<StepsSpan> onSpan;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(color: gc.bgRaised, borderRadius: BorderRadius.circular(22)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 2,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title.toUpperCase(),
                    style: AppTheme.f(
                      10,
                      weight: FontWeight.w600,
                      color: gc.textTertiary,
                      letterSpacing: 0.9,
                    ),
                  ),
                ),
                _SpanToggle(span: span, onSpan: onSpan),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

class _SpanToggle extends StatelessWidget {
  const _SpanToggle({required this.span, required this.onSpan});

  final StepsSpan span;
  final ValueChanged<StepsSpan> onSpan;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return Semantics(
      container: true,
      label: t.stepsRangeLabel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in StepsSpan.values)
            Semantics(
              button: true,
              selected: s == span,
              label: _spanLabel(s),
              onTap: () => onSpan(s),
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSpan(s),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: s == span ? gc.ember : gc.bgRaised2,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        _spanLabel(s),
                        style: AppTheme.f(
                          11,
                          weight: FontWeight.w600,
                          color: s == span ? gc.onEmber : gc.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Widget _value(GymColors gc, String value, String unit) => FittedBox(
  fit: BoxFit.scaleDown,
  alignment: AlignmentDirectional.centerStart,
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      RollIn(
        value,
        style: AppTheme.f(28, weight: FontWeight.w800, color: gc.text),
      ),
      if (unit.isNotEmpty) ...[
        const SizedBox(width: 5),
        Text(
          unit,
          style: AppTheme.f(13, weight: FontWeight.w500, color: gc.textSecondary),
        ),
      ],
    ],
  ),
);

Widget _note(GymColors gc, String text) => Padding(
  padding: const EdgeInsets.only(top: 4),
  child: Text(
    text,
    style: AppTheme.f(11.5, weight: FontWeight.w500, color: gc.textTertiary),
  ),
);

class StepsProgressCard extends StatefulWidget {
  const StepsProgressCard({super.key});

  @override
  State<StepsProgressCard> createState() => _StepsProgressCardState();
}

class _StepsProgressCardState extends State<StepsProgressCard> {
  StepsSpan _span = StepsSpan.week;

  @override
  void initState() {
    super.initState();
    if (fit.takeFocusSteps()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: 0.05,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: fit,
    builder: (context, _) {
      if (!showStepsProgress()) return const SizedBox.shrink();
      final gc = context.gc;
      final p = _period(_span);
      final avg = p.average;
      final gaps = p.bars.any((b) => b.value == null);
      return _Frame(
        title: t.stepsTitle,
        span: _span,
        onSpan: (s) => setState(() => _span = s),
        children: [
          _value(gc, avg == null ? '–' : _count(avg), avg == null ? '' : t.stepsAvgUnit),
          _note(
            gc,
            avg == null
                ? t.stepsPeriodEmpty
                : t.stepsGoalDays(_count(fit.stepGoal), p.goalDays, p.daysWithData),
          ),
          const SizedBox(height: 12),
          ExcludeSemantics(
            child: StepsBarChart(period: p, span: _span, goal: fit.stepGoal),
          ),
          if (gaps || p.hasPartial)
            _note(gc, [if (gaps) t.stepsLegendGaps, if (p.hasPartial) t.stepsLegendPartial].join(' ')),
        ],
      );
    },
  );
}

class KcalProgressCard extends StatefulWidget {
  const KcalProgressCard({super.key});

  @override
  State<KcalProgressCard> createState() => _KcalProgressCardState();
}

class _KcalProgressCardState extends State<KcalProgressCard> {
  StepsSpan _span = StepsSpan.week;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: fit,
    builder: (context, _) {
      if (!showStepsProgress()) return const SizedBox.shrink();
      final gc = context.gc;
      final p = _period(_span);
      final kg = weightForDay(DateTime.now(), fit.bodyweight, fit.profile.weightKg);
      final weightNote = t.kcalWeightPerDay(fit.weightLabel(kg));

      Widget row(String label, int kcal) => MergeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 2,
              children: [
                Text(
                  label,
                  style: AppTheme.f(13, weight: FontWeight.w600, color: gc.textSecondary),
                ),
                Text(
                  '≈ ${_count(kcal)} kcal',
                  style: AppTheme.f(13, weight: FontWeight.w700, color: gc.text),
                ),
              ],
            ),
          ),
        ),
      );

      return _Frame(
        title: t.kcalTitle,
        span: _span,
        onSpan: (s) => setState(() => _span = s),
        children: [
          _value(gc, '≈ ${_count(p.totalKcal)}', 'kcal'),
          row(t.stepsByWalking, p.stepsKcal),
          row(t.kcalByWorkouts, p.workoutKcal),
          Semantics(
            button: true,
            label: weightNote,
            hint: t.stepsShowEstimate,
            onTap: () => showStepsHelp(context),
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showStepsHelp(context),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    weightNote,
                    style: AppTheme.f(11.5, weight: FontWeight.w500, color: gc.textTertiary),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class StepsBarChart extends StatelessWidget {
  const StepsBarChart({
    super.key,
    required this.period,
    required this.span,
    required this.goal,
    this.height = 116,
  });

  final StepsPeriod period;
  final StepsSpan span;
  final int goal;
  final double height;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    final bars = period.bars;
    final top = _top(bars, goal);
    final style = AppTheme.d(10, weight: FontWeight.w600, color: gc.textTertiary);
    final compact = NumberFormat.compact(locale: intlLocale);
    final ticks = [
      for (final f in const [1.0, 0.5, 0.0]) compact.format((top * f).round()),
    ];
    var widest = 0.0;
    for (final tick in ticks) {
      final painter = TextPainter(
        text: TextSpan(text: tick, style: effectiveTextStyle(context, style)),
        textDirection: Directionality.of(context),
        locale: Localizations.maybeLocaleOf(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    final axis = widest.ceilToDouble() + 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: axis,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final tick in ticks) Text(tick, maxLines: 1, style: style)],
                ),
              ),
              const SizedBox(width: 6),
              Expanded(child: CustomPaint(painter: _BarsPainter(gc, bars, top, goal))),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: EdgeInsets.only(left: axis + 6),
          child: _labels(gc, style),
        ),
      ],
    );
  }

  Widget _labels(GymColors gc, TextStyle style) {
    final bars = period.bars;
    switch (span) {
      case StepsSpan.week:
        return Row(
          children: [
            for (final b in bars)
              Expanded(
                child: Center(child: Text(t.weekdayInitial(b.date.weekday), maxLines: 1, style: style)),
              ),
          ],
        );
      case StepsSpan.month:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final i in [0, bars.length ~/ 2, bars.length - 1]) Text('${bars[i].date.day}', style: style),
          ],
        );
      case StepsSpan.year:
        final month = DateFormat.MMM(intlLocale);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final i in [0, bars.length - 1]) Text(month.format(bars[i].date), style: style),
          ],
        );
    }
  }

  static double _top(List<StepsBar> bars, int goal) {
    var top = goal.toDouble();
    for (final b in bars) {
      final v = b.value;
      if (v != null && v > top) top = v;
    }
    return math.max(top, 1);
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.gc, this.bars, this.top, this.goal);

  final GymColors gc;
  final List<StepsBar> bars;
  final double top;
  final int goal;

  static const double _pad = 7;

  @override
  void paint(Canvas canvas, Size size) {
    final yTop = _pad, yBottom = size.height - _pad;
    double y(double v) => yBottom - (yBottom - yTop) * (v / top);
    final grid = Paint()
      ..color = gc.border
      ..strokeWidth = 1;
    for (final f in const [0.0, 0.5, 1.0]) {
      final gy = yBottom - (yBottom - yTop) * f;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }
    if (bars.isEmpty) return;
    final slot = size.width / bars.length;
    final barW = math.max(2.0, slot * 0.62);
    for (var i = 0; i < bars.length; i++) {
      final v = bars[i].value;
      if (v == null) continue;
      final h = math.max(2.0, yBottom - y(v));
      final left = slot * i + (slot - barW) / 2;
      final color = bars[i].partial ? gc.accent.withValues(alpha: 0.38) : gc.accent;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, yBottom - h, barW, h),
          Radius.circular(math.min(3, barW / 2)),
        ),
        Paint()..color = color,
      );
    }
    final gy = y(goal.toDouble());
    canvas.drawLine(
      Offset(0, gy),
      Offset(size.width, gy),
      Paint()
        ..color = gc.ember
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_BarsPainter o) => o.gc != gc || o.bars != bars || o.top != top || o.goal != goal;
}
