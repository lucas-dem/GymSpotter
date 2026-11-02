/// Catalog exercises the app no longer offers.
///
/// They stay in `kExercises` with their id, name, steps and drawing, so the routines, history, backups and imports
/// that already use them keep loading and showing them. The app only stops listing, searching and suggesting them:
/// lists the person picks from use `listedExercises`, while anything that resolves saved data keeps `exerciseById`
/// and `matchExerciseByName`.
const Set<String> kHiddenExercises = {
  '5VCj6iH', // Barbell Hack Squat (Sentadilla hack con barra); its drawing is shared with ZuPXtCK.
};
