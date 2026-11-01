// Ajustes → Sonido de alarma → Elegir: si la persona sale de Ajustes mientras se copia el sonido nuevo, la elección
// igual queda registrada y guardada (sesión 28, pendiente de la revisión de la s27). Antes, la copia terminaba, el
// sonido anterior ya estaba borrado y la pantalla, al no estar, volvía sin registrar nada: al reabrir sonaba la
// alarma por defecto. El selector de archivos y el audio son falsos; la copia es real, en carpetas temporales.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/app/infyter_app.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/screens/settings_screen.dart';
import 'package:infyter/services/alarm_store.dart';
import 'package:infyter/services/local_store.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Devuelve siempre el mismo archivo, como si la persona lo hubiera elegido.
class _SelectorFalso extends FilePicker {
  _SelectorFalso(this.archivo);
  final File archivo;

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
  }) async =>
      FilePickerResult([PlatformFile(path: archivo.path, name: 'campana.ogg', size: archivo.lengthSync())]);
}

class _AudioGlobalFalso implements GlobalAudioplayersPlatformInterface {
  @override
  Future<void> init() async {}
  @override
  Future<void> setGlobalAudioContext(AudioContext ctx) async {}
  @override
  Future<void> emitGlobalLog(String message) async {}
  @override
  Future<void> emitGlobalError(String code, String message) async {}
  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => const Stream.empty();
}

// Un reproductor que "lee" cualquier archivo como uno de 2 segundos (RestAlarm.probeDuration).
class _AudioFalso extends AudioplayersPlatformInterface {
  final _eventos = <String, StreamController<AudioEvent>>{};

  @override
  Future<void> create(String playerId) async => _eventos[playerId] = StreamController<AudioEvent>.broadcast();
  @override
  Stream<AudioEvent> getEventStream(String playerId) => _eventos[playerId]!.stream;
  @override
  Future<void> setSourceUrl(String playerId, String url, {bool? isLocal, String? mimeType}) async =>
      _eventos[playerId]!.add(const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true));
  @override
  Future<int?> getDuration(String playerId) async => 2000;
  @override
  Future<int?> getCurrentPosition(String playerId) async => 0;
  @override
  Future<void> dispose(String playerId) async => _eventos.remove(playerId)?.close();
  // setReleaseMode, release y el resto: no hacen nada.
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

// La copia del sonido elegido espera a que el test abra la compuerta; después copia de verdad. Así se puede salir de
// Ajustes justo mientras se copia, sin depender de cuánto tarda el disco.
final class _CopiaEnPausa extends IOOverrides {
  _CopiaEnPausa(this.origen);
  final String origen;
  final abrir = Completer<void>();
  bool empezo = false;

  @override
  File createFile(String path) =>
      path == origen ? _ArchivoEnPausa(super.createFile(path), this) : super.createFile(path);
}

class _ArchivoEnPausa implements File {
  _ArchivoEnPausa(this._real, this._compuerta);
  final File _real;
  final _CopiaEnPausa _compuerta;

  @override
  String get path => _real.path;

  @override
  Future<File> copy(String newPath) async {
    _compuerta.empezo = true;
    await _compuerta.abrir.future;
    return _real.copy(newPath);
  }

  // importSound solo copia el archivo elegido; cualquier otro uso rompería el test a la vista.
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory alarmas;
  late Directory origen;
  late File elegido;

  setUpAll(() {
    GlobalAudioplayersPlatformInterface.instance = _AudioGlobalFalso();
    AudioplayersPlatformInterface.instance = _AudioFalso();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.instance.init();
    fit.resetAllData();
    alarmas = await Directory.systemTemp.createTemp('infyter_alarma_ajustes');
    origen = await Directory.systemTemp.createTemp('infyter_alarma_ajustes_origen');
    AlarmStore.directory = alarmas.path;
    File('${alarmas.path}/alarm-1.mp3').writeAsBytesSync([7, 7, 7]);
    fit.setAlarmSound('alarm-1.mp3', 'Mi alarma');
    elegido = File('${origen.path}/campana.ogg')..writeAsBytesSync([1, 2, 3, 4]);
    FilePicker.platform = _SelectorFalso(elegido);
    fit.onboarded = true;
    fit.session = null;
    fit.resetRoute('home');
    fit.pushRoute('preferences'); // Ajustes (la ruta 'settings' es el perfil)
  });

  tearDown(() async {
    IOOverrides.global = null;
    AlarmStore.directory = null;
    fit.resetRoute('home');
    for (final d in [alarmas, origen]) {
      if (d.existsSync()) await d.delete(recursive: true);
    }
  });

  List<String> archivos() => [
    for (final f in alarmas.listSync())
      if (f is File) f.uri.pathSegments.last,
  ]..sort();

  // Deja correr E/S real y frames, alternados, hasta que se cumpla [listo].
  Future<void> esperar(WidgetTester tester, bool Function() listo) async {
    for (var i = 0; i < 100 && !listo(); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('si se sale de Ajustes mientras se copia el sonido, la alarma nueva queda elegida y guardada', (
    tester,
  ) async {
    final compuerta = _CopiaEnPausa(elegido.path);
    IOOverrides.global = compuerta;
    await tester.pumpWidget(const InfyterApp());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.scrollUntilVisible(find.text(t.alarmSound), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text(t.alarmSound));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.alarmChoose));

    // Elegir el archivo y medir su duración son falsos; después empieza la copia, que queda esperando.
    await esperar(tester, () => compuerta.empezo);
    expect(compuerta.empezo, isTrue, reason: 'la copia del sonido nuevo empezó');
    expect(archivos(), ['alarm-1.mp3']);

    fit.popRoute();
    await tester.pumpAndSettle();
    // Ni en pantalla ni guardada fuera de escena: el widget de Ajustes ya no existe.
    expect(find.byType(SettingsScreen, skipOffstage: false), findsNothing);

    compuerta.abrir.complete();
    await esperar(tester, () => !archivos().contains('alarm-1.mp3'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }

    final nuevo = archivos();
    expect(nuevo, hasLength(1));
    expect(nuevo.single, isNot('alarm-1.mp3'));
    expect(nuevo.single, endsWith('.ogg'));
    expect(fit.alarmSound, nuevo.single);
    expect(fit.alarmSoundName, 'campana');
    final prefs = await SharedPreferences.getInstance();
    final guardado = jsonDecode(prefs.getString('gymmane_v1')!) as Map<String, dynamic>;
    expect(guardado['alarmSound'], nuevo.single);
  });
}
