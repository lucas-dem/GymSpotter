import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/services/step_source.dart';
import 'package:infyter/services/step_source_android.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:infyter/wear/wear_app.dart';
import 'package:infyter/wear/wear_shell.dart';
import 'package:infyter/widgets/steps_card.dart';

class _CountingSource extends FakeStepSource {
  int availableCalls = 0;
  int permissionCalls = 0;
  int requestCalls = 0;

  @override
  Future<bool> isAvailable() {
    availableCalls++;
    return super.isAvailable();
  }

  @override
  Future<StepPermission> permission() {
    permissionCalls++;
    return super.permission();
  }

  @override
  Future<StepPermission> requestPermission() {
    requestCalls++;
    return super.requestPermission();
  }
}

String _hoy() {
  final d = DateTime.now();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

void _reset() {
  fit.saveAndExit();
  fit.sessions.clear();
  fit.routines.clear();
  fit.weeklyPlan.clear();
  fit.steps.clear();
  fit.stepsFrom.clear();
  fit.stepsOn = false;
  fit.stepsAskedAt = null;
  fit.stepsStatus = StepsStatus.unread;
  fit.stepSource = const UnavailableStepSource();
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(454, 454);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const WearApp());
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

List<String> _visibleTexts(WidgetTester tester) => [
  for (final e in find.byType(Text).evaluate())
    if (e.findAncestorWidgetOfExactType<WearClock>() == null) ?(e.widget as Text).data,
];

Future<List<String>> _allTexts(WidgetTester tester) async {
  final out = <String>{..._visibleTexts(tester)};
  final position = tester.state<ScrollableState>(find.byType(Scrollable).last).position;
  position.jumpTo(position.minScrollExtent);
  await tester.pump();
  for (var i = 0; i < 80; i++) {
    out.addAll(_visibleTexts(tester));
    if (position.pixels >= position.maxScrollExtent) break;
    position.jumpTo((position.pixels + 60).clamp(position.minScrollExtent, position.maxScrollExtent));
    await tester.pump();
  }
  expect(position.pixels, position.maxScrollExtent);
  out.addAll(_visibleTexts(tester));
  return out.toList()..sort();
}

const _stepKeys = [
  'stepsToday',
  'activeKcal',
  'stepsGoalUnit',
  'stepsEnableTitle',
  'stepsEnableBody',
  'stepsEnable',
  'stepsDeniedTitle',
  'stepsDeniedBody',
  'stepsDeniedBodyIos',
  'stepsCountingSince',
  'stepsContinue',
  'stepsHide',
  'stepsOpenProgress',
  'stepsChangeGoal',
  'stepsShowEstimate',
  'stepsGoalReached',
  'stepsPermissionBody',
  'stepGoal',
  'stepGoalHint',
  'stepsCount',
  'stepsHelpTitle',
  'stepsHelpBody',
  'stepsByWalking',
  'kcalByWorkouts',
  'stepsOverlapHint',
  'stepsAndroidHint',
  'stepsTitle',
  'stepsAvgUnit',
  'stepsGoalDays',
  'stepsPeriodEmpty',
  'stepsLegendGaps',
  'stepsLegendPartial',
  'kcalWeightPerDay',
  'stepsRangeLabel',
  'kcalTitle',
  'countSteps',
  'stepsNeedsPermission',
  'stepsSettingsHint',
  'stepsUnavailable',
  'stepsAllow',
  'stepsEnableBodyHc',
  'stepsPermissionBodyHc',
  'stepsDeniedBodyHc',
  'openHealthConnect',
  'stepsSettingsHintHc',
  'stepsHcHint',
];

Map<String, dynamic> _arb(String lang) =>
    jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map<String, dynamic>;

Iterable<String> _literals(String message) sync* {
  final parts = <String>[];
  final buffer = StringBuffer();
  var depth = 0;
  void flush() {
    if (depth.isEven) parts.add(buffer.toString());
    buffer.clear();
  }

  for (final char in message.split('')) {
    if (char == '{') {
      flush();
      depth++;
    } else if (char == '}') {
      flush();
      depth--;
    } else {
      buffer.write(char);
    }
  }
  flush();
  for (final part in parts) {
    final text = part.trim();
    if (text.length >= 4) yield text;
  }
}

List<String> _stepFragments() => [
  for (final lang in ['en', 'es'])
    for (final key in _stepKeys)
      if (_arb(lang)[key] case final String value) ..._literals(value),
];

const _sharedWords = <String>{
  'continue', // el boton "continuar" del reloj con un entrenamiento en pausa
  'continuar', // idem en espanol
  'activar', // palabra comun que el reloj puede usar en ajustes
};

bool _isStepText(String text, List<String> fragments) {
  final lower = text.toLowerCase();
  return fragments.any((f) {
    final low = f.toLowerCase();
    if (_sharedWords.contains(low)) return false;
    final multiWord = f.contains(' ');
    if (!multiWord && f.length < 5) return false;
    return lower == low || text.contains(f) || (multiWord && lower.contains(low));
  });
}

List<String> _stepStringsIn(List<String> texts) {
  final fragments = _stepFragments();
  return [
    for (final text in texts)
      if (_isStepText(text, fragments)) text,
  ];
}

void main() {
  setUp(_reset);
  tearDown(_reset);

  testWidgets('the watch home shows no steps card even with steps saved', (tester) async {
    final source = _CountingSource()..days = [StepDayReading(_hoy(), 9000)];
    fit.stepSource = source;
    fit.stepsOn = true;
    fit.steps[_hoy()] = 9000;
    await _pump(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(StepsCard), findsNothing);
    expect(source.reads, 0);
    expect(source.requestCalls, 0);
    expect(source.permissionCalls, 0);
  });

  testWidgets('the watch screens look the same with and without steps', (tester) async {
    await _pump(tester);
    final before = await _allTexts(tester);

    fit.stepSource = _CountingSource();
    fit.stepsOn = true;
    fit.stepGoal = 12000;
    fit.steps[_hoy()] = 9000;
    fit.stepsStatus = StepsStatus.counting;
    fit.setStepGoal(10000);
    await tester.pump(const Duration(milliseconds: 200));

    expect(await _allTexts(tester), before);
    expect(find.byType(StepsCard), findsNothing);

    fit.pushRoute('settings');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(StepsCard), findsNothing);
    expect(find.textContaining('9000'), findsNothing);
    expect(find.textContaining('9.000'), findsNothing);
  });

  test('on the watch the phone source reports unavailable and nothing is read', () async {
    final calls = <String>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel(StepChannel.name);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == StepChannel.isAvailable ? false : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    fit.stepSource = AndroidStepSource(channel: channel);
    fit.stepsOn = true;
    await fit.refreshSteps();

    expect(fit.stepsStatus, StepsStatus.unavailable);
    expect(fit.steps, isEmpty);
    expect(calls, everyElement(StepChannel.isAvailable));
    expect(calls, isNot(contains(StepChannel.requestPermission)));
    expect(calls, isNot(contains(StepChannel.readCounter)));
    expect(calls, isNot(contains(StepChannel.loadAnchor)));
  });

  test('turning steps on with an unavailable source asks nothing and stays off', () async {
    final source = _CountingSource()..available = false;
    fit.stepSource = source;
    await fit.enableSteps();

    expect(fit.stepsOn, isFalse);
    expect(fit.stepsAskedAt, isNull);
    expect(fit.stepsStatus, StepsStatus.unavailable);
    expect(source.requestCalls, 0);
    expect(source.permissionCalls, 0);
    expect(source.reads, 0);
    expect(fit.toJson()['stepsOn'], isNot(true));
  });

  test('the step string detector catches a fixed steps text', () {
    expect(_stepFragments(), isNotEmpty);
    expect(_stepStringsIn(['Start workout', 'Routines']), isEmpty);
    expect(_stepStringsIn(['Start workout', 'Steps today']), ['Steps today']);
    expect(_stepStringsIn(['STEPS']), ['STEPS']);
    expect(_stepStringsIn(['PASOS HOY']), ['PASOS HOY']);
    expect(_stepStringsIn(['Pasos hoy']), isNotEmpty);
    expect(_stepStringsIn(['Weekly goal', 'WEEKLY GOAL']), isEmpty);
  });

  test('the explicit step keys cover every step or kcal key of the arb', () {
    expect(_literals('Steps').toList(), ['Steps']);
    expect(_literals('Hoy, {n} pasos').toList(), ['Hoy,', 'pasos']);
    expect(_literals('Steps{n}').toList(), ['Steps']);
    expect(_literals('{n, plural, one{paso} other{pasos}}').toList(), ['paso', 'pasos']);
    for (final lang in ['en', 'es']) {
      expect(
        [
          for (final k in _stepKeys)
            if (_arb(lang)[k] is! String) k,
        ],
        isEmpty,
        reason: 'clave que ya no existe ($lang)',
      );
      final missing = [
        for (final key in _arb(lang).keys)
          if (RegExp(r'^(steps[A-Z]|stepGoal|kcal|activeKcal)').hasMatch(key) &&
              !key.startsWith('@') &&
              !_stepKeys.contains(key))
            key,
      ];
      expect(missing, isEmpty, reason: 'sumar a _stepKeys ($lang)');
    }
    expect(_literals('{n, plural, =1{{n} step} other{{n} steps today}}').toList(), ['step', 'steps today']);
    expect(_literals('{steps} steps'), ['steps']);
    expect(_literals('/ {goal}'), isEmpty);
  });

  testWidgets('the detector sees uppercase headings through the text collector', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ListView(children: const [Text('STEPS'), Text('PASOS HOY'), Text('WEEKLY GOAL')])),
    );
    expect(_stepStringsIn(await _allTexts(tester)), ['PASOS HOY', 'STEPS']);
  });

  for (final lang in ['en', 'es']) {
    for (final state in ['off', 'counting', 'denied']) {
      testWidgets('no steps string on the watch home, routines or settings ($lang, $state)', (tester) async {
        final previous = appLanguage;
        setAppLanguage(lang);
        addTearDown(() => setAppLanguage(previous));
        final source = _CountingSource()
          ..days = [StepDayReading(_hoy(), 9000)]
          ..permissionValue = state == 'denied' ? StepPermission.denied : StepPermission.granted;
        fit.stepSource = source;
        fit.stepsOn = state != 'off';
        if (state == 'counting') {
          fit.steps[_hoy()] = 9000;
          fit.stepsStatus = StepsStatus.counting;
        }
        if (state == 'denied') fit.stepsStatus = StepsStatus.denied;
        await _pump(tester);
        final screens = {
          'home': find.byType(WearHome),
          'routines': find.byType(WearRoutines),
          'settings': find.byType(WearSettings),
        };
        for (final entry in screens.entries) {
          fit.pushRoute(entry.key);
          await tester.pump(const Duration(milliseconds: 400));
          expect(entry.value, findsOneWidget, reason: entry.key);
          final texts = await _allTexts(tester);
          expect(texts, isNotEmpty, reason: entry.key);
          expect(_stepStringsIn(texts), isEmpty, reason: '${entry.key} $state');
        }
        expect(source.reads, 0);
        expect(source.requestCalls, 0);
      });
    }
  }

  testWidgets('a parked workout on the watch home shows continue and no steps string', (tester) async {
    final id = fit.createRoutine('Push');
    fit.toggleRoutineExercise(id, 'EIeI8Vf');
    fit.startRoutine(fit.routines.first);
    await _pump(tester);
    fit.parkSession();
    await tester.pump(const Duration(milliseconds: 400));
    final texts = await _allTexts(tester);
    expect(texts.map((e) => e.toLowerCase()), contains(t.continueBtn.toLowerCase()));
    expect(_stepStringsIn(texts), isEmpty);
    fit.saveAndExit();
    await tester.pump(const Duration(milliseconds: 400));
  });
}
