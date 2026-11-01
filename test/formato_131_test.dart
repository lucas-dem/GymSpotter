// Prueba de formato 1.3.1 (sesión 15, Agente B: persistencia y actualizaciones).
//
// Fija el formato que Infyter 1.3.1 (commit 151fd24) escribe en
// SharedPreferences, en UNA sola clave: `gymmane_v1` (en disco, con el
// prefijo de plataforma `flutter.`). Verifica que el código actual:
//   1. lee el fixture completo,
//   2. al guardar y recargar no pierde nada (ida y vuelta exacta),
//   3. sigue teniendo todos los ids del catálogo que 1.3.1 conocía.
// Además documenta, con tests de caracterización que PASAN describiendo el
// comportamiento actual, los casos en los que la carga altera datos.
// Sesión 16: los dos últimos casos (tipo inesperado y JSON ilegible) ya no
// pierden el original: queda una copia de rescate (ver store_rescue_test.dart).
//
// El fixture se armó a mano a partir de los toJson() reales:
// lib/state/fit_state.dart:371-433 y los modelos de lib/models/ y
// lib/state/moments_state.dart. Son datos inventados de prueba.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/catalog/exercise_catalog.dart';
import 'package:infyter/models/note.dart';
import 'package:infyter/models/workout.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/services/store_migrations.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kKey = 'gymmane_v1';

const List<String> _liveKeys = ['live', 'liveStart', 'liveElapsed', 'livePaused'];

/// Lo que 1.3.1 guarda para una persona con rutinas, historial, medidas,
/// fotos, notas, lugares, modo entrenador y un entrenamiento en pausa.
const String kFixture131 = r'''
{
  "profile": {"name": "Braian Prueba", "sex": "male", "age": 31, "h": 178.0, "w": 82.5, "act": 1.55, "goal": 4,
    "photo": "iVBORw0KGgo=", "handle": "braian.test", "badge": "blue", "banner": "R0lGODlhAQABAAAAACw=",
    "since": "2026-09-01T00:00:00.000"},
  "dark": true,
  "theme": "dark",
  "units": "lb",
  "language": "en",
  "rest": 120,
  "alarmSound": null,
  "alarmSoundName": null,
  "bg": "grid",
  "gymBranch": "chacabuco",
  "heatTone": "green",
  "bgDim": 0.7,
  "showFocus": false,
  "autoAdvance": false,
  "keepAwake": false,
  "countdown": false,
  "gamify": true,
  "rpe": true,
  "effort": "rir",
  "demo": "small",
  "alarmStyle": "loud",
  "noSuggest": ["SpYC0Kp"],
  "exMode": {"plank-hold": "weight"},
  "trainAt": 1140,
  "trainSmart": true,
  "trainerMode": true,
  "alarmAskedAt": 1761700000000,
  "onboarded": true,
  "favorites": {"EIeI8Vf": true, "qXTaZnJ": true, "SpYC0Kp": false},
  "notes": [
    {"id": "n1760900000000000", "x": "EIeI8Vf", "d": "2026-10-20T00:00:00.000", "k": 1,
      "t": "Subir 2,5 kg\nLa última serie costó", "m": ["note-1760900000000000-0.jpg"], "c": "2026-10-20T19:05:00.000"},
    {"id": "n1761000000000001", "x": "", "d": "2026-10-22T00:00:00.000", "k": 3,
      "t": "Molestia en el hombro izquierdo", "c": "2026-10-22T08:00:00.000"}
  ],
  "places": [
    {"id": "p1760000000000000", "n": "Gimnasio Junín", "e": ["Barbell", "Dumbbell", "Machine", "Cable"],
      "p": {"20.0": 4, "10.0": 4, "1.25": 2}, "b": 20.0},
    {"id": "p1760000000000001", "n": "Casa", "e": ["Bodyweight", "Band"]}
  ],
  "place": "p1760000000000000",
  "checkins": ["2026-10-5", "2026-10-12"],
  "routines": [
    {"id": "r1760000000000000-0", "n": "Empuje A", "ex": ["EIeI8Vf", "SpYC0Kp", "plank-hold"], "s": {"SpYC0Kp": 4},
      "c": ["EIeI8Vf"], "g": "PPL", "k": 3,
      "p": {"EIeI8Vf": [{"r": 10, "w": 40.0, "k": 1}, {"r": 8, "w": 80.0}, {"r": 8, "w": 80.0}, {"r": 6, "w": 85.0, "k": 3}],
            "plank-hold": [{"t": 60}, {"t": 45}]}},
    {"id": "r1760000000000001-1", "n": "Piernas", "ex": ["qXTaZnJ", "running", "c1760000000000000-0"],
      "p": {"running": [{"t": 1200, "km": 3.5}]}},
    {"id": "r1760000000000002-2", "n": "Rutina de Juan", "ex": ["eZyBC3j", "lBDjFxJ"], "o": "a1760000000000000"}
  ],
  "weeklyPlan": {"1": "r1760000000000000-0", "3": "r1760000000000001-1", "5": "r1760000000000000-0"},
  "athletes": [{"id": "a1760000000000000", "n": "Juan"}],
  "athleteWeeklyPlans": {"a1760000000000000": {"2": "r1760000000000002-2"}},
  "custom": [
    {"id": "c1760000000000000-0", "n": "Bici fija del club", "p": "quads", "e": "Machine", "d": "Beginner",
      "st": ["Regulá el asiento", "Pedaleá a ritmo constante"], "k": "cardio"},
    {"id": "c1760000000000001-1", "n": "Press con banda", "p": "chest", "e": "Band", "d": "Intermediate"}
  ],
  "media": {"EIeI8Vf": "EIeI8Vf-1760000000000000-0.mp4", "bg": "bg-1760000000000001-1.jpg",
    "c1760000000000001-1": "c1760000000000001-1-1760000000000002-2.jpg"},
  "exRest": {"EIeI8Vf": 150, "qXTaZnJ": 180},
  "progress": {"EIeI8Vf": 2.5},
  "warmup": ["qXTaZnJ"],
  "repsOnly": ["lBDjFxJ"],
  "repsOnlyOff": ["plank-hold"],
  "sessions": [
    {"d": "2026-10-20T18:30:00.000", "dur": 3725, "ex": [
      {"id": "EIeI8Vf", "n": "Barbell Bench Press", "p": "chest",
        "s": [{"r": 10, "w": 40.0, "k": 1}, {"r": 8, "w": 80.0, "e": 8.0}, {"r": 7, "w": 80.0, "e": 9.5}]},
      {"id": "running", "n": "Treadmill Run", "p": "quads", "s": [{"r": 0, "w": 0.0, "t": 1200, "km": 3.5}]}
    ]},
    {"d": "2026-10-22T19:00:00.000", "dur": 2400, "ex": [
      {"id": "qXTaZnJ", "n": "Barbell Full Squat", "p": "glutes",
        "s": [{"r": 5, "w": 100.0}, {"r": 5, "w": 100.0}, {"r": 8, "w": 80.0, "k": 2}]},
      {"id": "c1760000000000000-0", "n": "Bici fija del club", "p": "quads", "s": [{"r": 0, "w": 0.0, "t": 900}]}
    ]},
    {"d": "2026-10-24T12:00:00.000", "dur": 0, "ex": [
      {"id": "imp:press-militar", "n": "Press militar", "p": "shoulders", "s": [{"r": 8, "w": 40.0}]}
    ]}
  ],
  "bodyweight": [{"d": "2026-10-01T08:00:00.000", "kg": 83.2}, {"d": "2026-10-25T08:00:00.000", "kg": 82.5}],
  "measures": [
    {"d": "2026-10-01T09:00:00.000", "k": "waist", "v": 86.5},
    {"d": "2026-10-01T09:00:00.000", "k": "arm", "v": 38.0},
    {"d": "2026-10-25T09:00:00.000", "k": "bodyfat", "v": 17.5}
  ],
  "shots": [{"id": "s1760000000000000-0", "d": "2026-10-01T00:00:00.000",
    "s": {"front": "shot-1760000000000003-3.jpg", "side": "shot-1760000000000004-4.jpg"}, "w": 83.2, "n": "Inicio"}],
  "awards": {"firstStep": "2026-09-01T10:00:00.000", "firstRoutine": "2026-09-02T10:00:00.000",
    "firstWorkout": "2026-10-20T19:32:05.000", "firstRecord": "2026-10-20T19:32:05.000",
    "tonne1": "2026-10-22T19:40:00.000"},
  "awardsSeen": ["firstStep", "firstRoutine"],
  "moments": [{"d": "2026-10-20T19:40:00.000", "f": "moment-1760000000000005-5.jpg", "n": "PR de banca"}],
  "photoEvery": 15,
  "bodyTl": true,
  "live": {"ex": [
      {"id": "eZyBC3j", "n": "Barbell Bent Over Row", "p": "back",
        "s": [{"r": 10, "w": 60.0, "d": true}, {"r": 10, "w": 60.0, "d": false}], "l": true},
      {"id": "lBDjFxJ", "n": "Pull-up", "p": "back", "s": [{"r": 8, "w": 0.0, "d": false, "k": 3}]}
    ], "i": 0, "c": false, "at": null, "rf": 45, "sv": null, "ss": null, "sd": null},
  "liveStart": null,
  "liveElapsed": 845,
  "livePaused": true
}
''';

/// Los 563 ids de `kExercises` en 151fd24 (1.3.1). Rutinas, historial,
/// favoritos, notas, descansos, medios y ajustes por ejercicio los referencian.
const List<String> kCatalogIds131 = [
  'EIeI8Vf',
  'SpYC0Kp',
  '3TZduzM',
  'ns0SIbU',
  'GrO65fd',
  'yz9nUhF',
  'I4hDWkc',
  '9WTm7dq',
  '9XjtHvS',
  'Kyd9Rz5',
  'A6wtbuL',
  'Xy4jlWA',
  'DsgkuIt',
  'goJ6ezq',
  '3eGE2JC',
  'v1qBec9',
  'NJzBsGJ',
  'dG7tG5y',
  'ila4NZS',
  'wQ2c4XD',
  'KgI0tqW',
  'eZyBC3j',
  'BJ0Hz5L',
  'r0z6xzQ',
  'fUBheHs',
  'RVwzP10',
  'lBDjFxJ',
  'T2mxWqc',
  'EAs3xL9',
  'qXTaZnJ',
  'zG0zs85',
  'yn8yg1r',
  '7zdxRTl',
  'RRWFUcw',
  'qx4fgX7',
  'XlZ4lAC',
  'qKBpF7I',
  'OM46QHm',
  '8ozhUIZ',
  'ktsFQAZ',
  'Y1MsI1l',
  'zHEpuuc',
  '25GPyDY',
  'NbVPDMW',
  'slDvUAU',
  'qOgPVf6',
  'gvsWLQw',
  '3ZflifB',
  'iZop9xO',
  'PdmaD0N',
  '2IxROQ1',
  'X6C6i5Y',
  'VBAWRPG',
  'TFqbd8t',
  'abs-crunches-bench',
  'jpgqxiS',
  'QOA0FD0',
  'XVDdcoj',
  'cA9FuWG',
  '7vG5o25',
  '4IKbhHV',
  'vrhHa6D',
  '72BC5Za',
  'Gk1r408',
  'hMEptv0',
  'PbzNu7c',
  'eYnzaCm',
  'kiJ4Z2K',
  'GaSzzuh',
  '8urJS9b',
  'Hj4FOCd',
  'XUUD0Fs',
  'OQ1otBN',
  '7OeHptV',
  'mExgrF9',
  'JsOV1SU',
  'dmgMp3n',
  'kesXOpB',
  'f4xtKBj',
  '3xK09Sk',
  'fXfqg1E',
  'wt6rwjk',
  'veXwo0D',
  '7I6LNUG',
  'v2DfH14',
  'HMzLjXx',
  'i6LWjok',
  'ZIViNh1',
  'ZSJNetl',
  'aaXr7ld',
  'tig3PXb',
  'znLogoF',
  '9pQSkH8',
  'yaMIo4D',
  'xbkPfaw',
  'face-pull',
  'one-arm-dumbbell-row',
  'close-grip-lat-pulldown',
  'wide-grip-lat-pulldown',
  'single-arm-cable-row',
  'meadows-row',
  'neutral-grip-pull-up',
  'active-hang',
  'negative-pull-up',
  'commando-pull-up',
  'l-sit-pull-up',
  'towel-pull-up',
  'towel-row',
  'scapular-push-up',
  'prone-t-raise',
  'superman',
  'superman-hold',
  'reverse-snow-angel',
  'band-pull-apart',
  'banded-face-pull',
  'banded-row',
  'banded-lat-pulldown',
  'cat-cow-stretch',
  'worlds-greatest-stretch',
  'leg-swings-stretch',
  'childs-pose',
  'rowing',
  'skierg',
  'swimming',
  '9sgNE2O',
  'vptOQ4N',
  '7xI5MXA',
  'PAgTVaK',
  'A9qxk2F',
  'PSlvNMs',
  'hl8DUh8',
  'vi8EhoE',
  '0CXGHya',
  'XgWyAiA',
  'Ff18ItA',
  '33AzZeV',
  'DwhEmmE',
  '7saC5zz',
  'WbNq5Xu',
  'LQFOrMn',
  'GXoaSgn',
  'xXm4nYq',
  'wDN97Ca',
  '7E06s6d',
  '1qrWgZ2',
  '2Pya1cP',
  'trqKQv2',
  'wigSg76',
  'Vh0GsK4',
  'ETZfAbZ',
  'CMAxnsG',
  'JsKq9so',
  'reFHapa',
  'tBWXbIT',
  'MY9P1WA',
  'pec-deck',
  'incline-push-up',
  'knee-push-up',
  'wide-push-up',
  'decline-push-up',
  'typewriter-push-up',
  'hindu-push-up',
  'wall-push-up',
  'seal-jack',
  'doorway-chest-stretch',
  'b2Uoz54',
  'izMnLqz',
  'KHPZL0b',
  'myfUsKf',
  'flat-converging-chest-press',
  'incline-converging-chest-press',
  'cable-pullover',
  'pendulum-hack-squat',
  'machine-leg-press',
  'machine-lying-leg-curl',
  'static-lunge',
  'box-step-up',
  'alternating-dumbbell-curl',
  'reverse-grip-lat-pulldown',
  'e4aFmFY',
  'xHKN2s8',
  'eOrFCnx',
  'aqvSOQE',
  '67n3r98',
  '7uFJuXp',
  'Ln9iTbU',
  '3d7wHyd',
  'hvHhCv8',
  'Gpn4ADc',
  'VLYXo8S',
  'S9zHIvU',
  'QfAKy1G',
  'u2X71Np',
  'nFUwqG6',
  'ngPpyRS',
  'Rr7S3yg',
  'mTT3KLn',
  'xUwnBMT',
  '0dCyly0',
  'AQ0mC4Y',
  'G61cXLk',
  '903mzG8',
  'kTbSH9h',
  'aTNKZiC',
  'ht8xDrP',
  'nxW6BkN',
  'yUdIGNs',
  'upright-row',
  'machine-lateral-raise',
  'landmine-press',
  'pike-push-up',
  'feet-elevated-pike-push-up',
  'handstand-push-up',
  'wall-handstand-push-up',
  'wall-walk',
  'cross-body-shoulder-stretch',
  'battle-ropes',
  'xi0yckC',
  '6e2DcYX',
  'MvQPqVW',
  'CqhoytW',
  '2gPfomN',
  'wnEscH8',
  'IpONWYv',
  'WW95auq',
  'ayAHcEm',
  'Hy9D21L',
  's8nrDXF',
  '7M66AVi',
  'RqOtqD7',
  'qaZVsGk',
  'EZeDVzO',
  'Gxg9lDc',
  'd9Xaxq6',
  'uWpxD4v',
  'xmM75XG',
  'dFSNDOA',
  '8xUv4J7',
  'PXTIwgu',
  'fZFZ704',
  'i4JkUaL',
  'UEjSrKI',
  'NAkmgdx',
  's34Y4LR',
  'G7xoEzr',
  'wPypxFY',
  '5VXmnV5',
  '6bOA1Oi',
  'xnInPfE',
  'captains-chair-knee-raise',
  'bicycle-crunch',
  'mountain-climber',
  'dead-bug',
  'bird-dog',
  'pallof-press',
  'half-kneeling-pallof-press',
  'cable-pallof-hold',
  'hollow-body-hold',
  'hollow-rock',
  'v-up',
  'flutter-kick',
  'lying-leg-raise',
  'plank-shoulder-tap',
  'plank-jack',
  'bear-plank',
  'bear-crawl',
  'inchworm',
  'l-sit-hold',
  'side-plank-hip-dip',
  'dragon-flag',
  'half-burpee',
  'squat-thrust',
  'banded-pallof-press',
  'banded-woodchop',
  'banded-dead-bug',
  'Y7YcmIJ',
  'gFyFj9z',
  'hBGWILP',
  'Gu2rNJd',
  'SaDOwk7',
  '0lQnxMZ',
  'W9pFVv1',
  'QjE2DcA',
  'wWFspEi',
  'SGY8Zui',
  'r5DgrW9',
  '6YUfHPL',
  'uKyN64F',
  'mweqJin',
  'gfk9kD4',
  'c8f5cSY',
  'W31mMjd',
  'VO2qeJg',
  'gGNQmVt',
  'xdYPUtE',
  'HBYyX94',
  '9E25EOx',
  'oR7O9LW',
  'QChZi3x',
  'RYcV1kH',
  '5BZHW9s',
  's7HX1BY',
  'QpXqiq8',
  'dG5Smob',
  'IMRsOCn',
  'belt-squat',
  'hip-adduction-machine',
  'landmine-squat',
  'heel-elevated-goblet-squat',
  'front-foot-elevated-split-squat',
  'smith-machine-bulgarian-split-squat',
  'smith-machine-reverse-lunge',
  'reverse-lunge',
  'dumbbell-lateral-lunge',
  'wall-sit',
  'burpee',
  'high-knees',
  'jumping-jack',
  'skater-hop',
  'lateral-shuffle',
  'sprawl',
  'pistol-squat',
  'assisted-pistol-squat',
  'shrimp-squat',
  'skater-squat',
  'single-leg-box-squat',
  'banded-squat',
  'standing-quad-stretch',
  'running',
  'walking',
  'treadmill-incline-walk',
  'hiking',
  'cycling',
  'assault-bike',
  'elliptical',
  'Yza7XrQ',
  'zILLZ98',
  'sJFIDIp',
  'M5Y7GPg',
  'aee2Fcj',
  'fy7Tgy4',
  'NvfE43H',
  '50BETrz',
  'IENzBdA',
  'NlfIbzq',
  'G08RZcQ',
  'guT8YnS',
  'SYJ4Bkt',
  '6em2Dxj',
  'dXz8zjF',
  'gscGLOU',
  'WLvTAv5',
  'Zwiw7XR',
  'HPlPoQA',
  'xNrS20v',
  'J74XlNf',
  'otqIxU4',
  '4LIG9xr',
  '1VpF8db',
  '61GrD55',
  '1V1gj1u',
  '2NImIAG',
  '4dUn2iv',
  'incline-dumbbell-curl',
  'J6Dx1Mu',
  '7jGOBF3',
  'Gchi5Tr',
  'J60bN17',
  'RrLske5',
  'MU9HnE7',
  'LMGXZn8',
  'Db7eEgw',
  'Ser9eQp',
  '9RT8oQW',
  'gtO1ErP',
  'gx7s7uF',
  'SHUMp5H',
  '1xHyxys',
  'WcHl7ru',
  'U6G2gk9',
  'bZq4bwK',
  '641mIfk',
  'OTgkHwR',
  'Hx1WC8I',
  'yB9SvIF',
  's0HKO2I',
  'K1vlode',
  'ZsiqXYa',
  'XalXcvM',
  'HEJ6DIX',
  'o8aOcrz',
  'x6KpKpq',
  'yg8Totb',
  'wkgnGfb',
  'rope-tricep-pushdown',
  'single-dumbbell-skullcrusher',
  'single-arm-dumbbell-tricep-extension',
  'chair-dip',
  'crab-walk',
  'qi996YS',
  'mnzcrIB',
  'eGDudUV',
  '1bQkKZK',
  'RtyAsy1',
  'GWoKnIm',
  'IeTIEqg',
  '7Hg55JG',
  'Kpajagk',
  'UfePqpx',
  'BbfB8Gb',
  '5WiFcYk',
  'DhMl549',
  'ecl28tP',
  'lFhb2Rw',
  'u27Kcdz',
  'JZuApnB',
  'vR1vold',
  'nUwVh7b',
  'NNoHCEA',
  '6sYyrRX',
  'qg2PGl6',
  '6pTkI99',
  'ZuPXtCK',
  'wfotm7S',
  '5VCj6iH',
  'S4pwGlc',
  'hip-thrust',
  'dumbbell-hip-thrust',
  'glute-bridge',
  'single-leg-glute-bridge',
  'dumbbell-glute-bridge',
  'glute-bridge-march',
  'trap-bar-deadlift',
  'hip-abduction-machine',
  'machine-glute-kickback',
  'cable-standing-hip-abduction',
  'reverse-hyperextension',
  'dumbbell-sumo-deadlift',
  'dumbbell-sumo-squat',
  'deficit-reverse-lunge',
  'dumbbell-curtsy-lunge',
  'curtsy-lunge',
  'frog-pump',
  'donkey-kick',
  'fire-hydrant',
  'clamshell',
  'hip-airplane',
  'side-lying-leg-raise',
  'banded-glute-bridge',
  'banded-hip-thrust',
  'banded-frog-pump',
  'banded-clamshell',
  'banded-lateral-walk',
  'banded-monster-walk',
  'banded-donkey-kick',
  'banded-fire-hydrant',
  'banded-kickback',
  'banded-standing-hip-abduction',
  'banded-seated-hip-abduction',
  'kneeling-hip-flexor-stretch',
  'butterfly-stretch',
  'stair-climber',
  '2IHEa2T',
  'r29jP7S',
  'yl2IYyy',
  'IeDEXTe',
  'LmaFNZS',
  'rGwhJ5o',
  'ykUOVze',
  'bJYHBIN',
  '6HiHHe0',
  'FxhcxUW',
  '9GXrTE6',
  'iPm26QU',
  'VW88JNd',
  'ywaNfuh',
  'u5ESqzH',
  '1kB3Wmk',
  '0S75mYG',
  'dPmaUaU',
  '6MaEjVA',
  '0jp9Rlz',
  'wall-calf-stretch',
  'jump-rope',
  'yzYH9pI',
  'mtXengz',
  'eYmsEPR',
  'B6dAO1t',
  'arvaszz',
  'bjqbauy',
  'SJAA2IQ',
  'mym4hJo',
  'VhX2JdE',
  'hfmQ0Tz',
  'bd5b860',
  'qDnGfDb',
  '7RWNjiB',
  'LrV4s90',
  'LsZkfU6',
  'M2Pm3zj',
  '2qTvJAZ',
  'rEhi2o5',
  '82LxxkW',
  'cwsAI4G',
  'Eg98Ft9',
  'ZZKbeMw',
  '7xeukSt',
  'JymLInS',
  'MzNnwx9',
  'uTBt1HV',
  'OUQ0ZyW',
  'hrVQWvE',
  'FkBIE6a',
  'GwYwElT',
  'SiWCcTN',
  'LNE3wfo',
  'C5jncD2',
  'seated-leg-curl',
  'kettlebell-romanian-deadlift',
  'single-leg-romanian-deadlift',
  'landmine-romanian-deadlift',
  'lying-hamstring-walkout',
  'stability-ball-hamstring-curl',
  'hamstring-stretch',
  'seated-forward-fold-stretch',
  'kettlebell-swing',
  'kettlebell-goblet-squat',
  'kettlebell-front-squat',
  'kettlebell-sumo-deadlift',
  'kettlebell-single-leg-deadlift',
  'kettlebell-reverse-lunge',
  'kettlebell-single-arm-row',
  'kettlebell-overhead-press',
  'kettlebell-push-press',
  'kettlebell-high-pull',
  'kettlebell-shrug',
  'kettlebell-farmer-carry',
  'kettlebell-overhead-tricep-extension',
  'kettlebell-russian-twist',
  'kettlebell-side-bend',
  'rNG1dip',
  'rNG2pus',
  'rNG3fly',
  'rNG4tri',
  'rNG5pul',
  'rNG6chi',
  'rNG7row',
  'rNG8fac',
  'rNG9cur',
  'rNGaham',
  'rNGbrol',
  'rNGclsi',
  'rNGdsup',
  'rNGemus',
  'plank-hold',
  'side-plank-hold',
  'dead-hang-hold',
  'outdoor-run',
  'outdoor-cycling',
  'outdoor-walk',
  'outdoor-hike',
  'swim',
  'leg-extension',
];

Map<String, dynamic> _fixture() => jsonDecode(kFixture131) as Map<String, dynamic>;

Map<String, dynamic> _stored(SharedPreferences prefs) =>
    jsonDecode(prefs.getString(kKey)!) as Map<String, dynamic>;

/// Diferencias entre dos JSON. Las claves nuevas se marcan "apareció" (no son
/// pérdida); todo lo demás (clave perdida, lista más corta, valor cambiado) sí.
List<String> _diff(Object? a, Object? b, [String path = r'$']) {
  if (a is Map && b is Map) {
    return [
      for (final k in {...a.keys, ...b.keys})
        if (!b.containsKey(k))
          '$path.$k: se perdió (${jsonEncode(a[k])})'
        else if (!a.containsKey(k))
          '$path.$k: apareció (${jsonEncode(b[k])})'
        else
          ..._diff(a[k], b[k], '$path.$k'),
    ];
  }
  if (a is List && b is List) {
    return [
      if (a.length != b.length) '$path: largo ${a.length} -> ${b.length}',
      for (var i = 0; i < math.min(a.length, b.length); i++) ..._diff(a[i], b[i], '$path[$i]'),
    ];
  }
  return a == b ? const [] : ['$path: ${jsonEncode(a)} -> ${jsonEncode(b)}'];
}

/// Como [_diff], pero los logros se comparan como subconjunto: al cargar,
/// refreshAwards() puede ganar logros nuevos según la fecha (rachas).
List<String> _perdidas(Map<String, dynamic> antes, Map<String, dynamic> despues) {
  final a = Map<String, dynamic>.of(antes)..remove('awards');
  final b = Map<String, dynamic>.of(despues)..remove('awards');
  final out = _diff(a, b).where((d) => !d.contains(': apareció')).toList();
  final la = (antes['awards'] as Map?) ?? const {};
  final lb = (despues['awards'] as Map?) ?? const {};
  for (final e in la.entries) {
    if (lb[e.key] != e.value) out.add('\$.awards.${e.key}: ${e.value} -> ${lb[e.key]}');
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences prefs;
  late Directory rescueTmp;

  setUpAll(() async {
    rescueTmp = await Directory.systemTemp.createTemp('infyter_formato131');
    Store.rescueDirectory = rescueTmp.path;
    SharedPreferences.setMockInitialValues({kKey: kFixture131});
    await Store.instance.init();
    prefs = await SharedPreferences.getInstance();
  });

  tearDownAll(() async {
    fit.saveAndExit();
    Store.rescueDirectory = null;
    if (rescueTmp.existsSync()) await rescueTmp.delete(recursive: true);
  });

  // Corta timers y el guardado diferido pendiente, y deja `raw` en disco.
  Future<void> sembrar(String raw) async {
    fit.saveAndExit();
    await prefs.setString(kKey, raw);
  }

  test('1.3.1: el fixture se lee completo', () async {
    await sembrar(kFixture131);
    fit.loadFromStore();

    final p = fit.profile;
    expect(p.name, 'Braian Prueba');
    expect(p.age, 31);
    expect(p.heightCm, 178);
    expect(p.weightKg, 82.5);
    expect(p.handle, 'braian.test');
    expect(p.photo, isNotEmpty);
    expect(p.banner, isNotEmpty);
    expect(p.since, DateTime(2026, 9, 1));

    expect(fit.themePref, 'dark');
    expect(fit.units, 'lb');
    expect(fit.language, 'en');
    expect(fit.restSeconds, 120);
    expect(fit.gymBranch, 'chacabuco');
    expect(fit.bgPattern, 'grid');
    expect(fit.heatTone, 'green');
    expect(fit.bgDim, 0.7);
    expect([fit.showFocus, fit.autoAdvance, fit.keepScreenOn, fit.startCountdown], everyElement(isFalse));
    expect(fit.gamification, isTrue);
    expect(fit.logRpe, isTrue);
    expect(fit.effortScale, 'rir');
    expect(fit.demoSize, 'small');
    expect(fit.alarmStyle, 'loud');
    expect(fit.trainReminderMin, 1140);
    expect(fit.smartReminder, isTrue);
    expect(fit.trainerMode, isTrue);
    expect(fit.alarmAskedAt, 1761700000000);
    expect(fit.onboarded, isTrue);
    expect(fit.photoIntervalDays, 15);
    expect(fit.bodyTimeline, isTrue);

    expect(fit.favorites, {'EIeI8Vf': true, 'qXTaZnJ': true, 'SpYC0Kp': false});
    expect(fit.noSuggest, {'SpYC0Kp'});
    expect(fit.modeOverride, {'plank-hold': 'weight'});

    expect(fit.notes, hasLength(2));
    final nota = fit.notes.first;
    expect(nota.exerciseId, 'EIeI8Vf');
    expect(nota.kind, NoteKind.plan);
    expect(nota.title, 'Subir 2,5 kg');
    expect(nota.media, ['note-1760900000000000-0.jpg']);
    expect(fit.notes.last.isGeneral, isTrue);
    expect(fit.notes.last.kind, NoteKind.pain);

    expect(fit.places, hasLength(2));
    expect(fit.places.first.plates, {20.0: 4, 10.0: 4, 1.25: 2});
    expect(fit.places.first.bar, 20.0);
    expect(fit.activePlaceId, 'p1760000000000000');
    expect(fit.checkins, {'2026-10-5', '2026-10-12'});

    expect(fit.routines, hasLength(3));
    final empuje = fit.routines[0];
    expect(empuje.exerciseIds, ['EIeI8Vf', 'SpYC0Kp', 'plank-hold']);
    expect(empuje.sets, {'SpYC0Kp': 4});
    expect(empuje.chained, {'EIeI8Vf'});
    expect(empuje.group, 'PPL');
    expect(empuje.color, 3);
    expect(empuje.plan['EIeI8Vf']!.map((s) => s.kind), [
      SetKind.warmup,
      SetKind.normal,
      SetKind.normal,
      SetKind.failure,
    ]);
    expect(empuje.plan['plank-hold']!.map((s) => s.sec), [60, 45]);
    expect(fit.routines[1].exerciseIds, contains('c1760000000000000-0'));
    expect(fit.routines[2].ownerId, 'a1760000000000000');
    for (final r in fit.routines) {
      expect(
        fit.routineExercises(r).length,
        r.exerciseIds.length,
        reason: 'cada id de la rutina "${r.name}" tiene que seguir resolviendo (catálogo o personalizado)',
      );
    }
    expect(fit.weeklyPlan, {1: 'r1760000000000000-0', 3: 'r1760000000000001-1', 5: 'r1760000000000000-0'});
    expect(fit.athletes.single.name, 'Juan');
    expect(fit.athleteWeeklyPlans['a1760000000000000'], {2: 'r1760000000000002-2'});

    expect(fit.customExercises, hasLength(2));
    expect(fit.customExercises.first.mode, 'cardio');
    expect(fit.customExercises.first.steps, hasLength(2));
    expect(fit.exerciseMedia, hasLength(3));
    expect(fit.exerciseRest, {'EIeI8Vf': 150, 'qXTaZnJ': 180});
    expect(fit.progressStep, {'EIeI8Vf': 2.5});
    expect(fit.autoWarmup, {'qXTaZnJ'});
    expect(fit.repsOnly, {'lBDjFxJ'});
    expect(fit.repsOnlyOff, {'plank-hold'});

    expect(fit.sessions, hasLength(3));
    expect(fit.sessions[0].durationSec, 3725);
    final banca = fit.sessions[0].exercises[0];
    expect(banca.sets.map((s) => s.kind), [SetKind.warmup, SetKind.normal, SetKind.normal]);
    expect(banca.sets.last.rpe, 9.5);
    final cinta = fit.sessions[0].exercises[1].sets.single;
    expect([cinta.sec, cinta.km], [1200, 3.5]);
    expect(fit.sessions[1].exercises[0].sets.last.kind, SetKind.drop);
    expect(fit.sessions[2].exercises.single.id, 'imp:press-militar');

    expect(fit.bodyweight.map((b) => b.kg), [83.2, 82.5]);
    expect(fit.measures.map((m) => m.key), ['waist', 'arm', 'bodyfat']);
    expect(fit.shots.single.shots.keys, ['front', 'side']);
    expect(fit.moments.single.note, 'PR de banca');
    expect(
      fit.awards.keys,
      containsAll(['firstStep', 'firstWorkout', 'firstRoutine', 'firstRecord', 'tonne1']),
    );
    expect(fit.awardsSeen, {'firstStep', 'firstRoutine'});

    final viva = fit.session!;
    expect(fit.route, 'session', reason: 'un entrenamiento en curso se retoma al abrir');
    expect(fit.sessionPaused, isTrue);
    expect(fit.sessionElapsed, 845);
    expect(viva.exercises.map((e) => e.id), ['eZyBC3j', 'lBDjFxJ']);
    expect(viva.exercises.first.linkedNext, isTrue);
    expect(viva.exercises.first.sets.map((s) => s.done), [true, false]);
    expect(viva.restFrozen, 45);
  });

  test('1.3.1: guardar y recargar no pierde nada (ida y vuelta exacta)', () async {
    await sembrar(kFixture131);
    fit.loadFromStore();
    fit.persistNow();
    final primera = _stored(prefs);
    final perdidas = _perdidas(_fixture(), primera);
    final nuevas = _diff(_fixture(), primera).where((d) => d.contains(': apareció')).toList();
    final logrosNuevos = (primera['awards'] as Map).keys.toSet()
      ..removeAll((_fixture()['awards'] as Map).keys);
    print(
      'Fixture 1.3.1: ${kFixture131.length} caracteres, ${_fixture().length} claves de primer nivel. '
      'Guardado por el código actual: ${prefs.getString(kKey)!.length} caracteres, ${primera.length} claves.',
    );
    print('Claves nuevas escritas por el código actual: ${nuevas.isEmpty ? 'ninguna' : nuevas}');
    print(
      'Logros ganados al recargar (dependen de la fecha): ${logrosNuevos.isEmpty ? 'ninguno' : logrosNuevos}',
    );
    expect(perdidas, isEmpty, reason: perdidas.join('\n'));
    expect(nuevas, [
      '\$.$kSchemaVersionKey: apareció ($kStoreSchemaVersion)',
    ], reason: 'la única clave nueva es la versión de formato');
    expect(Store.instance.rescue, isNull, reason: 'un blob 1.3.1 sano no genera copias de rescate');

    fit.loadFromStore();
    fit.persistNow();
    final segunda = _stored(prefs);
    expect(_diff(primera, segunda), isEmpty, reason: 'la segunda vuelta tiene que ser idéntica a la primera');
  });

  test('guardia: siguen existiendo los 563 ids del catálogo de 1.3.1', () {
    expect(kCatalogIds131, hasLength(563));
    final hoy = {for (final e in kExercises) e.id};
    final faltan = [
      for (final id in kCatalogIds131)
        if (!hoy.contains(id)) id,
    ];
    expect(
      faltan,
      isEmpty,
      reason:
          'un id borrado o renombrado deja huérfanos rutinas, historial por ejercicio, favoritos, '
          'notas, descansos y medios: $faltan',
    );
  });

  test('guardia: todo se guarda en una sola clave, gymmane_v1', () async {
    await sembrar(kFixture131);
    fit.loadFromStore();
    fit.persistNow();
    expect(prefs.getKeys(), [kKey]);
  });

  test('caracterización: lo que la carga descarta o altera se pierde en el siguiente guardado', () async {
    final m = _fixture();
    for (final k in _liveKeys) {
      m.remove(k);
    }
    (m['measures'] as List).add({'d': '2026-10-26T09:00:00.000', 'k': 'biceps', 'v': 40.0});
    (m['exRest'] as Map)['SpYC0Kp'] = 0;
    m['alarmSound'] = 'alarm-1761000000000.mp3';
    m['alarmSoundName'] = 'Mi alarma';
    (m['shots'] as List).add({
      'id': 's1761400000000000-1',
      'd': '2026-10-26T00:00:00.000',
      's': {'frente': 'shot-1761400000000000-9.jpg'},
    });
    await sembrar(jsonEncode(m));
    fit.loadFromStore();
    fit.persistNow();
    final guardado = _stored(prefs);
    final perdidas = _perdidas(m, guardado);
    print(
      'Variante con valores que 1.3.1 no acepta al cargar; diferencias tras guardar:\n  ${perdidas.join('\n  ')}',
    );
    expect(
      (guardado['measures'] as List).where((e) => (e as Map)['k'] == 'biceps'),
      isEmpty,
      reason: 'medida con clave fuera de kMeasureKeys: se descarta (fit_state.dart:322)',
    );
    expect(
      (guardado['exRest'] as Map)['SpYC0Kp'],
      15,
      reason: 'descanso por ejercicio "apagado" (0 s) vuelve como 15 s (fit_state.dart:282)',
    );
    expect(
      guardado['alarmSound'],
      isNull,
      reason: 'si el archivo de alarma no se encuentra, la preferencia se borra (fit_state.dart:79-82)',
    );
    expect(guardado['alarmSoundName'], isNull);
    expect(
      guardado['shots'] as List,
      hasLength(1),
      reason: 'foto con pose fuera de kPoses: se descarta (progress_shot.dart:57, fit_state.dart:301)',
    );
    expect(perdidas, hasLength(5), reason: 'no tiene que cambiar nada más que esos cinco puntos');
  });

  test('caracterización: un id de catálogo que ya no existe queda guardado pero oculto', () async {
    final m = _fixture();
    for (final k in _liveKeys) {
      m.remove(k);
    }
    final r0 = (m['routines'] as List)[0] as Map<String, dynamic>;
    r0['ex'] = ['EIeI8Vf', 'id-que-ya-no-existe', 'qXTaZnJ'];
    r0
      ..remove('s')
      ..remove('c')
      ..remove('p');
    await sembrar(jsonEncode(m));
    fit.loadFromStore();
    final r = fit.routines.first;
    expect(r.exerciseIds, ['EIeI8Vf', 'id-que-ya-no-existe', 'qXTaZnJ']);
    expect(
      fit.routineExercises(r).map((e) => e.id),
      ['EIeI8Vf', 'qXTaZnJ'],
      reason: 'la pantalla de la rutina lo oculta (routines_state.dart:90-97)',
    );
    fit.persistNow();
    expect(
      ((_stored(prefs)['routines'] as List)[0] as Map)['ex'],
      ['EIeI8Vf', 'id-que-ya-no-existe', 'qXTaZnJ'],
      reason: 'no se borra del disco: reaparecería si el id vuelve al catálogo',
    );

    // Arrastrar el primer ejercicio visible al final: ReorderableListView llama onReorder(0, 2).
    fit.reorderRoutineExercise(r.id, 0, 2);
    expect(
      fit.routineExercises(r).map((e) => e.id),
      ['EIeI8Vf', 'qXTaZnJ'],
      reason:
          'con un id oculto, los índices de la UI (routine_edit_screen.dart:262-265) no coinciden '
          'con exerciseIds: el arrastre no tiene efecto visible',
    );
    expect(r.exerciseIds, ['id-que-ya-no-existe', 'EIeI8Vf', 'qXTaZnJ']);
  });

  test(
    'un tipo inesperado ya no corta el arranque y el original queda en una copia antes de guardar',
    () async {
      final m = _fixture();
      final series = ((((m['sessions'] as List)[0] as Map)['ex'] as List)[0] as Map)['s'] as List;
      (series[1] as Map)['r'] = '8';
      final crudo = jsonEncode(m);
      await sembrar(crudo);
      expect(
        () => fit.loadFromStore(),
        returnsNormally,
        reason: 'en 151fd24 lanzaba TypeError y main.dart:32 cortaba main() antes de runApp',
      );
      expect(prefs.getString(kKey), crudo, reason: 'cargar no escribe');
      final rescate = Store.instance.rescue!;
      expect(rescate.reason, 'itemsSkipped');
      expect(Store.instance.readRescueCopy(rescate.slot), crudo);
      expect(fit.routines, hasLength((m['routines'] as List).length));
      expect(
        fit.sessions,
        hasLength((m['sessions'] as List).length - 1),
        reason: 'se saltea solo la sesión con la serie rara; las demás y lo que sigue se cargan',
      );

      fit.persistNow();
      expect(prefs.getString(kKey), isNot(crudo), reason: 'la app quedó usable y vuelve a guardar');
      expect(Store.instance.readRescueCopy(rescate.slot), crudo, reason: 'la copia sobrevive al guardado');

      await prefs.setString(kKey, kFixture131);
      fit.loadFromStore();
      fit.persistNow();
      expect(_stored(prefs)['onboarded'], isTrue, reason: 'una carga válida posterior recupera todo');
    },
  );

  test('JSON ilegible: arranca vacía, pero el original queda en una copia de rescate', () async {
    fit.resetAllData();
    const corrupto = '{"profile":{"name":"Braian Prueba"},"sessions":[{"d":"2026-10-20T18:30:00.000"';
    await prefs.setString(kKey, corrupto);
    expect(Store.instance.load(), isEmpty, reason: 'load() sigue devolviendo {} si jsonDecode falla');
    final rescate = Store.instance.rescue!;
    expect(rescate.reason, 'unreadable');
    expect(Store.instance.readRescueCopy(rescate.slot), corrupto);
    fit.loadFromStore();
    expect(fit.onboarded, isFalse, reason: 'se muestra el onboarding, como en una instalación nueva');
    expect(fit.sessions, isEmpty);
    expect(prefs.getString(kKey), corrupto, reason: 'hasta acá el texto original sigue en disco');

    // Lo mismo que hace app_shell.dart:168-173 al pasar a segundo plano (inactive/paused).
    fit.persistNow();
    expect(prefs.getString(kKey), isNot(corrupto));
    expect(Store.instance.readRescueCopy(rescate.slot), corrupto, reason: 'el original ya no se pierde');
  });

  test(
    'actualización simulada: blob 1.3.1 -> código nuevo -> guardar -> reinicio -> recarga sin pérdidas',
    () async {
      await sembrar(kFixture131);
      fit.loadFromStore();
      fit.persistNow();
      final guardado = prefs.getString(kKey)!;

      fit.saveAndExit();
      fit.resetAllData();
      SharedPreferences.setMockInitialValues({kKey: guardado});
      Store.instance.debugReset();
      await Store.instance.init();
      prefs = await SharedPreferences.getInstance();

      fit.loadFromStore();
      expect(fit.routines, hasLength((_fixture()['routines'] as List).length));
      expect(fit.sessions, hasLength((_fixture()['sessions'] as List).length));
      fit.persistNow();
      final recargado = _stored(prefs);
      expect(recargado[kSchemaVersionKey], kStoreSchemaVersion);
      final perdidas = _perdidas(_fixture(), recargado);
      expect(perdidas, isEmpty, reason: perdidas.join('\n'));
      expect(prefs.getKeys(), {kKey}, reason: 'misma clave única que 1.3.1');
      expect(Store.instance.rescue, isNull);
    },
  );
}
