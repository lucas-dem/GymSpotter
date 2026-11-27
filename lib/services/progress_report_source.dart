import '../l10n/l10n.dart';
import '../models/progress_report.dart';
import '../state/fit_state.dart';
import '../widgets/steps_card.dart' show showStepsFrom;
import 'progress_report_builder.dart';

ProgressReport progressReportFromFit({
  required DateTime from,
  required DateTime to,
  required bool wholeHistory,
  DateTime? now,
}) =>
    buildProgressReport(
      from: from,
      to: to,
      wholeHistory: wholeHistory,
      now: now ?? DateTime.now(),
      language: appLanguage,
      locale: intlLocale,
      units: ReportUnits(
        weight: fit.units,
        length: fit.lengthUnit,
        distance: fit.distanceUnit,
        effort: fit.effortScale,
      ),
      sessions: fit.sessions,
      steps: fit.steps,
      stepsFrom: fit.stepsFrom,
      showStepsFrom: showStepsFrom(),
      bodyweight: fit.bodyweight,
      measures: fit.measures,
      profileWeightKg: fit.profile.weightKg,
      toWeight: fit.toDisplayWeight,
      toMeasure: fit.toDisplayMeasure,
      toDistance: fit.toDisplayKm,
      restFor: fit.restFor,
      exerciseName: t.catalogNameRaw,
    );

({DateTime from, DateTime to})? recordedSpanFromFit() => recordedSpan(
      sessions: fit.sessions,
      steps: fit.steps,
      bodyweight: fit.bodyweight,
      measures: fit.measures,
    );
