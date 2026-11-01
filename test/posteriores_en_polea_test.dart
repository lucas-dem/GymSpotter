import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/catalog/exercise_catalog.dart';
import 'package:infyter/l10n/catalog_es.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/models/exercise.dart';

// Posteriores en polea (aqvSOQE): the standing reverse fly at a dual cable machine, with the pulleys at shoulder
// height and the cables crossed. It has its own drawing; the two rear delt rows keep the shared one they have today.
const _posteriores = 'aqvSOQE';
const _sharedArtKept = {'G61cXLk', 'yUdIGNs'};

// FNV-1a (32 bits) of the drawing's text, so the test needs no extra package.
int _fnv1a(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash;
}

void main() {
  tearDown(() => setAppLanguage('en'));
  final byId = {for (final e in kExercises) e.id: e};

  test('Posteriores en polea shows its own reverse-fly drawing', () {
    expect(byId[_posteriores]?.art, 'reverse-cable-crossover');
    expect(kExercises.where((e) => e.art == 'reverse-cable-crossover').map((e) => e.id), [_posteriores]);
  });

  test('the two rear delt rows keep the shared drawing, unchanged', () {
    final users = kExercises.where((e) => e.art == 'cable-rear-delt-fly').map((e) => e.id);
    expect(users.toSet(), _sharedArtKept);
    final shared = File('assets/art/cable-rear-delt-fly.txt').readAsStringSync().replaceAll('\r\n', '\n');
    expect(shared.length, 251392);
    expect(_fnv1a(shared), 0x7759997b);
  });

  test('its steps describe the standing reverse fly in every language that has them', () {
    final posteriores = byId[_posteriores]!;
    const shoulderHeight = {
      'en': 'shoulder height',
      'es': 'altura de los hombros',
      'it': "all'altezza delle spalle",
      'zh': '与肩同高',
    };
    for (final entry in shoulderHeight.entries) {
      setAppLanguage(entry.key);
      final steps = exerciseSteps(posteriores);
      expect(steps, hasLength(5), reason: entry.key);
      expect(steps.first, contains(entry.value), reason: entry.key);
    }
  });

  test('Posteriores en polea is a Spanish name only', () {
    final posteriores = byId[_posteriores]!;
    expect(kExerciseNameEs[_posteriores], 'Posteriores en polea');
    expect(kGymNamedExercises, isNot(contains(_posteriores)));
    setAppLanguage('es');
    expect(exerciseName(posteriores), 'Posteriores en polea');
    for (final code in appLanguages.where((code) => code != 'es')) {
      setAppLanguage(code);
      expect(exerciseName(posteriores), isNot('Posteriores en polea'), reason: code);
    }
  });
}
