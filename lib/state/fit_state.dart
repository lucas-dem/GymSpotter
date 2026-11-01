import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../catalog/exercise_catalog.dart';
import '../catalog/program_templates.dart';
import '../l10n/l10n.dart';
import '../models/exercise.dart';
import '../models/live_session.dart';
import '../models/measure.dart';
import '../models/note.dart';
import '../models/place.dart';
import '../models/profile.dart';
import '../models/progress_shot.dart';
import '../models/workout.dart';
import '../services/alarm_store.dart';
import '../services/beeper.dart';
import '../services/exercise_match.dart';
import '../services/local_store.dart';
import '../services/media_store.dart';
import '../services/progress_reminder.dart';
import '../services/plan_share.dart';
import '../services/rest_alarm.dart';
import '../services/train_reminder.dart';
import '../services/workout_import.dart';

part 'awards_state.dart';
part 'fit_core.dart';
part 'library_state.dart';
part 'measures_state.dart';
part 'moments_state.dart';
part 'notes_state.dart';
part 'places_state.dart';
part 'routines_state.dart';
part 'settings_state.dart';
part 'stats_state.dart';
part 'timeline_state.dart';
part 'tools_state.dart';
part 'workout_state.dart';

class FitState extends FitCore
    with
        ToolsState,
        LibraryState,
        SettingsState,
        NotesState,
        PlacesState,
        MeasuresState,
        MomentsState,
        TimelineState,
        StatsState,
        AwardsState,
        RoutinesState,
        WorkoutState {
  /// Nunca lanza: un error acá cortaba main() antes de runApp en cada arranque.
  /// La carga es tolerante: lo que no se puede leer se saltea y el resto se
  /// carga. Si se salteó algo o la carga falla, el crudo queda copiado ANTES de
  /// habilitar guardados (`_loading` sigue en true hasta después de la copia).
  void loadFromStore() {
    try {
      _loadFrom(Store.instance.load(), onSkipped: () => Store.instance.preserveStored('itemsSkipped'));
    } catch (error) {
      Store.instance.preserveStored('loadFailed', error: error);
      _loading = false;
      try {
        _finishLoad();
      } catch (_) {
        notifyListeners();
      }
    }
    try {
      _rescueOffer = _hasOwnRecords ? null : Store.instance.rescueOffer;
      _rescueSaved = Store.instance.rescueSaved;
    } catch (_) {
      _rescueOffer = null;
      _rescueSaved = null;
    }
    if (_rescueOffer != null || _rescueSaved != null) notifyListeners();
  }

  /// [onSkipped] corre si se salteó algo, todavía con `_loading` en true.
  void _loadFrom(Map<String, dynamic> data, {VoidCallback? onSkipped}) {
    _loading = true;
    _skippedOnLoad = 0;
    if (data['language'] == null) _applyLanguage('es');
    if (data.isNotEmpty) {
      _part(() {
        profile = Profile.fromJson((data['profile'] as Map?)?.cast<String, dynamic>() ?? {});
        if (const {'Athlete', 'Atleta', 'Name'}.contains(profile.name)) {
          profile.name = kDefaultName;
        }
      });

      themePref = _themeFrom(data, fallback: 'dark');
      units = _pick(data['units'], 'kg');

      _applyLanguage(_pickOrNull<String>(data['language']) ?? language);
      restSeconds = _pick<num>(data['rest'], 90).toInt();
      alarmSound = _pickOrNull<String>(data['alarmSound']);
      alarmSoundName = _pickOrNull<String>(data['alarmSoundName']);
      RestAlarm.instance.customSoundPath = alarmSoundPath;

      if (alarmSoundPath == null) {
        alarmSound = null;
        alarmSoundName = null;
      }
      gymBranch = SettingsState.gymBranches.contains(data['gymBranch'])
          ? data['gymBranch'] as String
          : 'junin';
      final storedBg = _pick(data['bg'], 'dynamic');
      bgPattern = storedBg == 'gym'
          ? 'dynamic'
          : SettingsState.bgPatterns.contains(storedBg)
          ? storedBg
          : 'dynamic';
      if (!branchBackgrounds.contains(bgPattern) &&
          !const ['none', 'dynamic', 'dots', 'grid', 'photo'].contains(bgPattern)) {
        bgPattern = 'dynamic';
      }
      heatTone = _pick(data['heatTone'], 'ember');
      _part(() => _loadToggles(data));
      alarmAskedAt = _pickOrNull<num>(data['alarmAskedAt'])?.toInt();
      onboarded = _pick(data['onboarded'], false);
      favorites
        ..clear()
        ..addAll(_entries(data['favorites'], (k, v) => MapEntry(k as String, v as bool)));
      _part(() => _loadNotes(data));
      _part(() => _loadPlaces(data));
      checkins
        ..clear()
        ..addAll(_strings(data['checkins']));
      routines
        ..clear()
        ..addAll(_items(data['routines'], Routine.fromJson));
      weeklyPlan
        ..clear()
        ..addAll(_entries(data['weeklyPlan'], (k, v) => MapEntry(int.parse(k as String), v as String)));
      _part(() => _loadAthletes(data));
      customExercises
        ..clear()
        ..addAll(_items(data['custom'], Exercise.fromJson));
      _part(() => _loadMedia(data));
      _part(() => _loadRepsOnly(data));
      _part(() => _loadExerciseRest(data));
      sessions
        ..clear()
        ..addAll(_items(data['sessions'], LoggedSession.fromJson));
      bodyweight
        ..clear()
        ..addAll(_items(data['bodyweight'], BodyweightEntry.fromJson));
      _part(() => _loadMeasures(data));
      _part(() => _loadShots(data));
      awards
        ..clear()
        ..addAll(
          _entries(
            data['awards'],
            (k, v) => MapEntry(k as String, DateTime.tryParse(v as String? ?? '') ?? DateTime.now()),
          ),
        );
      awardsSeen
        ..clear()
        ..addAll(_strings(data['awardsSeen']));
      moments
        ..clear()
        ..addAll(_items(data['moments'], Moment.fromJson));
      photoIntervalDays = _pick<num>(data['photoEvery'], 30).toInt();
      bodyTimeline = _pick(data['bodyTl'], false);
      _part(() => _restoreLiveSession(data));
    }
    if (_skippedOnLoad > 0) onSkipped?.call();
    _finishLoad();
  }

  // Carga tolerante (sesión 26): al leer el almacén, lo que no se puede leer se
  // saltea y se cuenta, y el resto se carga igual. Importar un backup es
  // estricto (`_strictLoad`): el primer error hace que applyBackup vuelva atrás.
  bool _strictLoad = false;
  int _skippedOnLoad = 0;

  /// Corre [body]; si falla y la carga es tolerante, lo cuenta y sigue.
  void _part(void Function() body) {
    try {
      body();
    } catch (_) {
      if (_strictLoad) rethrow;
      _skippedOnLoad++;
    }
  }

  void _skipped(String what) {
    if (_strictLoad) throw FormatException('tipo inesperado: $what');
    _skippedOnLoad++;
  }

  /// Los elementos de la lista [raw] que [parse] puede leer; cada uno que
  /// falla se saltea y se cuenta.
  List<T> _each<T>(Object? raw, T Function(Object? item) parse) {
    final out = <T>[];
    if (raw == null) return out;
    if (raw is! List) {
      _skipped('lista');
      return out;
    }
    for (final item in raw) {
      try {
        out.add(parse(item));
      } catch (_) {
        if (_strictLoad) rethrow;
        _skippedOnLoad++;
      }
    }
    return out;
  }

  List<T> _items<T>(Object? raw, T Function(Map<String, dynamic> json) parse) =>
      _each(raw, (item) => parse((item as Map).cast<String, dynamic>()));

  List<String> _strings(Object? raw) => _each(raw, (item) => item as String);

  /// Las entradas del mapa [raw] que [parse] puede leer (`null` = se ignora sin
  /// contarla); cada una que falla se saltea y se cuenta.
  Map<K, V> _entries<K, V>(Object? raw, MapEntry<K, V>? Function(Object? key, Object? value) parse) {
    final out = <K, V>{};
    if (raw == null) return out;
    if (raw is! Map) {
      _skipped('mapa');
      return out;
    }
    raw.forEach((key, value) {
      try {
        final entry = parse(key, value);
        if (entry != null) out[entry.key] = entry.value;
      } catch (_) {
        if (_strictLoad) rethrow;
        _skippedOnLoad++;
      }
    });
    return out;
  }

  /// [value] si es un [T]; si falta, [fallback]; con otro tipo se cuenta (o
  /// falla, si la carga es estricta) y vale [fallback].
  T _pick<T extends Object>(Object? value, T fallback) => _pickOrNull<T>(value) ?? fallback;

  T? _pickOrNull<T extends Object>(Object? value) {
    if (value == null) return null;
    if (value is T) return value;
    _skipped('$T');
    return null;
  }

  void _finishLoad() {
    _stampMemberSince();
    _seedCalculatorsFromProfile();
    _loading = false;
    refreshAwards(silent: true);
    pendingAwards.clear();
    if (gamification) pendingAwards.addAll(unseenAwards);
    notifyListeners();
  }

  void _stampMemberSince() {
    if (profile.since != null) return;
    var first = DateTime.now();
    for (final s in sessions) {
      if (s.date.isBefore(first)) first = s.date;
    }
    profile.since = DateTime(first.year, first.month, first.day);
  }

  static String _themeFrom(Map<String, dynamic> data, {required String fallback}) {
    final pref = data['theme'];
    if (pref is String && const ['system', 'dark', 'light'].contains(pref)) return pref;
    final dark = data['dark'];
    if (dark is bool) return dark ? 'dark' : 'light';
    return fallback;
  }

  void _loadToggles(Map<String, dynamic> data) {
    demoSize = _pick(data['demo'], 'large');
    alarmStyle = _pick(data['alarmStyle'], 'quiet');
    RestAlarm.instance.style = alarmStyle;
    noSuggest
      ..clear()
      ..addAll(_strings(data['noSuggest']));
    modeOverride
      ..clear()
      ..addAll(
        _entries(data['exMode'], (k, v) => MapEntry(k as String, v as String))
          ..removeWhere((_, v) => !const ['weight', 'cardio', 'time'].contains(v)),
      );
    bgDim = _pick<num>(data['bgDim'], 0.55).toDouble();
    showFocus = _pick(data['showFocus'], true);
    autoAdvance = _pick(data['autoAdvance'], true);
    keepScreenOn = _pick(data['keepAwake'], true);
    startCountdown = _pick(data['countdown'], true);
    gamification = _pick(data['gamify'], true);
    logRpe = _pick(data['rpe'], false);
    effortScale = data['effort'] == 'rir' ? 'rir' : 'rpe';
    trainReminderMin = _pickOrNull<num>(data['trainAt'])?.toInt();
    smartReminder = _pick(data['trainSmart'], false);
    trainerMode = _pick(data['trainerMode'], false);
    progressStep
      ..clear()
      ..addAll(_entries(data['progress'], (k, v) => MapEntry(k as String, (v as num).toDouble())));
    autoWarmup
      ..clear()
      ..addAll(_strings(data['warmup']));
  }

  void _loadAthletes(Map<String, dynamic> data) {
    athletes
      ..clear()
      ..addAll(_items(data['athletes'], Athlete.fromJson).where((a) => a.name.isNotEmpty));
    athleteWeeklyPlans
      ..clear()
      ..addAll(
        _entries(data['athleteWeeklyPlans'], (key, value) {
          if (key is! String || value is! Map) return null;
          return MapEntry(
            key,
            _entries(value, (day, routine) => MapEntry(int.parse(day as String), routine as String)),
          );
        }),
      );
  }

  void _restoreLiveSession(Map<String, dynamic> data) {
    final live = data['live'] as Map?;
    if (live == null) return;
    session = WorkoutSession.fromJson(live.cast<String, dynamic>());
    _elapsedBefore = (data['liveElapsed'] as num?)?.toInt() ?? 0;
    sessionPaused = data['livePaused'] as bool? ?? false;
    final started = data['liveStart'] as String?;
    if (sessionPaused || started == null) {
      _runningSince = null;
    } else {
      _runningSince = DateTime.tryParse(started);
      _startTicking(from: _runningSince);
    }
    if (!sessionPaused) syncRest();
    resetRoute('session');
  }

  void _loadMedia(Map<String, dynamic> data, {Map<String, String>? restored}) {
    exerciseMedia.clear();
    if (restored != null) {
      exerciseMedia.addAll(restored);
      return;
    }
    exerciseMedia.addAll(
      _entries(data['media'], (k, v) => k is String && v is String && v.isNotEmpty ? MapEntry(k, v) : null),
    );
    for (final e in (data['custom'] as List?) ?? const []) {
      if (e is! Map) continue; // ya contado al cargar los ejercicios propios
      final legacy = e['m'];
      final id = e['id'];
      if (id is String && legacy is String && legacy.isNotEmpty) {
        exerciseMedia.putIfAbsent(id, () => legacy);
      }
    }
  }

  void _loadExerciseRest(Map<String, dynamic> data) {
    exerciseRest
      ..clear()
      ..addAll(
        _entries(data['exRest'], (k, v) {
          final n = (v as num?)?.toInt();
          return k is String && n != null ? MapEntry(k, n.clamp(15, 600)) : null;
        }),
      );
  }

  void _loadRepsOnly(Map<String, dynamic> data) {
    repsOnly
      ..clear()
      ..addAll(_strings(data['repsOnly']));
    repsOnlyOff
      ..clear()
      ..addAll(_strings(data['repsOnlyOff']));
  }

  void _loadShots(Map<String, dynamic> data, {Map<String, String>? restored}) {
    shots
      ..clear()
      ..addAll(_items(data['shots'], ProgressEntry.fromJson).where((e) => !e.isEmpty));
    if (restored == null) return;
    for (var i = 0; i < shots.length; i++) {
      final e = shots[i];
      final kept = <String, String>{};
      e.shots.forEach((pose, name) {
        final now = restored[name];
        if (now != null) kept[pose] = now;
      });
      shots[i] = e.copyWith(shots: kept);
    }
    shots.removeWhere((e) => e.isEmpty);
  }

  void _loadMeasures(Map<String, dynamic> data) {
    measures
      ..clear()
      ..addAll(_items(data['measures'], BodyMeasure.fromJson).where((m) => kMeasureKeys.contains(m.key)));
  }

  void _loadPlaces(Map<String, dynamic> data) {
    places.clear();
    final raw = data['places'];
    if (raw is List) places.addAll(_items(raw, GymPlace.fromJson));
    activePlaceId = _pick(data['place'], '');
    if (places.every((p) => p.id != activePlaceId)) activePlaceId = '';
  }

  void _loadNotes(Map<String, dynamic> data) {
    notes.clear();
    final raw = data['notes'];
    if (raw is List) {
      notes.addAll(_items(raw, GymNote.fromJson));
      return;
    }

    var seq = 0;
    GymNote legacy(String exId, DateTime when, String text) => GymNote(
      id: 'n${when.microsecondsSinceEpoch}${seq++}',
      exerciseId: exId,
      date: _dayKey(when),
      kind: NoteKind.note,
      text: text,
      createdAt: when,
    );

    (data['exNotes'] as Map?)?.forEach((k, v) {
      for (final m in _items(v, (m) => m)) {
        _part(() {
          final text = ((m['t'] ?? '') as String).trim();
          if (text.isEmpty) return;
          notes.add(legacy(k as String, DateTime.tryParse((m['d'] ?? '') as String) ?? DateTime.now(), text));
        });
      }
    });
    if (raw is Map) {
      raw.forEach((k, v) {
        _part(() {
          final text = (v as String).trim();
          if (text.isNotEmpty) notes.add(legacy(k as String, DateTime.now(), text));
        });
      });
    }
  }

  @override
  Map<String, dynamic> toJson() => {
    'profile': profile.toJson(),
    'dark': dark,
    'theme': themePref,
    'units': units,
    'language': language,
    'rest': restSeconds,
    'alarmSound': alarmSound,
    'alarmSoundName': alarmSoundName,
    'bg': bgPattern,
    'gymBranch': gymBranch,
    'heatTone': heatTone,
    'bgDim': bgDim,
    'showFocus': showFocus,
    'autoAdvance': autoAdvance,
    'keepAwake': keepScreenOn,
    'countdown': startCountdown,
    'gamify': gamification,
    'rpe': logRpe,
    'effort': effortScale,
    'demo': demoSize,
    'alarmStyle': alarmStyle,
    'noSuggest': noSuggest.toList(),
    'exMode': modeOverride,
    'trainAt': trainReminderMin,
    'trainSmart': smartReminder,
    'trainerMode': trainerMode,
    'alarmAskedAt': alarmAskedAt,
    'onboarded': onboarded,
    'favorites': favorites,
    'notes': notes.map((n) => n.toJson()).toList(),
    'places': places.map((p) => p.toJson()).toList(),
    'place': activePlaceId,
    'checkins': checkins.toList(),
    'routines': routines.map((r) => r.toJson()).toList(),
    'weeklyPlan': weeklyPlan.map((k, v) => MapEntry(k.toString(), v)),
    'athletes': athletes.map((a) => a.toJson()).toList(),
    'athleteWeeklyPlans': athleteWeeklyPlans.map(
      (id, plan) => MapEntry(id, plan.map((day, routine) => MapEntry(day.toString(), routine))),
    ),
    'custom': customExercises.map((e) => e.toJson()).toList(),
    'media': exerciseMedia,
    'exRest': exerciseRest,
    'progress': progressStep,
    'warmup': autoWarmup.toList(),
    'repsOnly': repsOnly.toList(),
    'repsOnlyOff': repsOnlyOff.toList(),
    'sessions': sessions.map((s) => s.toJson()).toList(),
    'bodyweight': bodyweight.map((b) => b.toJson()).toList(),
    'measures': measures.map((m) => m.toJson()).toList(),
    'shots': shots.map((s) => s.toJson()).toList(),
    'awards': awards.map((k, v) => MapEntry(k, v.toIso8601String())),
    'awardsSeen': awardsSeen.toList(),
    'moments': moments.map((m) => m.toJson()).toList(),
    'photoEvery': photoIntervalDays,
    'bodyTl': bodyTimeline,
    if (session != null && !session!.complete) ...{
      'live': session!.toJson(),
      'liveStart': _runningSince?.toIso8601String(),
      'liveElapsed': _elapsedBefore,
      'livePaused': sessionPaused,
    },
  };

  // Copia de rescate para ofrecer en el inicio (ver Store.rescueOffer). Se
  // calcula al cargar: el getter de Store lee y decodifica copias.
  String? _rescueOffer;

  /// Copia de rescate que se puede restaurar, o `null`. No se ofrece con un
  /// entrenamiento abierto ni cuando ya hay datos propios cargados después del
  /// incidente: restaurar los reemplazaría.
  String? get rescueOffer => session == null && !_hasOwnRecords ? _rescueOffer : null;

  // Copia guardada tras datos que no se pudieron abrir, cuando no había ninguna
  // para restaurar (ver Store.rescueSaved). Se calcula al cargar.
  String? _rescueSaved;

  /// Copia guardada de los datos que no se pudieron abrir, cuando no hay ninguna
  /// que restaurar: el inicio solo avisa que quedó guardada. Como no reemplaza
  /// nada, sigue aunque ya haya datos nuevos, hasta que la persona lo cierre.
  String? get rescueSaved => _rescueSaved;

  // Lo que la persona registra y una restauración reemplazaría. La bienvenida
  // solo crea el perfil y los lugares.
  bool get _hasOwnRecords =>
      sessions.isNotEmpty ||
      routines.isNotEmpty ||
      bodyweight.isNotEmpty ||
      notes.isNotEmpty ||
      measures.isNotEmpty ||
      shots.isNotEmpty ||
      moments.isNotEmpty ||
      customExercises.isNotEmpty;

  /// Restaura [rescueOffer]. Antes guarda el estado actual como otra copia de
  /// rescate. Si la copia ya no se puede cargar devuelve false y no cambia nada.
  bool restoreRescue() {
    final slot = rescueOffer;
    if (slot == null) return false;
    final data = Store.instance.decodeRescueCopy(slot);
    if (data == null) return false;
    final before = backupSnapshot();
    Store.instance.keepCopy(before);
    try {
      // Sin el entrenamiento en curso que tuviera la copia: retomarlo
      // reiniciaría timers y la ruta con un entrenamiento viejo.
      _loadFrom(data..removeWhere((key, _) => _liveKeys.contains(key)));
    } catch (_) {
      _loadFrom(before);
      return false;
    }
    Store.instance.markRescueHandled(slot);
    _rescueOffer = null;
    persistNow();
    _refreshWidgets();
    notifyListeners();
    return true;
  }

  /// Cierra el aviso (el que ofrece restaurar o el que avisa que se guardó una
  /// copia) sin borrar ninguna copia.
  void dismissRescue() {
    final slot = _rescueOffer ?? _rescueSaved;
    if (slot == null) return;
    Store.instance.markRescueHandled(slot);
    _rescueOffer = null;
    _rescueSaved = null;
    notifyListeners();
  }

  void resetAllData() {
    _saveDebounce?.cancel();
    _sessionTimer?.cancel();
    _restTimer?.cancel();
    RestAlarm.instance.cancel();
    ProgressReminder.instance.cancel();
    session = null;
    _runningSince = null;
    _elapsedBefore = 0;
    sessionPaused = false;
    sessions.clear();
    bodyweight.clear();
    measures.clear();
    shots.clear();
    compareFromId = null;
    compareToId = null;
    notes.clear();
    moments.clear();
    awards.clear();
    awardsSeen.clear();
    pendingAwards.clear();
    places.clear();
    activePlaceId = '';
    checkins.clear();
    routines.clear();
    weeklyPlan.clear();
    athletes.clear();
    athleteWeeklyPlans.clear();
    trainerMode = false;
    activeAthleteId = 'me';
    customExercises.clear();
    exerciseMedia.clear();
    repsOnly.clear();
    repsOnlyOff.clear();
    exerciseRest.clear();
    progressStep.clear();
    autoWarmup.clear();
    noSuggest.clear();
    modeOverride.clear();
    demoSize = 'large';
    gymBranch = 'junin';
    bgPattern = 'dynamic';
    bgDim = 0.55;
    MediaStore.clearAll();
    Store.instance.discardRescue();
    _rescueOffer = null;
    _rescueSaved = null;
    favorites.clear();
    sessionPicks.clear();
    selectedMuscles.clear();
    profile = Profile();
    showFocus = true;
    autoAdvance = true;
    startCountdown = true;
    gamification = true;
    logRpe = false;
    effortScale = 'rpe';
    trainReminderMin = null;
    smartReminder = false;
    TrainReminder.instance.cancel();
    onboarded = false;
    strengthExerciseId = null;
    _photoBytes = null;
    _photoCacheKey = null;
    _bannerBytes = null;
    _bannerCacheKey = null;
    _seedCalculatorsFromProfile();
    resetRoute('home');
    trainStep = 'select';
    persistNow();
    _refreshWidgets();
    notifyListeners();
  }

  String exportJson() => Store.instance.exportJson(toJson());

  String exportCsv() => Store.instance.exportCsv(sessions);

  bool importJson(String raw) {
    final map = Store.instance.tryParse(raw);
    if (map == null) return false;
    try {
      applyBackup(map);
    } catch (_) {
      return false;
    }
    return true;
  }

  /// Si el backup trae un tipo inesperado, vuelve al estado de antes sin
  /// guardar nada y relanza. Antes quedaba aplicado a medias y con `_loading`
  /// en true: la app dejaba de guardar hasta que se reiniciara. Con
  /// [endRescue] en false, el aviso de rescate se cierra después, con
  /// [endRescueNotice], cuando lo importado ya quedó guardado.
  void applyBackup(
    Map<String, dynamic> map, {
    Map<String, String>? restoredMedia,
    Map<String, String>? restoredNoteMedia,
    Map<String, String>? restoredShots,
    Map<String, String>? restoredMoments,
    bool endRescue = true,
  }) {
    final before = backupSnapshot();
    try {
      _strictLoad = true;
      _applyBackup(
        map,
        restoredMedia: restoredMedia,
        restoredNoteMedia: restoredNoteMedia,
        restoredShots: restoredShots,
        restoredMoments: restoredMoments,
      );
    } catch (_) {
      _strictLoad = false;
      _loadFrom(before);
      rethrow;
    } finally {
      _strictLoad = false;
    }
    if (endRescue) endRescueNotice();
  }

  /// Lo importado reemplazó lo que había: el aviso de rescate ya no se muestra.
  void endRescueNotice() {
    final offered = _rescueOffer ?? _rescueSaved;
    if (offered == null) return;
    Store.instance.markRescueHandled(offered);
    _rescueOffer = null;
    _rescueSaved = null;
    notifyListeners();
  }

  static const _liveKeys = {'live', 'liveStart', 'liveElapsed', 'livePaused'};

  /// El estado actual, para volver a él con [restoreSnapshot]. Copia profunda:
  /// toJson() comparte mapas vivos (favoritos, medios, descansos) que
  /// _applyBackup vacía. Sin el entrenamiento en curso: un backup no lo toca y
  /// restaurarlo reiniciaría sus timers y la ruta.
  Map<String, dynamic> backupSnapshot() =>
      (jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>)
        ..removeWhere((key, _) => _liveKeys.contains(key));

  /// Vuelve al estado [before] de [backupSnapshot] (si un backup ya aplicado no
  /// se pudo guardar) y lo vuelve a guardar.
  void restoreSnapshot(Map<String, dynamic> before) {
    _loadFrom(before);
    persistNow();
    _refreshWidgets();
  }

  /// Guarda ya y dice si quedó guardado. Cancela el guardado diferido: si no,
  /// podría escribir después lo que este guardado no pudo.
  Future<bool> saveNow() {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    return Store.instance.save(toJson());
  }

  void _applyBackup(
    Map<String, dynamic> map, {
    Map<String, String>? restoredMedia,
    Map<String, String>? restoredNoteMedia,
    Map<String, String>? restoredShots,
    Map<String, String>? restoredMoments,
  }) {
    _loading = true;
    profile = Profile.fromJson((map['profile'] as Map?)?.cast<String, dynamic>() ?? {});
    themePref = _themeFrom(map, fallback: themePref);
    units = map['units'] as String? ?? units;
    _applyLanguage(map['language'] as String? ?? language);
    restSeconds = (map['rest'] as num?)?.toInt() ?? restSeconds;
    gymBranch = SettingsState.gymBranches.contains(map['gymBranch']) ? map['gymBranch'] as String : gymBranch;
    final restoredBg = map['bg'] as String? ?? bgPattern;
    bgPattern = restoredBg == 'gym'
        ? 'dynamic'
        : SettingsState.bgPatterns.contains(restoredBg)
        ? restoredBg
        : 'dynamic';
    if (!branchBackgrounds.contains(bgPattern) &&
        !const ['none', 'dynamic', 'dots', 'grid', 'photo'].contains(bgPattern)) {
      bgPattern = 'dynamic';
    }
    _loadToggles(map);
    onboarded = map['onboarded'] as bool? ?? onboarded;
    favorites
      ..clear()
      ..addAll(((map['favorites'] as Map?) ?? {}).map((k, v) => MapEntry(k as String, v as bool)));
    _loadPlaces(map);
    _loadNotes(map);
    if (restoredNoteMedia != null) _remapNoteMedia(restoredNoteMedia);
    checkins
      ..clear()
      ..addAll(((map['checkins'] as List?) ?? []).cast<String>());
    routines
      ..clear()
      ..addAll(
        ((map['routines'] as List?) ?? []).map((e) => Routine.fromJson((e as Map).cast<String, dynamic>())),
      );
    weeklyPlan
      ..clear()
      ..addAll(
        ((map['weeklyPlan'] as Map?) ?? {}).map((k, v) => MapEntry(int.parse(k as String), v as String)),
      );
    _loadAthletes(map);
    customExercises
      ..clear()
      ..addAll(
        ((map['custom'] as List?) ?? []).map((e) => Exercise.fromJson((e as Map).cast<String, dynamic>())),
      );
    _loadMedia(map, restored: restoredMedia);
    _loadRepsOnly(map);
    _loadExerciseRest(map);
    sessions
      ..clear()
      ..addAll(
        ((map['sessions'] as List?) ?? []).map(
          (e) => LoggedSession.fromJson((e as Map).cast<String, dynamic>()),
        ),
      );
    bodyweight
      ..clear()
      ..addAll(
        ((map['bodyweight'] as List?) ?? []).map(
          (e) => BodyweightEntry.fromJson((e as Map).cast<String, dynamic>()),
        ),
      );
    _loadMeasures(map);
    _loadShots(map, restored: restoredShots);
    _loadAwards(map);
    _loadMoments(map, restored: restoredMoments);
    photoIntervalDays = (map['photoEvery'] as num?)?.toInt() ?? photoIntervalDays;
    bodyTimeline = map['bodyTl'] as bool? ?? bodyTimeline;
    _seedCalculatorsFromProfile();
    _loading = false;
    _persist();
    _refreshWidgets();
    notifyListeners();
  }

  void _loadAwards(Map<String, dynamic> map) {
    awards
      ..clear()
      ..addAll(
        ((map['awards'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k as String, DateTime.tryParse(v as String? ?? '') ?? DateTime.now()),
        ),
      );
    awardsSeen
      ..clear()
      ..addAll(((map['awardsSeen'] as List?) ?? const []).cast<String>());
    pendingAwards.clear();
  }

  void _loadMoments(Map<String, dynamic> map, {Map<String, String>? restored}) {
    moments
      ..clear()
      ..addAll(
        ((map['moments'] as List?) ?? const [])
            .map((e) => Moment.fromJson((e as Map).cast<String, dynamic>()))
            .map((m) => restored == null ? m : Moment(m.date, restored[m.file] ?? m.file, note: m.note))
            .where((m) => m.file.isNotEmpty),
      );
  }

  void _remapNoteMedia(Map<String, String> restored) {
    for (var i = 0; i < notes.length; i++) {
      final n = notes[i];
      if (n.media.isEmpty) continue;
      final kept = [
        for (final m in n.media)
          if (restored[m] != null) restored[m]!,
      ];
      notes[i] = n.copyWith(media: kept);
    }
  }

  static String _normName(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  @override
  void syncTrainReminder() {
    if (trainReminderMin == null) {
      TrainReminder.instance.cancel();
      return;
    }
    TrainReminder.instance.schedule(
      minuteOfDay: reminderMinute,
      weekdays: reminderWeekdays,
      skipToday: trainedToday,
    );
  }

  int get reminderMinute => (smartReminder ? usualStartMinute : null) ?? trainReminderMin ?? 19 * 60;

  Set<int> get reminderWeekdays {
    if (smartReminder) {
      final days = usualWeekdays;
      if (days.isNotEmpty) return days.toSet();
    }
    return weeklyPlan.keys.toSet();
  }

  Exercise? matchExerciseByName(String name) => matchExercise(name, allExercises);

  int applyTemplate(ProgramTemplate template) {
    final targetPlan = visibleWeeklyPlan;
    final planWasEmpty = targetPlan.isEmpty;
    var made = 0;
    final sameDay = <String, String>{};
    for (final day in template.days) {
      final ids = <String, int>{};
      for (final (name, sets) in day.exercises) {
        final ex = matchExerciseByName(name);
        if (ex == null || ids.containsKey(ex.id)) continue;
        ids[ex.id] = sets;
      }
      if (ids.isEmpty) continue;
      final key = '${day.name}|${ids.entries.map((e) => '${e.key}:${e.value}').join(',')}';
      final twin = sameDay[key];
      if (twin != null) {
        if (planWasEmpty && day.weekday != null) targetPlan[day.weekday!] = twin;
        continue;
      }
      final id = createRoutine(day.name);
      sameDay[key] = id;
      setRoutineGroup(id, template.name);
      for (final entry in ids.entries) {
        toggleRoutineExercise(id, entry.key);
        bumpRoutineSets(id, entry.key, entry.value - kDefaultRoutineSets);
      }
      if (planWasEmpty && day.weekday != null) targetPlan[day.weekday!] = id;
      made++;
    }
    if (made == 0) return 0;
    persistNow();
    syncTrainReminder();
    notifyListeners();
    return made;
  }

  static const planTemplate =
      '{\n'
      '  "program": "Upper Lower",\n'
      '  "unit": "kg",\n'
      '  "routines": [\n'
      '    {\n'
      '      "name": "Upper A",\n'
      '      "days": ["Monday", "Thursday"],\n'
      '      "exercises": [\n'
      '        {"name": "Barbell Bench Press", "sets": 4, "reps": 8, "weight": 60, "rest": 120,\n'
      '         "plan": [{"type": "warmup", "reps": 10, "weight": 30}]},\n'
      '        {"name": "Barbell Bent Over Row", "sets": 4, "reps": 8, "superset": true},\n'
      '        {"name": "Dumbbell Biceps Curl", "sets": 3, "reps": 12}\n'
      '      ]\n'
      '    }\n'
      '  ]\n'
      '}';

  static const planWeeksTemplate =
      '{"program": "12 weeks", "weeks": [\n'
      '  {"name": "Week 1", "routines": [{"name": "Day A", "exercises": [{"name": "Barbell Full Squat", "sets": 3, "reps": 8}]}]},\n'
      '  {"name": "Week 2", "routines": [{"name": "Day A", "exercises": [{"name": "Barbell Full Squat", "sets": 4, "reps": 8}]}]}\n'
      ']}';

  String planRequestText() {
    final here = allExercises.where(fitsHere).toList();
    final lines = <String>[
      'Infyter · ${activePlace?.name ?? t.placeAll}',
      t.planIntro,
      t.planFormat,
      planTemplate,
      t.planFormatNotes,
      planWeeksTemplate,
      '',
    ];
    for (final ex in here) {
      final local = exerciseName(ex);
      final label = local == ex.name ? ex.name : '${ex.name} ($local)';
      final mode = modeOf(ex.id);
      lines.add(
        '$label | ${ex.primary} | ${ex.equipment} | ${ex.difficulty}${mode.isEmpty ? '' : ' | $mode'}',
      );
    }
    return lines.join('\n');
  }

  ({int added, List<String> missed, bool readable}) importPlan(String raw, {bool schedule = false}) {
    final plans = parsePlan(raw);
    if (plans.isEmpty) return (added: 0, missed: const [], readable: false);
    final result = applyPlan(plans, schedule: schedule);
    return (added: result.added, missed: result.missed, readable: true);
  }

  Exercise? _planExercise(PlanItem item, {bool create = false}) {
    final byId = item.id == null ? null : exerciseById(item.id!);
    if (byId != null && (item.name.isEmpty || !isCustom(byId.id) || byId.name == item.name)) return byId;
    final byName = matchExerciseByName(item.name);
    if (byName != null) return byName;
    if (!create || (item.muscle ?? '').isEmpty) return null;
    final muscle = kMuscles.any((m) => m.id == item.muscle) ? item.muscle! : 'chest';
    final gear = kEquipment.contains(item.equipment) ? item.equipment! : 'Other';
    final level = kDifficulties.contains(item.level) ? item.level! : 'Beginner';
    final id = addCustomExercise(
      name: item.name,
      primary: muscle,
      equipment: gear,
      difficulty: level,
      steps: item.steps,
      mode: item.mode,
    );
    return exerciseById(id);
  }

  ({int routines, int added, List<String> missed}) previewPlan(List<PlanRoutine> plans) {
    var made = 0, added = 0;
    final missed = <String>[];
    for (final plan in plans) {
      var found = 0;
      for (final item in plan.items) {
        final known = _planExercise(item) != null || (item.muscle ?? '').isNotEmpty;
        if (known) {
          found++;
        } else if (!missed.contains(item.name)) {
          missed.add(item.name);
        }
      }
      if (found > 0) made++;
      added += found;
    }
    return (routines: made, added: added, missed: missed);
  }

  bool _sameRoutine(Routine r, String name, List<String> ids) =>
      r.name.trim().toLowerCase() == name.trim().toLowerCase() &&
      r.exerciseIds.length == ids.length &&
      [for (var i = 0; i < ids.length; i++) r.exerciseIds[i] == ids[i]].every((x) => x);

  ({int routines, int added, List<String> missed}) applyPlan(
    List<PlanRoutine> plans, {
    bool schedule = false,
  }) {
    var made = 0, added = 0;
    final missed = <String>[];
    for (final plan in plans) {
      final picked = <(Exercise, PlanItem)>[];
      for (final item in plan.items) {
        final ex = _planExercise(item, create: true);
        if (ex == null) {
          if (!missed.contains(item.name)) missed.add(item.name);
          continue;
        }
        if (picked.any((p) => p.$1.id == ex.id)) continue;
        picked.add((ex, item));
      }
      if (picked.isEmpty) continue;
      final name = plan.name.isEmpty ? t.newRoutineName : plan.name;
      final ids = [for (final p in picked) p.$1.id];
      final existing = visibleRoutines
          .where((r) => _sameRoutine(r, name, ids) && r.group == plan.group)
          .firstOrNull;
      final id = existing?.id ?? createRoutine(name);
      if (existing == null) {
        setRoutineGroup(id, plan.group);
        for (final (ex, item) in picked) {
          toggleRoutineExercise(id, ex.id);
          final sets = _plannedFrom(item);
          if (sets.isNotEmpty) {
            setPlannedSets(id, ex.id, sets);
          } else if (item.sets != null) {
            setRoutineSetCount(id, ex.id, item.sets!);
          }
          if (item.superset) toggleChain(id, ex.id);
          final rest = item.restSec;
          if (rest != null && !hasCustomRest(ex.id)) setExerciseRest(ex.id, rest);
        }
        made++;
        added += picked.length;
      }
      if (schedule) {
        for (final d in plan.days) {
          visibleWeeklyPlan[d] = id;
        }
      }
    }
    if (added > 0 || schedule) {
      persistNow();
      syncTrainReminder();
      notifyListeners();
    }
    return (routines: made, added: added, missed: missed);
  }

  List<PlannedSet> _plannedFrom(PlanItem item) {
    final explicit = [
      for (final p in item.plan)
        PlannedSet(
          reps: p.reps ?? item.reps,
          weightKg: p.weightKg ?? (p.kind == SetKind.warmup.index ? null : item.weightKg),
          kind: setKindFrom(p.kind),
          sec: p.sec,
          km: p.km,
        ),
    ];
    final working = explicit.where((p) => p.kind != SetKind.warmup).length;
    final simple = item.reps == null && item.weightKg == null;
    final wanted = item.sets ?? (working > 0 || simple ? working : kDefaultRoutineSets);
    if (simple && explicit.isEmpty) return const [];
    return [
      ...explicit,
      for (var i = working; i < wanted.clamp(0, 20); i++)
        PlannedSet(reps: item.reps, weightKg: item.weightKg),
    ];
  }

  static const _kindNames = ['normal', 'warmup', 'drop', 'failure', 'restpause'];

  String exportPlanJson(List<Routine> list, {bool withSchedule = true, Map<int, String>? schedule}) {
    final exportedSchedule = schedule ?? visibleWeeklyPlan;
    return encodePlan({
      'infyter': 'plan',
      'v': 1,
      'unit': 'kg',
      'routines': [
        for (final r in list)
          {
            'name': routineTitle(r),
            if (r.group.isNotEmpty) 'group': r.group,
            if (withSchedule)
              'days': [
                for (var d = 1; d <= 7; d++)
                  if (exportedSchedule[d] == r.id) d,
              ],
            'exercises': [
              for (final id in r.exerciseIds)
                if (exerciseById(id) case final ex?)
                  {
                    'id': id,
                    'name': ex.name,
                    'sets': routineSets(r, id),
                    if (hasPlan(r, id))
                      'plan': [
                        for (final p in plannedSets(r, id))
                          {
                            if (p.kind != SetKind.normal) 'type': _kindNames[p.kind.index],
                            if (p.reps != null) 'reps': p.reps,
                            if (p.weightKg != null) 'weight': _round3(p.weightKg!),
                            if (p.sec != null) 'time': p.sec,
                            if (p.km != null) 'distance': p.km,
                          },
                      ],
                    if (chainsToNext(r, id)) 'superset': true,
                    if (hasCustomRest(id)) 'rest': restFor(id),
                    if (isCustom(id))
                      'custom': {
                        'muscle': ex.primary,
                        'equipment': ex.equipment,
                        'level': ex.difficulty,
                        if (ex.steps.isNotEmpty) 'steps': ex.steps,
                        if (modeOf(id).isNotEmpty) 'track': modeOf(id),
                      },
                  },
            ],
          },
      ],
    });
  }

  String planSummaryText(List<Routine> list) {
    final out = <String>[];
    for (final r in list) {
      final days = [
        for (var d = 1; d <= 7; d++)
          if (visibleWeeklyPlan[d] == r.id) t.weekdayShort(d),
      ];
      out.add(days.isEmpty ? routineTitle(r) : '${routineTitle(r)} · ${days.join(', ')}');
      for (final id in r.exerciseIds) {
        final ex = exerciseById(id);
        if (ex == null) continue;
        final planned = plannedSets(r, id).where((p) => p.kind != SetKind.warmup).toList();
        final reps = planned.isEmpty ? null : planned.first.reps;
        final kg = planned.isEmpty ? null : planned.first.weightKg;
        final detail = StringBuffer('${routineSets(r, id)}')..write(reps == null ? '' : ' × $reps');
        if (kg != null) detail.write(' @ ${weightLabel(kg)}');
        out.add('• ${exerciseName(ex)} — $detail${chainsToNext(r, id) ? ' +' : ''}');
      }
      out.add('');
    }
    return out.join('\n').trim();
  }

  static String _sessionKey(LoggedSession s) =>
      '${s.date.toIso8601String()}|${s.exercises.map((e) => '${e.id}:${e.sets.length}').join(',')}';

  // La clave de una sesión ya guardada con sus ids provisorios ("imp:…")
  // resueltos con los nombres de hoy: un ejercicio importado antes de que su
  // nombre tuviera alias ahora se importa con el id del catálogo. [matched]
  // guarda lo ya resuelto: un historial largo repite pocos nombres.
  String _storedKey(LoggedSession s, Map<String, String?> matched) => _sessionKey(
    LoggedSession(s.date, s.durationSec, [
      for (final e in s.exercises)
        e.id.startsWith('imp:')
            ? LoggedExercise(
                matched.putIfAbsent(e.name, () => matchExerciseByName(e.name)?.id) ?? e.id,
                e.name,
                e.primary,
                e.sets,
              )
            : e,
    ]),
  );

  int importParsedSessions(List<ParsedSession> parsed) {
    final matched = <String, String?>{};
    final seen = {...sessions.map(_sessionKey), for (final s in sessions) _storedKey(s, matched)};
    var added = 0;
    for (final ps in parsed) {
      final exs = <LoggedExercise>[];
      for (final pe in ps.exercises) {
        if (pe.sets.isEmpty) continue;
        final match = (pe.id == null ? null : exerciseById(pe.id!)) ?? matchExerciseByName(pe.name);
        final id = match?.id ?? 'imp:${_normName(pe.name).replaceAll(' ', '-')}';
        final hint = (pe.muscle ?? '').toLowerCase();
        final primary =
            match?.primary ?? (kFilterMuscles.contains(hint) ? hint : guessMuscle(pe.name) ?? 'other');
        exs.add(
          LoggedExercise(id, match?.name ?? pe.name, primary, [
            for (final s in pe.sets) LoggedSet(s.reps, s.weightKg, rpe: s.rpe),
          ]),
        );
      }
      if (exs.isEmpty) continue;
      final ls = LoggedSession(ps.date, ps.durationSec, exs);
      final key = _sessionKey(ls);
      if (seen.contains(key)) continue;
      sessions.add(ls);
      seen.add(key);
      added++;
    }
    if (added > 0) {
      sessions.sort((a, b) => a.date.compareTo(b.date));
      _persist();
      _refreshWidgets();
      notifyListeners();
    }
    return added;
  }

  int importParsedWeights(List<ParsedWeight> parsed) {
    final seen = bodyweight.map((e) => _dayKey(e.date)).toSet();
    var added = 0;
    for (final w in parsed) {
      if (w.kg <= 0) continue;
      if (!seen.add(_dayKey(w.date))) continue;
      bodyweight.add(BodyweightEntry(w.date, _round3(w.kg)));
      added++;
    }
    if (added > 0) {
      bodyweight.sort((a, b) => a.date.compareTo(b.date));
      final latest = latestBodyweight;
      if (latest != null) {
        profile.weightKg = latest.kg;
        _seedCalculatorsFromProfile();
      }
      _persist();
      notifyListeners();
    }
    return added;
  }

  bool handleBack() {
    switch (route) {
      case 'exercise-detail':
        closeExerciseDetail();
      case 'tools':
        backFromTools();
      case 'tools-detail':
        closeTool();
      case 'routines':
        backFromRoutines();
      case 'routine-edit':
        closeRoutineEdit();
      case 'measures':
        backFromMeasures();
      case 'places':
        backFromPlaces();
      case 'timeline':
        backFromTimeline();
      case 'compare':
        backFromCompare();
      case 'notes':
        backFromNotes();
      case 'note-edit':
        closeNoteEditor();
      case 'train':
        trainStep == 'review' ? trainBack() : closeTrain();
      case 'preferences':
        backFromPreferences();
      case 'moments':
        backFromMoments();
      case 'awards':
        backFromAwards();
      case 'ai-plan':
        backFromAiPlan();
      case 'progress':
      case 'exercises':
      case 'settings':
        goHome();
      case 'home':
        return false;
      default:
        popRoute();
    }
    return true;
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _restTimer?.cancel();
    super.dispose();
  }
}

final fit = FitState();
