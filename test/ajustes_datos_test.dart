// Ajustes → DATOS de punta a punta (1.4.0): Exportar copia, Importar copia y Borrar todos mis datos, tocados desde la
// pantalla. El menú de compartir, el selector de archivos y las carpetas del sistema son falsos; los archivos son reales,
// en carpetas temporales.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/app/infyter_app.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/models/workout.dart';
import 'package:infyter/services/alarm_store.dart';
import 'package:infyter/services/backup_zip.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/services/media_store.dart';
import 'package:infyter/services/progress_reminder.dart';
import 'package:infyter/services/step_source.dart';
import 'package:infyter/services/step_source_android.dart';
import 'package:infyter/services/step_source_ios.dart';
import 'package:infyter/services/train_reminder.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:infyter/state/steps_card_pref.dart';
import 'package:infyter/state/steps_range.dart';
import 'package:infyter/theme/app_colors.dart';
import 'package:infyter/widgets/ui_kit.dart' show titleCase;
import 'package:shared_preferences/shared_preferences.dart';
// La interfaz de plataforma de shared_preferences (dependencia transitiva) permite simular el disco lleno.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'formato_131_test.dart' show kFixture131;
import 'letra_grande_util.dart';

const _shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');
const _blob = 'flutter.gymmane_v1';

/// El disco no acepta el blob principal, como commit() sin espacio.
class _DiscoLleno extends InMemorySharedPreferencesStore {
  _DiscoLleno(super.data) : super.withData();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      key == _blob ? false : super.setValue(valueType, key, value);
}

/// Devuelve los bytes de [archivo] como si la persona lo hubiera elegido; null = canceló.
class _Selector extends FilePicker {
  ({String name, List<int> bytes})? archivo;
  int pedidos = 0;
  int limpiezas = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    pedidos++;
    final a = archivo;
    if (a == null) return null;
    return FilePickerResult([PlatformFile(name: a.name, size: a.bytes.length, bytes: Uint8List.fromList(a.bytes))]);
  }

  @override
  Future<bool?> clearTemporaryFiles() async {
    limpiezas++;
    return true;
  }
}

class _Share {
  _Share(this.args, this.files);

  final Map<Object?, Object?> args;
  final Map<String, List<int>> files;

  String get name => files.keys.first;
  String get mime => (args['mimeTypes'] as List).first as String;
  String? get subject => args['subject'] as String?;
}

LoggedSession _sesion(String nombre, int reps) => LoggedSession(DateTime(2026, 11, 10, 10), 1800, [
  LoggedExercise('bench_press', nombre, 'chest', [LoggedSet(reps, 60)]),
]);

late Directory _tmp;
late Directory _media;
late Directory _alarmas;
late Directory _rescate;
late List<_Share> _shares;
late _Selector _selector;
late FakeStepSource _fuente;

Future<void> _pasar(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _esperar(WidgetTester tester, bool Function() hasta) async {
  for (var i = 0; i < 200 && !hasta(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(hasta(), isTrue);
}

Future<void> _abrirAjustes(WidgetTester tester) async {
  fit.onboarded = true;
  fit.session = null;
  fit.resetRoute('home');
  fit.pushRoute('preferences');
  await tester.pumpWidget(const InfyterApp());
  await _pasar(tester, 12);
  await tester.ensureVisible(find.text(t.resetData));
  await _pasar(tester, 3);
}

Future<void> _tocar(WidgetTester tester, String texto) async {
  await tester.ensureVisible(find.text(texto));
  await _pasar(tester, 2);
  await tester.tap(find.text(texto));
  await _pasar(tester);
}

Future<void> _cerrar(WidgetTester tester) async {
  fit.saveAndExit();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

Future<String?> _blobEnDisco() async => (await SharedPreferencesStorePlatform.instance.getAll())[_blob] as String?;

Future<List<String>> _sesionesEnDisco() async {
  final raw = await _blobEnDisco();
  final data = raw == null ? const <String, dynamic>{} : jsonDecode(raw) as Map<String, dynamic>;
  return [
    for (final s in (data['sessions'] as List? ?? const []))
      for (final e in (s as Map)['ex'] as List) (e as Map)['n'] as String,
  ];
}

List<String> _sesionesEnMemoria() => [
  for (final s in fit.sessions)
    for (final e in s.exercises) e.name,
];

List<int> _zip(Map<String, dynamic> json, {Map<String, List<int>> archivos = const {}}) {
  final archive = Archive();
  archivos.forEach((path, bytes) => archive.addFile(ArchiveFile.noCompress(path, bytes.length, bytes)));
  archive.addFile(ArchiveFile.string(kBackupJsonEntry, jsonEncode(json)));
  return ZipEncoder().encodeBytes(archive);
}

Map<String, dynamic> _copiaB() => {
  'onboarded': true,
  'language': 'es',
  'sessions': [_sesion('Press de la copia', 5).toJson()],
};

/// Lo que la persona tiene hoy: un entrenamiento, una foto de ejercicio guardada y todo en disco.
Future<String> _estadoActual(WidgetTester tester) async {
  fit.profile.since = DateTime(2026, 9, 1);
  fit.onboarded = true;
  fit.sessions
    ..clear()
    ..add(_sesion('Press de hoy', 8));
  final String foto = (await tester.runAsync<String?>(() => MediaStore.saveBytes('bench_press', 'png', Uint8List.fromList([1, 2, 3]))))!;
  fit.exerciseMedia['bench_press'] = foto;
  await tester.runAsync(() => fit.saveNow());
  return foto;
}

Future<void> _importar(WidgetTester tester, String nombre, List<int> bytes) async {
  _selector.archivo = (name: nombre, bytes: bytes);
  await _tocar(tester, t.importBackup);
  expect(find.text(t.importHint), findsOneWidget);
  await tester.tap(find.text(titleCase(t.chooseFile)));
  await _pasar(tester);
}

Future<void> _esperarAviso(WidgetTester tester, String aviso) =>
    _esperar(tester, () => find.text(aviso).evaluate().isNotEmpty);

void main() {
  setUpAll(cargarNunito);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = InMemorySharedPreferencesStore.empty();
    Store.instance.debugReset();
    await Store.instance.init();
    _tmp = Directory.systemTemp.createTempSync('infyter_datos_tmp');
    _media = Directory.systemTemp.createTempSync('infyter_datos_media');
    _alarmas = Directory.systemTemp.createTempSync('infyter_datos_alarm');
    _rescate = Directory.systemTemp.createTempSync('infyter_datos_rescate');
    MediaStore.directory = _media.path;
    AlarmStore.directory = _alarmas.path;
    Store.rescueDirectory = _rescate.path;
    ProgressReminder.instance.enabled = false;
    TrainReminder.instance.enabled = false;
    _fuente = FakeStepSource()..available = true;
    fit.resetAllData();
    fit.stepSource = _fuente;
    fit.setLanguage('es');
    fit.startCountdown = false;
    _shares = [];
    _selector = _Selector();
    FilePicker.platform = _selector;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_pathChannel, (call) async => _tmp.path);
    messenger.setMockMethodCallHandler(_shareChannel, (call) async {
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      final files = <String, List<int>>{
        for (final p in (args['paths'] as List?) ?? const [])
          (p as String).split(RegExp(r'[/\\]')).last: File(p).readAsBytesSync(),
      };
      _shares.add(_Share(args, files));
      return 'com.example.app';
    });
  });

  tearDown(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_pathChannel, null);
    messenger.setMockMethodCallHandler(_shareChannel, null);
    fit.saveAndExit();
    fit.startCountdown = true;
    fit.stepSource = const UnavailableStepSource();
    fit.sessions.clear();
    fit.exerciseMedia.clear();
    MediaStore.directory = null;
    AlarmStore.directory = null;
    Store.rescueDirectory = null;
    for (final d in [_tmp, _media, _alarmas, _rescate]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  testWidgets('DATOS: CSV, Exportar copia, Importar copia y, al final y en rojo, Borrar todos mis datos', (tester) async {
    await _abrirAjustes(tester);
    final filas = [t.exportCsv, t.exportBackup, t.importBackup, t.resetData];
    final alturas = [for (final f in filas) tester.getTopLeft(find.text(f)).dy];
    expect(alturas, [...alturas]..sort());
    expect(t.exportBackup, 'Exportar copia (ZIP)');
    final borrar = tester.widget<Text>(find.text(t.resetData));
    expect(borrar.style?.color, tester.element(find.text(t.resetData)).gc.danger);
    final importar = tester.widget<Text>(find.text(t.importBackup));
    expect(importar.style?.color, isNot(tester.element(find.text(t.importBackup)).gc.danger));
    expect(find.text(t.importFromApp), findsNothing);
    await _cerrar(tester);
  });

  testWidgets('Exportar copia comparte un ZIP con los datos y el asunto en el idioma de la app', (tester) async {
    await _estadoActual(tester);
    await _abrirAjustes(tester);
    await _tocar(tester, t.exportBackup);
    await _esperar(tester, () => _shares.isNotEmpty);
    final s = _shares.single;
    expect(s.name, matches(RegExp(r'^infyter-backup-\d{4}-\d{2}-\d{2}\.zip$')));
    expect(s.mime, 'application/zip');
    expect(s.subject, 'Copia de seguridad de Infyter');
    final archive = ZipDecoder().decodeBytes(s.files.values.single);
    final json = jsonDecode(utf8.decode(archive.findFile(kBackupJsonEntry)!.readBytes()!)) as Map<String, dynamic>;
    expect((json['sessions'] as List), hasLength(1));
    expect((json['media'] as Map).values.single, startsWith('media/images/'));
    expect(archive.files.where((f) => f.name.startsWith('media/images/')), hasLength(1));
    await _cerrar(tester);
  });

  testWidgets('el asunto de la copia y del CSV sale en el idioma de la app', (tester) async {
    await _estadoActual(tester);
    fit.setLanguage('en');
    await _abrirAjustes(tester);
    await _tocar(tester, t.exportBackup);
    await _esperar(tester, () => _shares.length == 1);
    await _tocar(tester, t.exportCsv);
    await _esperar(tester, () => _shares.length == 2);
    expect(_shares[0].subject, 'Infyter backup');
    expect(_shares[1].subject, 'Infyter workouts');
    expect(_shares[1].name, matches(RegExp(r'^infyter-workouts-\d{4}-\d{2}-\d{2}\.csv$')));
    expect(utf8.decode(_shares[1].files.values.single), contains('Press de hoy'));
    fit.setLanguage('ja');
    await tester.pump();
    await _tocar(tester, t.exportCsv);
    await _esperar(tester, () => _shares.length == 3);
    expect(_shares[2].subject, 'Infyterのワークアウト');
    await _cerrar(tester);
  });

  testWidgets('Importar copia con un ZIP valido reemplaza los datos y lo deja guardado', (tester) async {
    final fotoVieja = await _estadoActual(tester);
    await _abrirAjustes(tester);
    final copia = _copiaB()..['media'] = {'bench_press': 'media/images/press.png'};
    await _importar(tester, 'infyter-backup-2026-11-01.zip', _zip(copia, archivos: {'media/images/press.png': [9, 9, 9, 9]}));
    await _esperarAviso(tester, t.backupImported);
    expect(_sesionesEnMemoria(), ['Press de la copia']);
    expect(await tester.runAsync(_sesionesEnDisco), ['Press de la copia']);
    final fotoNueva = fit.exerciseMedia['bench_press']!;
    expect(fotoNueva, isNot(fotoVieja));
    expect(File('${_media.path}/$fotoNueva').readAsBytesSync(), [9, 9, 9, 9]);
    expect(File('${_media.path}/$fotoVieja').existsSync(), isFalse);
    expect(_selector.limpiezas, 1);
    await _cerrar(tester);
  });

  testWidgets('Importar copia con un JSON valido reemplaza los datos y lo deja guardado', (tester) async {
    await _estadoActual(tester);
    await _abrirAjustes(tester);
    await _importar(tester, 'infyter-backup.json', utf8.encode(jsonEncode(_copiaB())));
    await _esperarAviso(tester, t.backupImported);
    expect(_sesionesEnMemoria(), ['Press de la copia']);
    expect(await tester.runAsync(_sesionesEnDisco), ['Press de la copia']);
    await _cerrar(tester);
  });

  for (final (caso, nombre, bytes) in [
    ('un ZIP dañado', 'roto.zip', [0x50, 0x4B, 0x03, 0x04, 1, 2, 3, 4, 5, 6, 7, 8]),
    ('un ZIP sin la copia adentro', 'otro.zip', ZipEncoder().encodeBytes(Archive()..addFile(ArchiveFile.string('a.txt', 'hola')))),
    ('un JSON cortado', 'roto.json', utf8.encode('{"sessions": [{"d": "2026-')),
    ('un JSON con un tipo inesperado', 'raro.json', utf8.encode('{"sessions": "no es una lista"}')),
    ('un archivo vacío', 'vacio.json', <int>[]),
  ]) {
    testWidgets('Importar copia con $caso avisa y no toca los datos actuales', (tester) async {
      final foto = await _estadoActual(tester);
      await _abrirAjustes(tester);
      await _importar(tester, nombre, bytes);
      await _esperarAviso(tester, t.backupFailed);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
      await _pasar(tester);
      expect(_sesionesEnMemoria(), ['Press de hoy']);
      expect(fit.exerciseMedia['bench_press'], foto);
      expect(await tester.runAsync(_sesionesEnDisco), ['Press de hoy']);
      final guardado = jsonDecode((await tester.runAsync<String?>(_blobEnDisco))!) as Map<String, dynamic>;
      expect(guardado['media'], {'bench_press': foto});
      expect(File('${_media.path}/$foto').existsSync(), isTrue);
      expect(_media.listSync(), hasLength(1));
      await _cerrar(tester);
    });
  }

  testWidgets('Importar copia de la 1.3.x: entra todo y quedan los pasos de este teléfono', (tester) async {
    await _estadoActual(tester);
    final hoy = stepsDayKey(DateTime.now());
    fit.steps[hoy] = 4321;
    fit.stepGoal = 12000;
    await tester.runAsync(() => fit.saveNow());
    await _abrirAjustes(tester);
    final copia131 = jsonDecode(kFixture131) as Map<String, dynamic>;
    expect(copia131.containsKey('steps'), isFalse);
    await _importar(tester, 'infyter-backup-2026-10-30.zip', _zip(copia131));
    await _esperarAviso(tester, t.backupImported);
    expect(fit.profile.name, 'Braian Prueba');
    expect(fit.units, 'lb');
    expect(fit.sessions, hasLength((copia131['sessions'] as List).length));
    expect(fit.steps[hoy], 4321);
    expect(fit.stepGoal, 12000);
    final guardado = jsonDecode((await tester.runAsync<String?>(_blobEnDisco))!) as Map<String, dynamic>;
    expect((guardado['profile'] as Map)['name'], 'Braian Prueba');
    await _cerrar(tester);
  });

  testWidgets('Importar copia JSON con el disco lleno vuelve a lo de antes', (tester) async {
    await _estadoActual(tester);
    final antes = await tester.runAsync<String?>(_blobEnDisco);
    await _abrirAjustes(tester);
    final disco = (await tester.runAsync(() => SharedPreferencesStorePlatform.instance.getAll()))!;
    SharedPreferencesStorePlatform.instance = _DiscoLleno(disco);
    Store.instance.debugReset();
    await tester.runAsync(() => Store.instance.init());
    await _importar(tester, 'copia.json', utf8.encode(jsonEncode(_copiaB())));
    await _esperarAviso(tester, t.backupFailed);
    expect(_sesionesEnMemoria(), ['Press de hoy']);
    expect(await tester.runAsync<String?>(_blobEnDisco), antes);
    await _cerrar(tester);
  });

  testWidgets('Importar copia cancelado en la confirmacion no abre el selector ni toca nada', (tester) async {
    await _estadoActual(tester);
    await _abrirAjustes(tester);
    await _tocar(tester, t.importBackup);
    await tester.tap(find.text(titleCase(t.cancel)));
    await _pasar(tester);
    expect(_selector.pedidos, 0);
    expect(_sesionesEnMemoria(), ['Press de hoy']);
    await _cerrar(tester);
  });

  group('Borrar todos mis datos', () {
    /// Todo lo que el teléfono guarda de la persona, fuera y dentro del estado.
    Future<Map<String, File>> llenar(WidgetTester tester) async {
      await _estadoActual(tester);
      fit.steps[stepsDayKey(DateTime.now())] = 7000;
      fit.stepGoal = 15000;
      fit.stepsOn = true;
      fit.stepsAskedAt = 1;
      fit.units = 'lb';
      fit.themePref = 'light';
      fit.restSeconds = 150;
      fit.photoIntervalDays = 7;
      fit.alarmStyle = 'loud';
      final String alarma = (await tester.runAsync<String?>(() => AlarmStore.saveBytes('mia.mp3', Uint8List.fromList([7, 7]))))!;
      fit.setAlarmSound(alarma, 'Mi alarma');
      Store.instance.keepCopy(fit.backupSnapshot());
      Store.instance.setNote('entrance_home', '2026-11-27');
      await tester.runAsync(() => StepsCardPref.setHidden(true));
      await tester.runAsync(() async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('infyter_steps_ios_start_v1', 1700000000000);
      });
      await tester.runAsync(() => fit.saveNow());
      File archivo(String ruta) => File('${_tmp.path}/$ruta')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1]);
      return {
        'copia': archivo('infyter-backup-2026-11-01.zip'),
        'csv': archivo('infyter-workouts-2026-11-01.csv'),
        'tarjeta': archivo('infyter-streak.png'),
        'progreso': archivo('progress_export/infyter-progreso-2026-11-01_2026-11-27.pdf'),
        'compartido': archivo('share_plus/infyter-progreso-2026-11-01_2026-11-27.pdf'),
        'copiaCompartida': archivo('share_plus/infyter-backup-2026-11-01.zip'),
        'ajeno': archivo('otra-app.tmp'),
      };
    }

    Future<void> borrar(WidgetTester tester, {String? confirmar}) async {
      await _tocar(tester, t.resetData);
      expect(find.text(t.resetTitle), findsOneWidget);
      expect(find.text(t.resetBody), findsOneWidget);
      await tester.tap(find.text(titleCase(confirmar ?? t.resetConfirm)));
      await _pasar(tester);
    }

    testWidgets('deja la app como recién instalada y apaga el conteo', (tester) async {
      final archivos = await llenar(tester);
      await _abrirAjustes(tester);
      await borrar(tester);
      await _esperarAviso(tester, t.resetDone);
      await _esperar(tester, () => _media.listSync().isEmpty && _alarmas.listSync().isEmpty);
      await _esperar(tester, () => _selector.limpiezas == 1);

      final nueva = FitState();
      expect(fit.toJson(), nueva.toJson());
      nueva.dispose();
      expect(fit.onboarded, isFalse);
      expect(fit.steps, isEmpty);
      expect(fit.stepGoal, kDefaultStepGoal);
      expect(fit.stepsOn, isFalse);
      expect(_fuente.forgotten, 1);
      final guardado = jsonDecode((await tester.runAsync<String?>(_blobEnDisco))!) as Map<String, dynamic>;
      expect(guardado['sessions'], isEmpty);
      expect(guardado['steps'], isEmpty);
      expect(guardado['stepGoal'], kDefaultStepGoal);
      expect(guardado['stepsOn'], isFalse);
      expect(Store.instance.rescueCopies, isEmpty);
      expect(_rescate.existsSync() && _rescate.listSync().isNotEmpty, isFalse);
      expect(Store.instance.note('entrance_home'), isNull);
      expect(StepsCardPref.hidden.value, isFalse);
      final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
      expect(prefs.containsKey('infyter_steps_card_hidden_v1'), isFalse);
      for (final nombre in ['copia', 'csv', 'tarjeta', 'progreso', 'compartido', 'copiaCompartida']) {
        expect(archivos[nombre]!.existsSync(), isFalse, reason: nombre);
      }
      expect(archivos['ajeno']!.existsSync(), isTrue);
      expect(_selector.limpiezas, 1);
      expect(fit.language, 'es');
      await _cerrar(tester);
    });

    testWidgets('cancelado no borra nada', (tester) async {
      final archivos = await llenar(tester);
      final antes = await tester.runAsync<String?>(_blobEnDisco);
      await _abrirAjustes(tester);
      await borrar(tester, confirmar: t.cancel);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      expect(_sesionesEnMemoria(), ['Press de hoy']);
      expect(await tester.runAsync<String?>(_blobEnDisco), antes);
      expect(_media.listSync(), hasLength(1));
      expect(archivos['copia']!.existsSync(), isTrue);
      expect(_fuente.forgotten, 0);
      expect(fit.stepsOn, isTrue);
      await _cerrar(tester);
    });

    testWidgets('con el disco lleno avisa y no borra nada', (tester) async {
      final archivos = await llenar(tester);
      final antes = await tester.runAsync<String?>(_blobEnDisco);
      await _abrirAjustes(tester);
      final disco = (await tester.runAsync(() => SharedPreferencesStorePlatform.instance.getAll()))!;
      SharedPreferencesStorePlatform.instance = _DiscoLleno(disco);
      Store.instance.debugReset();
      await tester.runAsync(() => Store.instance.init());
      await borrar(tester);
      await _esperarAviso(tester, t.resetFailed);
      expect(_sesionesEnMemoria(), ['Press de hoy']);
      expect(fit.stepsOn, isTrue);
      expect(fit.stepGoal, 15000);
      expect(fit.units, 'lb');
      expect(fit.onboarded, isTrue);
      expect(await tester.runAsync<String?>(_blobEnDisco), antes);
      expect(_media.listSync(), hasLength(1));
      expect(_alarmas.listSync(), hasLength(1));
      expect(Store.instance.rescueCopies, isNotEmpty);
      expect(archivos['copia']!.existsSync(), isTrue);
      expect(_fuente.forgotten, 0);
      await _cerrar(tester);
    });
  });

  group('Borrar todos mis datos y las marcas de la fuente de pasos', () {
    late List<String> llamadas;

    setUp(() {
      llamadas = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel(StepChannel.name),
        (call) async {
          llamadas.add(call.method);
          return null;
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(StepChannel.name), null);
    });

    test('Android: borra el ancla y las marcas del permiso', () async {
      fit.stepSource = AndroidStepSource();
      fit.stepsOn = true;
      expect(await fit.deleteAllData(), isTrue);
      expect(llamadas, contains(StepChannel.forget));
      expect(fit.stepsOn, isFalse);
    });

    test('iOS: marca un arranque nuevo, así no vuelven los días borrados', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('infyter_steps_ios_start_v1', 0);
      fit.stepSource = IosStepSource();
      fit.stepsOn = true;
      expect(await fit.deleteAllData(), isTrue);
      expect(prefs.getInt('infyter_steps_ios_start_v1'), -1);
      expect(fit.stepsOn, isFalse);
    });
  });
}
