import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/screens/routines_screen.dart';
import 'package:infyter/services/plan_qr.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:infyter/theme/app_theme.dart';

void main() {
  test('trainer athletes keep separate routines and schedules in backups', () {
    final source = FitState()..trainerMode = true;
    final athleteId = source.addAthlete('Lucas');
    source.openAthlete(athleteId);
    final routineId = source.createRoutine('PPL · Push');
    source.assignRoutineToDay(DateTime.monday, routineId);

    expect(source.personalRoutines, isEmpty);
    expect(source.visibleRoutines.single.ownerId, athleteId);
    expect(source.visibleWeeklyPlan[DateTime.monday], routineId);
    final sharedFromAthleteList = source.exportPlanJson(
      source.routines.where((r) => r.ownerId == athleteId).toList(),
      schedule: source.athleteWeeklyPlans[athleteId],
    );
    final sharedPlan = jsonDecode(sharedFromAthleteList) as Map<String, dynamic>;
    final sharedRoutine = (sharedPlan['routines'] as List).single as Map<String, dynamic>;
    expect(sharedRoutine['days'], [DateTime.monday]);

    final restored = FitState();
    restored.applyBackup(source.toJson());
    restored.openAthlete(athleteId);

    expect(restored.trainerMode, isTrue);
    expect(restored.athletes.single.name, 'Lucas');
    expect(restored.visibleRoutines.single.name, 'PPL · Push');
    expect(restored.visibleWeeklyPlan[DateTime.monday], routineId);

    source.dispose();
    restored.dispose();
  });

  test('routine QR payload compresses and round-trips unicode JSON', () {
    const json =
        '{"infyter":"plan","routines":[{"name":"Piernas · sábado","exercises":[{"name":"Sentadilla"}]}]}';
    final encoded = encodePlanQrJson(json);

    expect(encoded, startsWith('infyter:plan:1:'));
    expect(decodePlanQr(encoded), json);
    expect(decodePlanQr('https://example.com'), isNull);
  });

  testWidgets('adding an athlete from the dialog keeps the routines tree stable', (tester) async {
    fit.resetAllData();
    fit.toggleTrainerMode();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: AnimatedBuilder(animation: fit, builder: (context, child) => const RoutinesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Agregar atleta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Lucas');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(fit.athletes.map((a) => a.name), contains('Lucas'));
    expect(tester.takeException(), isNull);
    fit.persistNow();
  });
}
