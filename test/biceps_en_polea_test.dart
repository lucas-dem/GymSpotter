import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/catalog/exercise_aliases.dart';
import 'package:infyter/catalog/exercise_catalog.dart';
import 'package:infyter/l10n/catalog_es.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/models/exercise.dart';
import 'package:infyter/services/exercise_match.dart';

// Bíceps en polea (G08RZcQ): the cable curl with a straight bar, as Lucas confirmed. It keeps the
// cable-curl drawing, has a gym name that only Spanish shows and a search alias with that name.
const _biceps = 'G08RZcQ';
const _gymName = 'Bíceps en polea';

// Its Spanish name up to 1.3.1, kept only as a search alias: no language shows it as the name.
const _oldName = 'Curl de bíceps en polea';

void main() {
  tearDown(() => setAppLanguage('en'));
  final byId = {for (final e in kExercises) e.id: e};

  test('Bíceps en polea shows the cable curl drawing', () {
    expect(byId[_biceps]?.art, 'cable-curl');
  });

  test('Bíceps en polea is a Spanish name only', () {
    final biceps = byId[_biceps]!;
    expect(kExerciseNameEs[_biceps], _gymName);
    expect(kGymNamedExercises, isNot(contains(_biceps)));
    setAppLanguage('es');
    expect(exerciseName(biceps), _gymName);
    setAppLanguage('en');
    expect(exerciseName(biceps), 'Cable Curl');
    for (final code in appLanguages.where((code) => code != 'es')) {
      setAppLanguage(code);
      expect(exerciseName(biceps), isNot(_gymName), reason: code);
    }
  });

  test('searching or importing "Bíceps en polea" finds it in any language', () {
    expect(kExerciseAliases['Cable Curl'], contains(_gymName));
    for (final code in appLanguages) {
      setAppLanguage(code);
      expect(kExercises.where(exerciseSearch(_gymName)).map((e) => e.id), [_biceps], reason: code);
      expect(matchExercise(_gymName, kExercises)?.id, _biceps, reason: code);
    }
  });

  test('searching or importing its old name "Curl de bíceps en polea" still finds it', () {
    final biceps = byId[_biceps]!;
    expect(kExerciseAliases['Cable Curl'], contains(_oldName));
    for (final code in appLanguages) {
      setAppLanguage(code);
      expect(kExercises.where(exerciseSearch(_oldName)).map((e) => e.id), [_biceps], reason: code);
      expect(matchExercise(_oldName, kExercises)?.id, _biceps, reason: code);
      expect(exerciseName(biceps), isNot(_oldName), reason: code);
    }
  });
}
