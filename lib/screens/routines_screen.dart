import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../catalog/program_templates.dart';
import '../l10n/l10n.dart';
import '../models/workout.dart';
import '../services/plan_qr.dart';
import '../state/fit_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/dialogs.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_notch.dart';
import '../widgets/routine_folder.dart';
import '../widgets/svg_icon.dart';
import '../widgets/ui_kit.dart';
import 'plan_import_sheet.dart';

class RoutinesScreen extends StatelessWidget {
  const RoutinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    if (fit.trainerMode && fit.activeAthleteId == null) {
      return _athletesView(context, gc);
    }
    final currentRoutines = fit.visibleRoutines;
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        clipBehavior: Clip.none,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenHeader(
              title: fit.trainerMode ? fit.activeAthleteName : t.routines,
              onBack: fit.backFromRoutines,
              titleSize: 22,
              actions: [
                Semantics(
                  button: true,
                  label: t.importRoutines,
                  child: RoundAction(
                    onTap: () => showPlanImportSheet(context),
                    child: Icon(PhosphorIconsRegular.downloadSimple, size: 17, color: gc.text),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: t.importByQr,
                  child: RoundAction(
                    onTap: () => scanPlanQr(context),
                    child: Icon(PhosphorIconsRegular.qrCode, size: 17, color: gc.text),
                  ),
                ),
                if (currentRoutines.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    label: t.shareWeek,
                    child: RoundAction(
                      onTap: () => _shareMenu(context),
                      child: Icon(PhosphorIconsRegular.shareNetwork, size: 17, color: gc.text),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 22),
            Text(
              t.weeklyPlan,
              style: AppTheme.f(12, weight: FontWeight.w600, color: gc.textSecondary, letterSpacing: 1.5),
            ),
            const SizedBox(height: 10),
            SoftCard(
              radius: 20,
              borderColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Column(children: [for (int i = 0; i < 7; i++) _dayRow(context, gc, i)]),
            ),
            const SizedBox(height: 26),
            Text(
              t.yourRoutines,
              style: AppTheme.f(12, weight: FontWeight.w600, color: gc.textSecondary, letterSpacing: 1.5),
            ),
            const SizedBox(height: 10),
            if (currentRoutines.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 26),
                child: Text(
                  t.noRoutines,
                  textAlign: TextAlign.center,
                  style: AppTheme.f(13, weight: FontWeight.w500, color: gc.textSecondary),
                ),
              )
            else ...[
              for (final group in fit.routineGroups) ...[
                _groupHeader(gc, group, fit.routinesInGroup(group).length),
                _folders(context, fit.routinesInGroup(group)),
                const SizedBox(height: 10),
              ],
              _folders(context, fit.routinesInGroup('')),
            ],
            const SizedBox(height: 16),
            PrimaryButton(label: t.newRoutine, onTap: () => fit.openRoutine(fit.createRoutine())),
            const SizedBox(height: 10),
            GhostButton(
              label: t.templates,
              icon: PhosphorIconsRegular.stack,
              onTap: () => _openTemplates(context),
            ),
            const SizedBox(height: 10),
            GhostButton(
              label: t.importRoutines,
              icon: PhosphorIconsRegular.downloadSimple,
              onTap: () => showPlanImportSheet(context),
            ),
            const SizedBox(height: 10),
            GhostButton(
              label: t.scanPlanQr,
              icon: PhosphorIconsRegular.qrCode,
              onTap: () => scanPlanQr(context),
            ),
            const SizedBox(height: 10),
            GhostButton(label: t.aiRoutine, icon: PhosphorIconsRegular.sparkle, onTap: fit.goAiPlan),
          ],
        ),
      ),
    );
  }

  Widget _athletesView(BuildContext context, GymColors gc) {
    final entries = <({String id, String name, int count})>[
      (id: 'me', name: t.myTraining, count: fit.personalRoutines.length),
      for (final athlete in fit.athletes)
        (
          id: athlete.id,
          name: athlete.name,
          count: fit.routines.where((r) => r.ownerId == athlete.id).length,
        ),
    ];
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenHeader(
              title: t.routines,
              onBack: fit.backFromRoutines,
              titleSize: 22,
              actions: [
                Semantics(
                  button: true,
                  label: t.importByQr,
                  child: RoundAction(
                    onTap: () => scanPlanQr(context),
                    child: Icon(PhosphorIconsRegular.qrCode, size: 17, color: gc.text),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  label: t.addAthlete,
                  child: RoundAction(
                    onTap: () => _addAthlete(context),
                    child: Icon(PhosphorIconsRegular.userPlus, size: 17, color: gc.text),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              t.peopleCaps,
              style: AppTheme.f(12, weight: FontWeight.w600, color: gc.textSecondary, letterSpacing: 1.5),
            ),
            const SizedBox(height: 6),
            Text(
              t.athletesHint,
              style: AppTheme.f(12.5, weight: FontWeight.w500, color: gc.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < entries.length; i += 2)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _AthleteFolder(
                        name: entries[i].name,
                        routineCount: entries[i].count,
                        personal: entries[i].id == 'me',
                        onTap: () => fit.openAthlete(entries[i].id),
                        onMenu: () => _athleteMenu(context, entries[i].id),
                        onShareQr: entries[i].id == 'me' || entries[i].count == 0
                            ? null
                            : () => _shareAthleteQr(context, entries[i].id),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: i + 1 >= entries.length
                          ? const SizedBox.shrink()
                          : _AthleteFolder(
                              name: entries[i + 1].name,
                              routineCount: entries[i + 1].count,
                              onTap: () => fit.openAthlete(entries[i + 1].id),
                              onMenu: () => _athleteMenu(context, entries[i + 1].id),
                              onShareQr: entries[i + 1].count == 0
                                  ? null
                                  : () => _shareAthleteQr(context, entries[i + 1].id),
                            ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            PrimaryButton(label: t.addAthlete, onTap: () => _addAthlete(context)),
            const SizedBox(height: 10),
            GhostButton(
              label: t.importByQr,
              icon: PhosphorIconsRegular.qrCode,
              onTap: () => scanPlanQr(context),
            ),
          ],
        ),
      ),
    );
  }

  void _shareAthleteQr(BuildContext context, String id) {
    final athlete = fit.athletes.where((a) => a.id == id).firstOrNull;
    if (athlete == null) return;
    final routines = fit.routines.where((r) => r.ownerId == id).toList();
    showPlanQr(context, routines, title: athlete.name, schedule: fit.athleteWeeklyPlans[id]);
  }

  Future<String?> _askAthleteName(BuildContext context, {String initial = '', String? dialogTitle}) async {
    final gc = context.gc;
    final controller = TextEditingController(text: initial);
    if (initial.isNotEmpty) {
      controller.selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
    }
    final value = await showAppDialog<String>(
      context: context,
      builder: (dialog) => appDialog(
        gc,
        title: Text(
          dialogTitle ?? (initial.isEmpty ? t.newAthlete : t.editAthlete),
          style: AppTheme.f(19, weight: FontWeight.w800, color: gc.text),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (value) => Navigator.pop(dialog, value),
          style: AppTheme.f(15, weight: FontWeight.w600, color: gc.text),
          decoration: InputDecoration(
            hintText: t.nameLabel,
            filled: true,
            fillColor: gc.bgRaised2,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          dialogAction(t.cancel, gc.textSecondary, () => Navigator.pop(dialog), strong: false),
          dialogAction(t.save, gc.accent, () => Navigator.pop(dialog, controller.text)),
        ],
      ),
    );
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  Future<void> _addAthlete(BuildContext context) async {
    final name = await _askAthleteName(context);
    if (name != null) fit.addAthlete(name);
  }

  void _athleteMenu(BuildContext context, String id) {
    final personal = id == 'me';
    final athlete = fit.athletes.where((a) => a.id == id).firstOrNull;
    if (!personal && athlete == null) return;
    final name = personal ? t.myTraining : athlete!.name;
    final routines = fit.routines.where((r) => r.ownerId == id).toList();
    showAppSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheet) => Container(
        padding: sheetPad(sheet),
        decoration: BoxDecoration(
          color: context.gc.bgRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: 16),
            SheetTitle(name, subtitle: t.routineCount(routines.length)),
            const SizedBox(height: 14),
            OptionGroup([
              OptionItem(
                t.openRoutines,
                icon: PhosphorIconsRegular.folderOpen,
                onTap: () {
                  Navigator.pop(sheet);
                  fit.openAthlete(id);
                },
              ),
              if (!personal && routines.isNotEmpty)
                OptionItem(
                  t.sharePlanQr,
                  icon: PhosphorIconsRegular.qrCode,
                  onTap: () {
                    Navigator.pop(sheet);
                    _shareAthleteQr(context, id);
                  },
                ),
              OptionItem(
                t.duplicatePlan,
                icon: PhosphorIconsRegular.copy,
                onTap: () async {
                  Navigator.pop(sheet);
                  final newName = await _askAthleteName(
                    context,
                    initial: personal ? t.newAthlete : t.copySuffix(name),
                    dialogTitle: t.duplicatePlan,
                  );
                  if (newName == null || !context.mounted) return;
                  final duplicatedId = fit.duplicatePlanAsAthlete(id, newName);
                  if (duplicatedId.isEmpty || !context.mounted) return;
                  fit.openAthlete(duplicatedId);
                  showNotchToast(
                    context,
                    t.planDuplicated,
                    subtitle: newName,
                    icon: PhosphorIconsFill.checkCircle,
                    accent: context.gc.sage,
                  );
                },
              ),
              if (!personal) ...[
                OptionItem(
                  t.editEntry,
                  icon: PhosphorIconsRegular.pencilSimple,
                  onTap: () async {
                    Navigator.pop(sheet);
                    final editedName = await _askAthleteName(context, initial: name);
                    if (editedName != null) fit.renameAthlete(id, editedName);
                  },
                ),
                OptionItem(
                  t.delete,
                  icon: PhosphorIconsRegular.trash,
                  danger: true,
                  onTap: () async {
                    Navigator.pop(sheet);
                    final ok = await askConfirm(
                      context,
                      title: t.deleteAthlete,
                      body: t.deleteAthleteBody(name),
                      confirmLabel: t.delete,
                      danger: true,
                    );
                    if (ok) fit.deleteAthlete(id);
                  },
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  void _shareMenu(BuildContext context) {
    final gc = context.gc;
    final currentRoutines = fit.visibleRoutines;
    final planned = currentRoutines.where((r) => fit.visibleWeeklyPlan.containsValue(r.id)).toList();
    showAppSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheet) => Container(
        padding: sheetPad(sheet),
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.85),
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
              const SizedBox(height: 18),
              _shareOption(gc, PhosphorIconsRegular.qrCode, t.sharePlanQr, t.sharePlanQrHint, () {
                Navigator.pop(sheet);
                showPlanQr(
                  context,
                  planned.isEmpty
                      ? currentRoutines
                      : [...planned, ...currentRoutines.where((r) => !planned.contains(r))],
                  title: fit.activeAthleteName,
                );
              }),
              _shareOption(gc, PhosphorIconsRegular.calendarDots, t.shareWeek, t.shareWeekHint, () {
                Navigator.pop(sheet);
                sharePlan(
                  planned.isEmpty
                      ? currentRoutines
                      : [...planned, ...currentRoutines.where((r) => !planned.contains(r))],
                  title: t.weeklyPlan,
                );
              }),
              const SizedBox(height: 14),
              Text(
                t.shareRoutine.toUpperCase(),
                style: AppTheme.f(10.5, weight: FontWeight.w700, color: gc.textTertiary, letterSpacing: 1.3),
              ),
              const SizedBox(height: 8),
              for (final r in [
                for (final group in fit.routineGroups) ...fit.routinesInGroup(group),
                ...fit.routinesInGroup(''),
              ])
                _shareOption(
                  gc,
                  PhosphorIconsRegular.listChecks,
                  fit.routineTitle(r),
                  [if (r.group.isNotEmpty) r.group, t.exerciseCount(r.exerciseIds.length)].join(' · '),
                  () {
                    Navigator.pop(sheet);
                    sharePlan([r]);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shareOption(GymColors gc, IconData icon, String title, String hint, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: gc.bgRaised2, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: gc.emberSoft, borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, size: 19, color: gc.ember),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.f(14, weight: FontWeight.w600, color: gc.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.f(11.5, weight: FontWeight.w500, color: gc.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(PhosphorIconsRegular.shareNetwork, size: 16, color: gc.textSecondary),
          ],
        ),
      ),
    );
  }

  void _openTemplates(BuildContext context) {
    final gc = context.gc;
    showAppSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheet) => Container(
        padding: sheetPad(sheet),
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.85),
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
              const SizedBox(height: 16),
              SheetTitle(t.templates, subtitle: t.templatesHint),
              const SizedBox(height: 16),
              for (final template in kProgramTemplates) _templateCard(context, gc, sheet, template),
            ],
          ),
        ),
      ),
    );
  }

  Widget _templateCard(BuildContext context, GymColors gc, BuildContext sheet, ProgramTemplate template) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final made = fit.applyTemplate(template);
        Navigator.pop(sheet);
        if (made == 0 || !context.mounted) return;
        showNotchToast(
          context,
          t.templateAdded(made),
          subtitle: template.name,
          icon: PhosphorIconsFill.stack,
          accent: context.gc.sage,
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: gc.bgRaised2, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: gc.emberSoft, borderRadius: BorderRadius.circular(12)),
              child: Icon(PhosphorIconsRegular.stack, size: 20, color: gc.ember),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name,
                    style: AppTheme.f(15, weight: FontWeight.w700, color: gc.text, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t.templateBlurb(template.id),
                    style: AppTheme.f(12, weight: FontWeight.w500, color: gc.textSecondary, height: 1.35),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.dayCount(template.days.length),
                    style: AppTheme.f(11, weight: FontWeight.w500, color: gc.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(PhosphorIconsRegular.plus, size: 16, color: gc.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _dayRow(BuildContext context, GymColors gc, int i) {
    final weekday = i + 1;
    final r = fit.visibleRoutines.where((x) => x.id == fit.visibleWeeklyPlan[weekday]);
    final assigned = r.isNotEmpty ? r.first : null;
    final isToday = DateTime.now().weekday == weekday;
    return GestureDetector(
      onTap: () => _pickRoutine(context, weekday),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Text(
              t.weekdayShort(weekday),
              maxLines: 1,
              softWrap: false,
              style: AppTheme.f(14, weight: FontWeight.w600, color: isToday ? gc.ember : gc.text),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                assigned == null ? t.restDayShort : fit.routineTitle(assigned),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.f(
                  14,
                  weight: FontWeight.w500,
                  color: assigned != null ? gc.text : gc.textTertiary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SvgPathIcon(Ic.chevronRight, size: 14, color: gc.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _groupHeader(GymColors gc, String name, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Row(
        children: [
          Icon(PhosphorIconsRegular.folderSimple, size: 15, color: gc.brass),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.f(13, weight: FontWeight.w700, color: gc.text, letterSpacing: 1),
            ),
          ),
          Text(
            '$count',
            style: AppTheme.f(12, weight: FontWeight.w500, color: gc.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _folders(BuildContext context, List<Routine> list) {
    return Column(
      children: [
        for (var i = 0; i < list.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: RoutineFolder(routine: list[i], onMenu: () => _routineMenu(context, list[i])),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: i + 1 < list.length
                      ? RoutineFolder(routine: list[i + 1], onMenu: () => _routineMenu(context, list[i + 1]))
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _routineMenu(BuildContext context, Routine r) {
    final gc = context.gc;
    showAppSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheet) => Container(
        padding: sheetPad(sheet),
        decoration: BoxDecoration(
          color: gc.bgRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: 16),
            SheetTitle(fit.routineTitle(r), subtitle: t.exerciseCount(r.exerciseIds.length)),
            const SizedBox(height: 14),
            OptionGroup([
              OptionItem(
                t.editEntry,
                icon: PhosphorIconsRegular.pencilSimple,
                onTap: () {
                  Navigator.pop(sheet);
                  fit.openRoutine(r.id);
                },
              ),
              if (r.exerciseIds.isNotEmpty)
                OptionItem(
                  titleCase(t.startWorkout),
                  icon: PhosphorIconsRegular.play,
                  onTap: () {
                    Navigator.pop(sheet);
                    fit.startRoutine(r);
                  },
                ),
              OptionItem(
                t.shareRoutine,
                icon: PhosphorIconsRegular.shareNetwork,
                onTap: () {
                  Navigator.pop(sheet);
                  sharePlan([r]);
                },
              ),
              OptionItem(
                t.showQr,
                icon: PhosphorIconsRegular.qrCode,
                onTap: () {
                  Navigator.pop(sheet);
                  showPlanQr(context, [r], title: fit.routineTitle(r));
                },
              ),
              OptionItem(
                t.duplicateRoutine,
                icon: PhosphorIconsRegular.copy,
                onTap: () {
                  Navigator.pop(sheet);
                  fit.duplicateRoutine(r.id);
                },
              ),
              OptionItem(
                t.delete,
                icon: PhosphorIconsRegular.trash,
                danger: true,
                onTap: () async {
                  Navigator.pop(sheet);
                  final ok = await askConfirm(
                    context,
                    title: t.deleteRoutine,
                    body: fit.routineTitle(r),
                    confirmLabel: t.delete,
                    danger: true,
                  );
                  if (ok) fit.deleteRoutine(r.id);
                },
              ),
            ]),
          ],
        ),
      ),
    );
  }

  void _pickRoutine(BuildContext context, int weekday) {
    final gc = context.gc;
    final routines = [
      for (final group in fit.routineGroups) ...fit.routinesInGroup(group),
      ...fit.routinesInGroup(''),
    ];
    showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheet) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.72),
        padding: sheetPad(sheet),
        decoration: BoxDecoration(
          color: gc.bgRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: 16),
            SheetTitle(titleCase(t.setDay(t.weekday(weekday).toUpperCase()))),
            const SizedBox(height: 14),
            Flexible(
              child: OptionGroup(scroll: true, [
                OptionItem(
                  t.restDayShort,
                  icon: PhosphorIconsRegular.moonStars,
                  selected: fit.visibleWeeklyPlan[weekday] == null,
                  onTap: () {
                    fit.assignRoutineToDay(weekday, null);
                    Navigator.pop(sheet);
                  },
                ),
                for (final r in routines)
                  OptionItem(
                    fit.routineTitle(r),
                    detail: r.group.isEmpty ? null : r.group,
                    selected: fit.visibleWeeklyPlan[weekday] == r.id,
                    onTap: () {
                      fit.assignRoutineToDay(weekday, r.id);
                      Navigator.pop(sheet);
                    },
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _AthleteFolder extends StatelessWidget {
  const _AthleteFolder({
    required this.name,
    required this.routineCount,
    required this.onTap,
    this.onMenu,
    this.onShareQr,
    this.personal = false,
  });

  final String name;
  final int routineCount;
  final VoidCallback onTap;
  final VoidCallback? onMenu;
  final VoidCallback? onShareQr;
  final bool personal;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    final hue = personal
        ? gc.ember
        : kFolderHues[name.codeUnits.fold<int>(0, (a, b) => a + b) % kFolderHues.length];
    final dark = gc.bg.computeLuminance() < .5;
    return Pressable(
      onTap: onTap,
      scale: .975,
      child: SizedBox(
        height: 164,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: 76,
              height: 40,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: gc.bgRaised,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                ),
              ),
            ),
            Positioned.fill(
              top: 16,
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
              left: 10,
              right: 10,
              top: 30,
              height: 58,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color.lerp(hue, Colors.black, dark ? .35 : .12),
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
            Positioned(
              left: 6,
              right: 6,
              top: 54,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 10, 12),
                decoration: BoxDecoration(
                  color: Color.lerp(gc.bgRaised2, hue, dark ? .14 : .28),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: dark ? .3 : .08), blurRadius: 14),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: hue.withValues(alpha: .22),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            personal ? PhosphorIconsFill.user : PhosphorIconsFill.barbell,
                            size: 15,
                            color: hue,
                          ),
                        ),
                        const Spacer(),
                        if (onShareQr != null)
                          Semantics(
                            button: true,
                            label: t.shareAthleteQr(name),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onShareQr,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  color: hue.withValues(alpha: .2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(PhosphorIconsBold.qrCode, size: 14, color: hue),
                                    const SizedBox(width: 4),
                                    Text(
                                      t.qrLabel,
                                      style: AppTheme.f(10.5, weight: FontWeight.w800, color: hue),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        if (onShareQr != null && onMenu != null) const SizedBox(width: 2),
                        if (onMenu != null)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onMenu,
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(PhosphorIconsBold.dotsThreeVertical, size: 16, color: gc.text),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.f(15.5, weight: FontWeight.w800, color: gc.text, height: 1.12),
                    ),
                    const Spacer(),
                    Text(
                      t.routineCount(routineCount),
                      style: AppTheme.f(11.5, weight: FontWeight.w600, color: gc.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
