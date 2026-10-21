import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/catalog/exercise_aliases.dart';
import 'package:infyter/catalog/exercise_catalog.dart';
import 'package:infyter/l10n/catalog_es.dart';
import 'package:infyter/models/exercise.dart';
import 'package:infyter/services/exercise_match.dart';

const _hevyNames = {
  'Bench Press (Barbell)': 'Barbell Bench Press',
  'Squat (Barbell)': 'Barbell Full Squat',
  'Deadlift (Barbell)': 'Barbell Deadlift',
  'Lat Pulldown (Cable)': 'Cable Pulldown',
  'Seated Row (Cable)': 'Cable Seated Row',
  'Overhead Press (Barbell)': 'Barbell Standing Wide Military Press',
  'Shoulder Press (Dumbbell)': 'Dumbbell Standing Overhead Press',
  'Lateral Raise (Dumbbell)': 'Dumbbell Lateral Raise',
  'Bicep Curl (Dumbbell)': 'Dumbbell Biceps Curl',
  'Hammer Curl (Dumbbell)': 'Dumbbell Hammer Curl',
  'Triceps Pushdown (Cable)': 'Cable Pushdown',
  'Skullcrusher (Barbell)': 'Barbell Lying Triceps Extension',
  'Romanian Deadlift (Barbell)': 'Barbell Romanian Deadlift',
  'Bulgarian Split Squat (Dumbbell)': 'Dumbbell Single Leg Split Squat',
  'Chest Fly (Machine)': 'Fly Deck Chest',
  'Chest Press (Machine)': 'Lever Standing Chest Press',
  'T Bar Row': 'Lever T Bar Row',
  'Hip Abduction (Machine)': 'Hip Abduction Machine',
  'Leg Curl (Machine)': 'Seated Leg Curl',
  'Farmers Walk': 'Kettlebell Farmer Carry',
};

const _requestedSpanishNames = {
  'EIeI8Vf': 'Press plano',
  'ns0SIbU': 'Press inclinado con mancuernas',
  'pec-deck': 'Fly deck para pecho',
  '25GPyDY': 'Bíceps con barra',
  'incline-dumbbell-curl': 'Bíceps en banco inclinado',
  'RVwzP10': 'Jalón al pecho',
  'fUBheHs': 'Remo dorsalera baja',
  'aaXr7ld': 'Remo T',
  'rope-tricep-pushdown': 'Tríceps con soga',
  'cable-pullover': 'Pull-over en polea',
  '9WTm7dq': 'Fondos',
  'TFqbd8t': 'Crunches',
  'abs-crunches-bench': 'Abs crunches',
  'pendulum-hack-squat': 'Prensa hack',
  'machine-leg-press': 'Prensa 45°',
  'leg-extension': 'Sillón de cuádriceps',
  'machine-lying-leg-curl': 'Camilla de isquios',
  'static-lunge': 'Estocadas estáticas',
  'hip-thrust': 'Hip thrust',
  'ila4NZS': 'Peso muerto',
  '9E25EOx': 'Búlgara',
  'seated-leg-curl': 'Femoral sentado',
  'dead-bug': 'Bicho muerto',
  'box-step-up': 'Subidas al cajón',
  'DsgkuIt': 'Vuelos laterales',
  '3eGE2JC': 'Vuelos frontales',
  'plank-hold': 'Planchas frontales',
  'flat-converging-chest-press': 'Convergente plano',
  'incline-converging-chest-press': 'Convergente inclinado',
  'alternating-dumbbell-curl': 'Bíceps alternados',
  'reverse-grip-lat-pulldown': 'Jalón invertido',
  'ykUOVze': 'Gemelos',
};

List<Exercise> _search(String query) => kExercises.where(exerciseSearch(query)).toList();

void main() {
  final byName = {for (final e in kExercises) e.name: e};

  test('every alias belongs to an exercise in the catalog', () {
    final orphans = kExerciseAliases.keys.where((name) => !byName.containsKey(name));
    expect(orphans, isEmpty);
  });

  test('the requested routine names are the visible Spanish catalog names', () {
    for (final entry in _requestedSpanishNames.entries) {
      expect(kExerciseNameEs[entry.key], entry.value);
    }
    expect(kExerciseAliases['Bench Supported Abs Crunch'], contains('Abs Crunches'));
    expect(kExerciseAliases['Leg Extension'], contains('Sillón de cuádriceps (descenso)'));
    expect(byName['Bench Supported Abs Crunch']?.art, 'crunch');
    expect(byName['Pendulum Hack Squat']?.art, 'hack-squat');
    expect(byName['Flat Converging Chest Press']?.art, 'machine-chest-press');
    expect(byName['Incline Converging Chest Press']?.art, 'incline-chest-press');
    expect(byName['Static Lunge']?.art, 'split-squat');
  });

  test('no two exercises claim the same alias', () {
    final owners = <String, String>{};
    final clashes = <String>[];
    for (final entry in kExerciseAliases.entries) {
      for (final alias in entry.value) {
        final owner = owners.putIfAbsent(searchKey(alias), () => entry.key);
        if (owner != entry.key) clashes.add('$alias: $owner / ${entry.key}');
      }
    }
    expect(clashes, isEmpty);
  });

  test('searching a name from another app finds the exercise', () {
    for (final entry in _hevyNames.entries) {
      expect(
        _search(entry.key).map((e) => e.name),
        contains(entry.value),
        reason: 'searching "${entry.key}" should find ${entry.value}',
      );
    }
  });

  test('importing a name from another app maps to the same exercise', () {
    for (final entry in _hevyNames.entries) {
      expect(matchExercise(entry.key, kExercises)?.name, entry.value);
    }
  });

  test('a half-typed name still narrows down to the exercise', () {
    expect(_search('lat pulld').map((e) => e.name), contains('Cable Pulldown'));
    expect(_search('db bench').map((e) => e.name), contains('Dumbbell Bench Press'));
    expect(_search('bulgarian split').map((e) => e.name), contains('Dumbbell Single Leg Split Squat'));
  });

  test('the plain catalog name still wins on its own', () {
    expect(_search('Barbell Bench Press').map((e) => e.name), contains('Barbell Bench Press'));
    expect(_search('pec deck').map((e) => e.name), contains('Fly Deck Chest'));
    expect(_search('fly deck').map((e) => e.name), containsAll(['Fly Deck Chest', 'Fly Deck Rear Delts']));
    expect(_search('convergente plano').single.name, 'Flat Converging Chest Press');
    expect(_search('convergente inclinado').single.name, 'Incline Converging Chest Press');
  });

  test('the names an AI writes land on a real exercise', () {
    const written = [
      'Bench Press',
      'Squat',
      'Deadlift',
      'Overhead Press',
      'Barbell Row',
      'Lat Pulldown',
      'Bicep Curl',
      'Tricep Pushdown',
      'Leg Press',
      'Romanian Deadlift',
      'Plank',
      'Face Pull',
      'Pull-ups',
      'Push-ups',
      'Dumbbell Shoulder Press',
      'Incline Bench Press',
      'Leg Curl',
      'Calf Raises',
      'Lateral Raises',
      'Hip Thrust',
      'Cable Fly',
      'Seated Row',
      'Hammer Curls',
      'Skull Crushers',
      'Bulgarian Split Squat',
      'Goblet Squat',
      'Russian Twist',
      'Mountain Climbers',
    ];
    final missed = [
      for (final n in written)
        if (matchExercise(n, kExercises) == null) n,
    ];
    expect(missed, isEmpty, reason: 'sin emparejar: ${missed.join(", ")}');
  });

  test('the order of the words does not matter for an alias', () {
    expect(matchExercise('Dumbbell Shoulder Press', kExercises)?.name, 'Dumbbell Standing Overhead Press');
    expect(matchExercise('Shoulder Press (Dumbbell)', kExercises)?.name, 'Dumbbell Standing Overhead Press');
  });

  test('an empty search keeps the whole catalog', () {
    expect(_search('   ').length, kExercises.length);
  });
}
