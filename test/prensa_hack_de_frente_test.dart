import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/catalog/exercise_catalog.dart';
import 'package:infyter/l10n/catalog_es.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/models/exercise.dart';

// Prensa hack de frente: the Prensa hack machine with the user facing it. It is its own exercise with its own
// drawing and a gym name that only Spanish shows; Prensa hack keeps the drawing it has today.
const _frente = 'reverse-pendulum-hack-squat';
const _hack = 'pendulum-hack-squat';

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

  test('Prensa hack de frente is a new exercise with its own drawing', () {
    final frente = byId[_frente]!;
    expect(frente.name, 'Reverse Pendulum Hack Squat');
    expect(frente.art, 'reverse-pendulum-hack-squat');
    expect(frente.primary, 'glutes');
    expect(frente.secondary, ['hamstrings', 'quads']);
    expect(frente.equipment, 'Machine');
    expect(kExercises.where((e) => e.art == 'reverse-pendulum-hack-squat').map((e) => e.id), [_frente]);
  });

  test('Prensa hack keeps its v7 drawing, unchanged', () {
    expect(byId[_hack]?.art, 'pendulum-hack-squat');
    expect(kExercises.where((e) => e.art == 'pendulum-hack-squat').map((e) => e.id), [_hack]);
    final v7 = File('assets/art/pendulum-hack-squat.txt').readAsStringSync().replaceAll('\r\n', '\n');
    expect(v7.length, 157297);
    expect(_fnv1a(v7), 0x07229fb2);
  });

  test('Prensa hack de frente is a Spanish name only', () {
    final frente = byId[_frente]!;
    expect(kExerciseNameEs[_frente], 'Prensa hack de frente');
    expect(kGymNamedExercises, isNot(contains(_frente)));
    setAppLanguage('es');
    expect(exerciseName(frente), 'Prensa hack de frente');
    for (final code in appLanguages.where((code) => code != 'es')) {
      setAppLanguage(code);
      expect(exerciseName(frente), 'Reverse Pendulum Hack Squat', reason: code);
    }
  });
}
