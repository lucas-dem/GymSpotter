import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/app/infyter_app.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/screens/progress_export_sheet.dart';
import 'package:infyter/models/workout.dart';
import 'package:infyter/state/fit_state.dart';
import 'package:infyter/state/steps_range.dart';
import 'package:infyter/widgets/ui_kit.dart' show TinySwitch;
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'letra_grande_util.dart';

const _shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

class _Share {
  _Share(this.args, this.files);

  final Map<Object?, Object?> args;
  final Map<String, List<int>> files;

  String? get text => args['text'] as String?;
  String get mime => (args['mimeTypes'] as List).first as String;
  String get name => files.keys.first;
}

DateTime _hoy = DateTime(2026, 11, 15);

DateTime _dia(int atras) => DateTime(_hoy.year, _hoy.month, _hoy.day - atras);

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

LoggedSession _sesion(int atras) => LoggedSession(_dia(atras).add(const Duration(hours: 10)), 3000, [
  LoggedExercise('bench_press', 'Bench press', 'chest', [LoggedSet(8, 60)]),
]);

late Directory _tmp;
late String _progressDir;
late String _sharedDir;
late List<_Share> _shares;
late List<String> _clipboard;
String _shareAnswer = 'com.example.app';
bool _shareFails = false;

void _datos(List<int> sesionesHace) {
  fit.sessions
    ..clear()
    ..addAll(sesionesHace.map(_sesion));
  fit.steps.clear();
  fit.stepsFrom.clear();
  fit.steps[stepsDayKey(_dia(0))] = 5000;
}

Future<void> _abrir(WidgetTester tester) async {
  fit.route = 'progress';
  await tester.pumpWidget(const InfyterApp());
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _pasar(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _esperar(WidgetTester tester, bool Function() hasta) async {
  for (var i = 0; i < 200 && !hasta(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(hasta(), isTrue);
}

Future<void> _abrirVentana(WidgetTester tester) async {
  showProgressExportSheet(tester.element(find.byType(Scaffold).first), today: _hoy);
  await _pasar(tester);
}

Future<void> _cerrarVentana(WidgetTester tester) async {
  Navigator.of(tester.element(find.text('Formato'))).pop();
  await _pasar(tester);
}

Future<void> _exportar(WidgetTester tester) async {
  final antes = _shares.length;
  await tester.tap(find.text('Exportar'));
  await _esperar(tester, () => _shares.length > antes);
  await _pasar(tester);
}

Future<void> _cerrar(WidgetTester tester) async {
  fit.saveAndExit();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 3));
}

void main() {
  setUpAll(() async {
    await cargarNunito();
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fit.saveAndExit();
    fit.onboarded = true;
    fit.startCountdown = false;
    fit.setLanguage('es');
    _hoy = DateTime(2026, 11, 15);
    _tmp = Directory.systemTemp.createTempSync('infyter_export_test');
    _progressDir = '${_tmp.path}/progress_export';
    _sharedDir = '${_tmp.path}/share_plus';
    File('${_tmp.path}/share_plus/infyter-streak.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1]);
    _shares = [];
    _clipboard = [];
    _shareAnswer = 'com.example.app';
    _shareFails = false;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_pathChannel, (call) async => _tmp.path);
    messenger.setMockMethodCallHandler(_shareChannel, (call) async {
      if (_shareFails) throw PlatformException(code: 'boom');
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      final files = <String, List<int>>{
        for (final p in (args['paths'] as List?) ?? const [])
          (p as String).split('/').last: File(p).readAsBytesSync(),
      };
      for (final e in files.entries) {
        File('${_tmp.path}/share_plus/${e.key}')
          ..createSync(recursive: true)
          ..writeAsBytesSync(e.value);
      }
      _shares.add(_Share(args, files));
      return _shareAnswer;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        _clipboard.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
  });

  tearDown(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_pathChannel, null);
    messenger.setMockMethodCallHandler(_shareChannel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
    fit.saveAndExit();
    fit.bgPattern = 'dynamic';
    fit.startCountdown = true;
    fit.sessions.clear();
    fit.steps.clear();
  });

  testWidgets('el icono ofrece las dos opciones y "Una tarjeta" abre la hoja de siempre', (tester) async {
    _datos([1]);
    await _abrir(tester);
    await tester.tap(find.byIcon(PhosphorIconsRegular.shareNetwork));
    await _pasar(tester);
    expect(find.text('Una tarjeta'), findsOneWidget);
    expect(find.text('Compartir progreso'), findsOneWidget);
    await tester.tap(find.text('Una tarjeta'));
    await _pasar(tester);
    expect(find.text(t.sharePick), findsOneWidget);
    expect(find.text(t.shareHint), findsOneWidget);
    expect(find.text('Compartir progreso'), findsNothing);
    await _cerrar(tester);
  });

  testWidgets('por defecto: ultimos 30 dias, Texto y conteo de dias', (tester) async {
    _datos([0, 29, 30]);
    await _abrir(tester);
    await _abrirVentana(tester);
    expect(find.text(t.shortDateYear(_dia(29))), findsOneWidget);
    expect(find.text(t.shortDateYear(_dia(0))), findsOneWidget);
    expect(find.text(t.exportDayCount(2)), findsOneWidget);
    expect(find.text('Copiar texto'), findsOneWidget);
    await _cerrar(tester);
  });

  testWidgets('Historico completo bloquea las fechas y se puede desactivar', (tester) async {
    _datos([0, 29, 60]);
    await _abrir(tester);
    await _abrirVentana(tester);
    await tester.tap(find.byType(TinySwitch));
    await _pasar(tester);
    expect(find.text(t.shortDateYear(_dia(60))), findsOneWidget);
    expect(find.text(t.exportDayCount(3)), findsOneWidget);
    expect(find.text(t.exportWholeHistoryHint(t.shortDateYear(_dia(60)), t.shortDateYear(_dia(0)))), findsOneWidget);
    await tester.tap(find.text(t.shortDateYear(_dia(60))), warnIfMissed: false);
    await _pasar(tester);
    expect(find.byType(DatePickerDialog), findsNothing);

    await tester.tap(find.byType(TinySwitch));
    await _pasar(tester);
    expect(find.text(t.shortDateYear(_dia(29))), findsOneWidget);
    expect(find.text(t.exportDayCount(2)), findsOneWidget);
    await tester.tap(find.text(t.shortDateYear(_dia(29))));
    await _pasar(tester);
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await _cerrar(tester);
  });

  testWidgets('periodo sin datos lo dice y no exporta', (tester) async {
    _datos([90]);
    fit.steps.clear();
    await _abrir(tester);
    await _abrirVentana(tester);
    expect(find.text(t.exportEmpty), findsOneWidget);
    await tester.tap(find.text('Exportar'), warnIfMissed: false);
    await tester.tap(find.text('Copiar texto'), warnIfMissed: false);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await _pasar(tester);
    expect(_shares, isEmpty);
    expect(_clipboard, isEmpty);
    expect(Directory(_progressDir).existsSync(), isFalse);
    await _cerrar(tester);
  });

  testWidgets('Texto se copia al portapapeles con aviso y se manda como texto', (tester) async {
    _datos([0]);
    await _abrir(tester);
    await _abrirVentana(tester);
    await _exportar(tester);
    expect(_clipboard, hasLength(1));
    expect(_clipboard.single, contains('Bench press'));
    expect(_shares.single.text, _clipboard.single);
    expect(find.text(t.exportCopiedClipboard), findsWidgets);
    expect(Directory(_progressDir).existsSync(), isFalse);
    await _cerrar(tester);
  });

  testWidgets('Copiar texto solo copia', (tester) async {
    _datos([0]);
    await _abrir(tester);
    await _abrirVentana(tester);
    await tester.tap(find.text('Copiar texto'));
    await _esperar(tester, () => _clipboard.isNotEmpty);
    expect(_clipboard.single, contains('Bench press'));
    expect(_shares, isEmpty);
    await _cerrar(tester);
  });

  testWidgets('cada formato comparte su archivo con el nombre correcto y el temporal se borra al cerrar',
      (tester) async {
    _datos([0, 29]);
    await _abrir(tester);
    await _abrirVentana(tester);
    final periodo = '${_iso(_dia(29))}_${_iso(_dia(0))}';

    for (final (etiqueta, ext, mime, inicio) in [
      ('CSV', 'csv', 'text/csv', [0xEF, 0xBB, 0xBF]),
      ('JSON', 'json', 'application/json', [0x7B]),
      ('Excel', 'xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', [0x50, 0x4B]),
      ('PDF', 'pdf', 'application/pdf', [0x25, 0x50, 0x44, 0x46]),
    ]) {
      await tester.tap(find.text(etiqueta));
      await _pasar(tester);
      await _exportar(tester);
      final s = _shares.last;
      expect(s.name, 'infyter-progreso-$periodo.$ext');
      expect(s.mime, mime);
      expect(s.files.values.first.take(inicio.length).toList(), inicio);
      expect(s.text, isNull);
      expect(File('$_progressDir/${s.name}').existsSync(), isTrue);
      expect(File('$_sharedDir/${s.name}').existsSync(), isTrue);
    }
    final json = jsonDecode(utf8.decode(_shares[1].files.values.first)) as Map;
    expect((json['period'] as Map)['from'], _iso(_dia(29)));

    await _cerrarVentana(tester);
    await _esperar(tester, () => !Directory(_progressDir).existsSync());
    for (final s in _shares) {
      await _esperar(tester, () => !File('$_sharedDir/${s.name}').existsSync());
    }
    expect(File('$_sharedDir/infyter-streak.png').existsSync(), isTrue);
    await _cerrar(tester);
  });

  testWidgets('si se cancela el compartir el temporal se borra en el acto', (tester) async {
    _datos([0]);
    _shareAnswer = '';
    await _abrir(tester);
    await _abrirVentana(tester);
    await tester.tap(find.text('CSV'));
    await _pasar(tester);
    await _exportar(tester);
    await _esperar(tester, () => !Directory(_progressDir).existsSync());
    await _esperar(tester, () => !File('$_sharedDir/${_shares.single.name}').existsSync());
    await _esperar(tester, () => find.text('Exportar').evaluate().isNotEmpty);
    await _cerrar(tester);
  });

  testWidgets('si falla el compartir avisa y no deja temporales', (tester) async {
    _datos([0]);
    _shareFails = true;
    await _abrir(tester);
    await _abrirVentana(tester);
    await tester.tap(find.text('CSV'));
    await _pasar(tester);
    await tester.tap(find.text('Exportar'));
    await _esperar(tester, () => find.text(t.exportFailed).evaluate().isNotEmpty);
    expect(_shares, isEmpty);
    await _esperar(tester, () => !Directory(_progressDir).existsSync());
    await _cerrar(tester);
  });

  testWidgets('cambiar de formato mientras exporta no cambia el archivo ni el MIME', (tester) async {
    _datos([0]);
    await _abrir(tester);
    await _abrirVentana(tester);
    await tester.tap(find.text('PDF'));
    await _pasar(tester);
    await tester.tap(find.text('Exportar'));
    await tester.pump();
    await tester.tap(find.text('CSV'), warnIfMissed: false);
    await tester.tap(find.byType(TinySwitch), warnIfMissed: false);
    await tester.pump();
    await _esperar(tester, () => _shares.isNotEmpty);
    expect(_shares.single.name, endsWith('.pdf'));
    expect(_shares.single.mime, 'application/pdf');
    await _cerrar(tester);
  });

  testWidgets('nada registrado nunca: lo dice y el interruptor no hace nada', (tester) async {
    _datos([]);
    fit.steps.clear();
    await _abrir(tester);
    await _abrirVentana(tester);
    expect(find.text(t.exportNothingAtAll), findsOneWidget);
    await tester.tap(find.byType(TinySwitch));
    await _pasar(tester);
    expect(find.textContaining('Todo lo registrado'), findsNothing);
    await tester.tap(find.text('Exportar'), warnIfMissed: false);
    await _pasar(tester);
    expect(_shares, isEmpty);
    await _cerrar(tester);
  });

  for (final dia in [DateTime(2026, 11, 1), DateTime(2026, 11, 15), DateTime(2026, 12, 31)]) {
    testWidgets('Desde y Hasta se corrigen entre si (hoy es ${_iso(dia)})', (tester) async {
      _hoy = dia;
      _datos([0]);
      await _abrir(tester);
      await _abrirVentana(tester);
      final inicioMes = DateTime(dia.year, dia.month, 1);
      final mesAnterior = DateTime(dia.year, dia.month - 1, 1);

      await tester.tap(find.text(t.shortDateYear(dia)));
      await _pasar(tester);
      await tester.tap(find.byIcon(Icons.chevron_left));
      await _pasar(tester);
      await tester.tap(find.text('1').last);
      await tester.tap(find.byType(TextButton).last);
      await _pasar(tester);
      expect(find.text(t.shortDateYear(mesAnterior)), findsNWidgets(2));

      await tester.tap(find.text(t.shortDateYear(mesAnterior)).first);
      await _pasar(tester);
      await tester.tap(find.byIcon(Icons.chevron_right));
      await _pasar(tester);
      await tester.tap(find.text('1').last);
      await tester.tap(find.byType(TextButton).last);
      await _pasar(tester);
      expect(find.text(t.shortDateYear(inicioMes)), findsNWidgets(2));
      await _cerrar(tester);
    });
  }

  testWidgets('un texto de mas de 60 000 caracteres sale como archivo .txt', (tester) async {
    _datos(List.generate(500, (i) => i));
    await _abrir(tester);
    await _abrirVentana(tester);
    await tester.tap(find.byType(TinySwitch));
    await _pasar(tester);
    await _exportar(tester);
    final s = _shares.single;
    expect(s.text, isNull);
    expect(s.name, endsWith('.txt'));
    expect(s.mime, 'text/plain');
    expect(_clipboard, isEmpty);
    await _cerrar(tester);
  });

  testWidgets('una segunda exportacion borra el archivo anterior', (tester) async {
    _datos([0]);
    await _abrir(tester);
    await _abrirVentana(tester);
    await tester.tap(find.text('CSV'));
    await _pasar(tester);
    await _exportar(tester);
    final primero = _shares.single.name;
    await tester.tap(find.text('JSON'));
    await _pasar(tester);
    await _exportar(tester);
    expect(File('$_progressDir/$primero').existsSync(), isFalse);
    expect(File('$_sharedDir/$primero').existsSync(), isFalse);
    expect(File('$_progressDir/${_shares.last.name}').existsSync(), isTrue);
    await _cerrar(tester);
  });

  testWidgets('al abrir la ventana se limpian los sobrantes de una exportacion anterior', (tester) async {
    File('$_progressDir/infyter-progreso-2026-01-01_2026-01-02.csv')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1]);
    File('$_sharedDir/infyter-progreso-2026-01-01_2026-01-02.csv').writeAsBytesSync([1]);
    _datos([0]);
    await _abrir(tester);
    await _abrirVentana(tester);
    await _esperar(tester, () => !Directory(_progressDir).existsSync());
    await _esperar(tester, () => !File('$_sharedDir/infyter-progreso-2026-01-01_2026-01-02.csv').existsSync());
    expect(File('$_sharedDir/infyter-streak.png').existsSync(), isTrue);
    await _cerrar(tester);
  });
}
