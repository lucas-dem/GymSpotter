import 'dart:async';
import 'dart:math' as math;

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../l10n/l10n.dart';
import '../services/step_source.dart';
import '../state/energy.dart';
import '../state/fit_state.dart';
import '../state/steps_card_pref.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'charts.dart';
import 'entrance.dart';
import 'fit_text.dart';
import 'glass.dart';
import 'svg_icon.dart';
import 'ui_kit.dart';

export '../state/steps_card_pref.dart';

String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _count(int n) => NumberFormat.decimalPattern(intlLocale).format(n);

String _clock(int minute) =>
    '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';

class StepsCard extends StatefulWidget {
  const StepsCard({super.key});

  @override
  State<StepsCard> createState() => _StepsCardState();
}

class _StepsCardState extends State<StepsCard> {
  Timer? _midnight;

  @override
  void initState() {
    super.initState();
    StepsCardPref.load();
    _armMidnight();
  }

  @override
  void dispose() {
    _midnight?.cancel();
    super.dispose();
  }

  void _armMidnight() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now) + const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {});
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) unawaited(fit.refreshSteps());
      _armMidnight();
    });
  }

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: fit, builder: (context, _) => _body(context));

  Widget _body(BuildContext context) {
    final status = fit.stepsStatus;
    if (status == StepsStatus.unavailable || status == StepsStatus.unread) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: StepsCardPref.hidden,
      builder: (context, hidden, _) {
        final gc = context.gc;
        Widget wrap(Widget child) => Padding(padding: const EdgeInsets.only(top: 14), child: child);
        switch (status) {
          case StepsStatus.counting:
            return wrap(_counting(context, gc));
          case StepsStatus.denied:
            if (hidden) return const SizedBox.shrink();
            return wrap(_denied(context, gc));
          case StepsStatus.needsPermission:
            return wrap(_enable(context, gc, onHide: _hideAndStop));
          case StepsStatus.off:
            if (hidden || fit.stepsAskedAt != null) return const SizedBox.shrink();
            return wrap(_enable(context, gc, onHide: () => StepsCardPref.setHidden(true)));
          case StepsStatus.unavailable:
          case StepsStatus.unread:
            return const SizedBox.shrink();
        }
      },
    );
  }

  void _hideAndStop() {
    StepsCardPref.setHidden(true);
    fit.disableSteps();
  }

  Widget _denied(BuildContext context, GymColors gc) => _prompt(
    context,
    gc,
    title: t.stepsDeniedTitle,
    body: stepsDeniedText(),
    action: GhostButton(
      label: stepsOpenPermissionLabel(),
      icon: PhosphorIconsRegular.gear,
      onTap: () => unawaited(openStepsPermissionScreen()),
    ),
    onHide: _hideAndStop,
  );

  Widget _enable(BuildContext context, GymColors gc, {required VoidCallback onHide}) => _prompt(
    context,
    gc,
    title: t.stepsEnableTitle,
    body: readsHealthConnect(fit.stepSource) ? t.stepsEnableBodyHc : t.stepsEnableBody,
    action: GhostButton(
      label: t.stepsEnable,
      icon: PhosphorIconsRegular.footprints,
      onTap: () => activateSteps(context),
    ),
    onHide: onHide,
  );

  Widget _prompt(
    BuildContext context,
    GymColors gc, {
    required String title,
    required String body,
    required Widget action,
    VoidCallback? onHide,
  }) {
    // With very large text the body takes the card's full width, so long words are not squeezed beside the icon.
    final ancho = MediaQuery.textScalerOf(context).scale(10) > 15;
    final cuerpo = Text(body, style: AppTheme.f(12, weight: FontWeight.w500, color: gc.textSecondary));
    return SoftCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(14, 16, 2, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(PhosphorIconsBold.footprints, size: 19, color: gc.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTheme.f(14.5, color: gc.text)),
                    if (!ancho) ...[const SizedBox(height: 4), cuerpo],
                  ],
                ),
              ),
              if (onHide != null)
                Semantics(
                  button: true,
                  label: t.stepsHide,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onHide,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(PhosphorIconsBold.x, size: 14, color: gc.textTertiary),
                    ),
                  ),
                )
              else
                const SizedBox(width: 10),
            ],
          ),
          if (ancho) ...[
            const SizedBox(height: 4),
            Padding(padding: const EdgeInsetsDirectional.only(end: 12), child: cuerpo),
          ],
          const SizedBox(height: 14),
          Padding(padding: const EdgeInsetsDirectional.only(end: 12), child: action),
        ],
      ),
    );
  }

  Widget _counting(BuildContext context, GymColors gc) {
    final now = DateTime.now();
    final key = _dayKey(now);
    final steps = fit.steps[key] ?? 0;
    final goal = fit.stepGoal;
    final done = steps >= goal;
    final kcal = _todayKcal(now);
    final from = showStepsFrom() ? fit.stepsFrom[key] : null;
    final note = from != null
        ? t.stepsCountingSince(_clock(from))
        : t.estimatedWithWeight(fit.weightLabel(kcal.weightKg));
    final ring = Semantics(
      button: true,
      label: t.stepGoal,
      hint: t.stepsChangeGoal,
      value: done ? '${t.stepsCount(goal)}, ${t.stepsGoalReached}' : t.stepsCount(goal),
      onTap: () => showStepGoalSheet(context),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showStepGoalSheet(context),
        child: GoalRing(
          pct: math.min(100, steps * 100 / goal),
          size: 56,
          color: done ? gc.ember : null,
          child: done
              ? SvgPathIcon(Ic.checkBold, size: 18, color: gc.ember)
              : Icon(PhosphorIconsBold.footprints, size: 20, color: gc.textSecondary),
        ),
      ),
    );
    final scale = MediaQuery.textScalerOf(context).scale(10) / 10;
    final stepsStat = _stat(gc, t.stepsToday, _count(steps), unit: t.stepsGoalUnit(_count(goal)));
    final kcalStat = _stat(gc, t.activeKcal, '≈ ${_count(kcal.total)}');
    return Semantics(
      button: true,
      label: t.stepsToday,
      hint: t.stepsOpenProgress,
      value: '${_count(steps)}, ≈ ${_count(kcal.total)} kcal',
      onTap: _openProgress,
      container: true,
      child: GestureDetector(
        excludeFromSemantics: true,
        behavior: HitTestBehavior.opaque,
        onTap: _openProgress,
        child: SoftCard(
          radius: 22,
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  final twoColumns = c.maxWidth >= 56 + 14 + 2 * 84 * scale;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ring,
                      const SizedBox(width: 14),
                      Expanded(
                        child: ExcludeSemantics(
                          child: FitTextGroup(
                            child: twoColumns
                                ? Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [Expanded(child: stepsStat), Expanded(child: kcalStat)],
                                  )
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [stepsStat, const SizedBox(height: 10), kcalStat],
                                  ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              Semantics(
                button: true,
                label: note,
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
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 14),
                        child: Text(
                          note,
                          style: AppTheme.f(11, weight: FontWeight.w500, color: gc.textTertiary),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(GymColors gc, String label, String value, {String unit = ''}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: FitText(
            label.toUpperCase(),
            style: AppTheme.f(9.5, weight: FontWeight.w600, color: gc.textTertiary, letterSpacing: 0.9),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: RollIn(
              value,
              style: AppTheme.f(23, weight: FontWeight.w800, color: gc.text),
            ),
          ),
        ),
        if (unit.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            unit,
            style: AppTheme.f(11, weight: FontWeight.w600, color: gc.textSecondary),
          ),
        ],
      ],
    );
  }
}

void _openProgress() => fit.openProgressOnSteps();

DayKcal _todayKcal(DateTime now) => dayKcal(
  day: now,
  steps: fit.steps[_dayKey(now)],
  sessions: fit.sessions,
  bodyweight: fit.bodyweight,
  profileWeightKg: fit.profile.weightKg,
);

/// "Desde las HH:MM" es del sensor (y de iOS); con Health Connect no se muestra.
bool showStepsFrom() => !readsHealthConnect(fit.stepSource);

/// Qué permiso falta, según la fuente.
String stepsDeniedText() {
  if (readsHealthConnect(fit.stepSource)) return t.stepsDeniedBodyHc;
  return defaultTargetPlatform == TargetPlatform.iOS ? t.stepsDeniedBodyIos : t.stepsDeniedBody;
}

String stepsOpenPermissionLabel() => readsHealthConnect(fit.stepSource) ? t.openHealthConnect : t.openSettings;

/// Con Health Connect abre su pantalla de permisos; si no se puede, o con otra fuente, los ajustes de la app.
Future<void> openStepsPermissionScreen() async {
  if (fit.stepSource case final HealthConnectSteps source) {
    var opened = false;
    try {
      opened = await source.openHealthConnect();
    } catch (_) {}
    if (opened) return;
  }
  await AppSettings.openAppSettings();
}

/// Muestra la explicación y, si la persona sigue, activa el conteo y pide el permiso.
Future<void> activateSteps(BuildContext context) async {
  final go = await showStepsExplanation(context);
  if (go == true) await fit.enableSteps();
}

Future<bool?> showStepsExplanation(BuildContext context) {
  final gc = context.gc;
  return showAppSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheet) => Container(
      padding: sheetPad(sheet),
      decoration: BoxDecoration(
        color: gc.bgRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: 20),
            Center(child: Icon(PhosphorIconsBold.footprints, size: 30, color: gc.accent)),
            const SizedBox(height: 12),
            Text(
              t.stepsEnableTitle,
              textAlign: TextAlign.center,
              style: AppTheme.f(19, color: gc.text),
            ),
            const SizedBox(height: 10),
            Text(
              readsHealthConnect(fit.stepSource) ? t.stepsPermissionBodyHc : t.stepsPermissionBody,
              textAlign: TextAlign.center,
              style: AppTheme.f(12.5, weight: FontWeight.w500, color: gc.textSecondary, height: 1.45),
            ),
            const SizedBox(height: 22),
            PrimaryButton(label: t.stepsContinue, onTap: () => Navigator.of(sheet).pop(true)),
          ],
        ),
      ),
    ),
  );
}

void showStepGoalSheet(BuildContext context) {
  final gc = context.gc;
  showAppSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setSheet) => Container(
        padding: sheetPad(sheet),
        decoration: BoxDecoration(
          color: gc.bgRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: 20),
              Text(
                t.stepGoal.toUpperCase(),
                textAlign: TextAlign.center,
                style: AppTheme.f(19, color: gc.text),
              ),
              const SizedBox(height: 6),
              Text(
                t.stepsCount(fit.steps[_dayKey(DateTime.now())] ?? 0),
                textAlign: TextAlign.center,
                style: AppTheme.f(12.5, weight: FontWeight.w500, color: gc.textSecondary),
              ),
              const SizedBox(height: 20),
              Center(
                child: StepperControl(
                  value: t.stepsCount(fit.stepGoal),
                  minWidth: 148,
                  onDec: () => setSheet(() => fit.setStepGoal(fit.stepGoal - kStepGoalStep)),
                  onInc: () => setSheet(() => fit.setStepGoal(fit.stepGoal + kStepGoalStep)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                t.stepGoalHint,
                textAlign: TextAlign.center,
                style: AppTheme.f(12, weight: FontWeight.w500, color: gc.textSecondary, height: 1.45),
              ),
              const SizedBox(height: 22),
              PrimaryButton(label: t.done, onTap: () => Navigator.of(sheet).pop()),
            ],
          ),
          ),
      ),
    ),
  );
}

void showStepsHelp(BuildContext context) {
  final gc = context.gc;
  final kcal = _todayKcal(DateTime.now());
  // Wrap: with very large text the value drops below the label instead of splitting a word.
  Widget row(String label, int value) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      children: [
        Text(
          label,
          style: AppTheme.f(13, weight: FontWeight.w600, color: gc.text),
        ),
        Text(
          '≈ ${_count(value)} kcal',
          style: AppTheme.f(13, weight: FontWeight.w700, color: gc.text),
        ),
      ],
    ),
  );
  final hint = AppTheme.f(12, weight: FontWeight.w500, color: gc.textSecondary, height: 1.45);
  showAppSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheet) => Container(
      padding: sheetPad(sheet),
      decoration: BoxDecoration(
        color: gc.bgRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: 20),
            Text(
              t.stepsHelpTitle,
              textAlign: TextAlign.center,
              style: AppTheme.f(19, color: gc.text),
            ),
            const SizedBox(height: 10),
            Text(t.stepsHelpBody, textAlign: TextAlign.center, style: hint),
            const SizedBox(height: 16),
            row(t.stepsByWalking, kcal.stepsKcal),
            row(t.kcalByWorkouts, kcal.workoutKcal),
            const SizedBox(height: 16),
            Text(
              t.estimatedWithWeight(fit.weightLabel(kcal.weightKg)),
              textAlign: TextAlign.center,
              style: hint,
            ),
            const SizedBox(height: 6),
            Text(t.stepsOverlapHint, textAlign: TextAlign.center, style: hint),
            if (readsHealthConnect(fit.stepSource)) ...[
              const SizedBox(height: 6),
              Text(t.stepsHcHint, textAlign: TextAlign.center, style: hint),
            ] else if (defaultTargetPlatform == TargetPlatform.android) ...[
              const SizedBox(height: 6),
              Text(t.stepsAndroidHint, textAlign: TextAlign.center, style: hint),
            ],
            const SizedBox(height: 22),
            PrimaryButton(label: t.done, onTap: () => Navigator.of(sheet).pop()),
          ],
        ),
      ),
    ),
  );
}
