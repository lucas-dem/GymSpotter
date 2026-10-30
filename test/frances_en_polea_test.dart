import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/catalog/exercise_catalog.dart';
import 'package:infyter/l10n/catalog_es.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/models/exercise.dart';

// Francés en polea (2IxROQ1) has its own high-pulley drawing and a gym name that only Spanish shows.
const _frances = '2IxROQ1';

// The exercises that keep the shared overhead drawing after Francés en polea moved to its own.
const _overheadArtKept = {'Gchi5Tr', 'Db7eEgw', 'Ser9eQp', '1xHyxys', 'Hx1WC8I', 's0HKO2I'};

void main() {
  tearDown(() => setAppLanguage('en'));
  final byId = {for (final e in kExercises) e.id: e};

  test('Francés en polea shows its own high-pulley drawing', () {
    expect(byId[_frances]?.art, 'high-pulley-overhead-tricep-extension');
  });

  test('the other exercises keep the shared overhead drawing', () {
    final users = kExercises.where((e) => e.art == 'overhead-tricep-extension').map((e) => e.id);
    expect(users.toSet(), _overheadArtKept);
    expect(kExerciseNameEs['1xHyxys'], 'Extensión de tríceps sobre la cabeza en polea alta');
  });

  test('Francés en polea is a Spanish name only', () {
    final frances = byId[_frances]!;
    expect(kExerciseNameEs[_frances], 'Francés en polea');
    expect(kGymNamedExercises, isNot(contains(_frances)));
    setAppLanguage('es');
    expect(exerciseName(frances), 'Francés en polea');
    setAppLanguage('en');
    expect(exerciseName(frances), 'Cable Overhead Triceps Extension (Rope Attachment)');
    setAppLanguage('it');
    expect(exerciseName(frances), 'Estensione tricipiti sopra la testa al cavo');
    setAppLanguage('zh');
    expect(exerciseName(frances), '绳索过头臂屈伸（绳索把手）');
    for (final code in appLanguages.where((code) => code != 'es')) {
      setAppLanguage(code);
      expect(exerciseName(frances), isNot('Francés en polea'), reason: code);
    }
  });
}
