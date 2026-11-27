import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/models/progress_report.dart';
import 'package:infyter/models/workout.dart';
import 'package:infyter/services/progress_export/export_format.dart';
import 'package:infyter/services/progress_export/pdf_export.dart';
import 'package:infyter/services/progress_export/report_outline.dart';
import 'package:infyter/services/progress_report_builder.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'compartir_progreso_fixture.dart';

PdfFonts _fonts() => PdfFonts(
      regular: File(kPdfFontAssets.regular).readAsBytesSync(),
      bold: File(kPdfFontAssets.bold).readAsBytesSync(),
      italic: File(kPdfFontAssets.italic).readAsBytesSync(),
    );

Future<Uint8List> _pdf(ProgressReport r, PdfFonts fonts) =>
    buildPdf(r, lookupAppLocalizations(localeOf(r.language)), ExportFormat(r.locale), fonts);

String _latin(Uint8List b) => latin1.decode(b);

Uint8List _streamOf(Uint8List b, String text, int obj) {
  final m = RegExp('(?:^|\\n)$obj 0 obj\\n<<[^\\n]*?>>stream\\r?\\n').firstMatch(text)!;
  final end = text.indexOf('endstream', m.end);
  final raw = b.sublist(m.end, end);
  return text.substring(m.start, m.end).contains('FlateDecode') ? Uint8List.fromList(zlib.decode(raw)) : raw;
}

Map<int, String> _toUnicode(String cmap) {
  final out = <int, String>{};
  String uni(String hex) => String.fromCharCodes([
        for (var i = 0; i < hex.length; i += 4) int.parse(hex.substring(i, i + 4), radix: 16),
      ]);
  for (final block in RegExp(r'beginbfchar([\s\S]*?)endbfchar').allMatches(cmap)) {
    for (final m in RegExp(r'<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>').allMatches(block.group(1)!)) {
      out[int.parse(m.group(1)!, radix: 16)] = uni(m.group(2)!);
    }
  }
  for (final block in RegExp(r'beginbfrange([\s\S]*?)endbfrange').allMatches(cmap)) {
    for (final m in RegExp(r'<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>').allMatches(block.group(1)!)) {
      final lo = int.parse(m.group(1)!, radix: 16);
      final hi = int.parse(m.group(2)!, radix: 16);
      final start = uni(m.group(3)!).runes.first;
      for (var c = lo; c <= hi; c++) {
        out[c] = String.fromCharCode(start + c - lo);
      }
    }
  }
  return out;
}

class _Extracted {
  _Extracted(this.pages, this.words);
  final int pages;
  final List<String> words;
}

/// Reads the words back from the PDF through each font's ToUnicode map, with no extra package.
_Extracted _extract(Uint8List b) {
  final text = _latin(b);
  final maps = <String, Map<int, String>>{};
  for (final obj in text.split('endobj')) {
    final name = RegExp(r'/Name/(F\d+)').firstMatch(obj)?.group(1);
    final ref = RegExp(r'/ToUnicode (\d+) 0 R').firstMatch(obj)?.group(1);
    if (name != null && ref != null) {
      maps[name] = _toUnicode(latin1.decode(_streamOf(b, text, int.parse(ref))));
    }
  }
  final pages = int.parse(RegExp(r'/Type/Pages/Kids\[[^\]]*\]/Count (\d+)').firstMatch(text)!.group(1)!);
  final words = <String>[];
  for (final page in RegExp(r'/Type/Page/[^\n]*?/Contents (\d+) 0 R').allMatches(text)) {
    final content = latin1.decode(_streamOf(b, text, int.parse(page.group(1)!)));
    for (final run in RegExp(r'/(F\d+) [\d.]+ Tf[^\[]*\[([^\]]*)\]\s*TJ').allMatches(content)) {
      final map = maps[run.group(1)!]!;
      final sb = StringBuffer();
      for (final h in RegExp(r'<([0-9a-fA-F]+)>').allMatches(run.group(2)!)) {
        final hex = h.group(1)!;
        for (var i = 0; i < hex.length; i += 4) {
          sb.write(map[int.parse(hex.substring(i, i + 4), radix: 16)] ?? '�');
        }
      }
      words.add(sb.toString());
    }
  }
  return _Extracted(pages, words);
}

List<String> _outlineWords(ProgressReport r, String lang) {
  final l = lookupAppLocalizations(localeOf(lang));
  return [
    for (final b in pdfOutlineFor(r, l, ExportFormat(r.locale)))
      for (final w in (b.kind == OutlineKind.fact ? '${b.text}: ${b.detail}' : '${b.text} ${b.detail ?? ''}').split(RegExp(r'\s+')))
        if (w.isNotEmpty) w,
  ];
}

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

ProgressReport _custom({required String language, String Function(String, String)? exerciseName, int days = 3}) {
  final from = fixtureFrom;
  return buildProgressReport(
    from: from,
    to: DateTime(from.year, from.month, from.day + days - 1),
    wholeHistory: false,
    now: fixtureNow,
    language: language,
    locale: language == 'zh_Hant' ? 'zh_TW' : language,
    units: const ReportUnits(weight: 'kg', length: 'cm', distance: 'km', effort: 'rpe'),
    sessions: [
      for (var i = 0; i < days; i++)
        LoggedSession(DateTime(from.year, from.month, from.day + i, 18), 3000, fixtureSessions().first.exercises),
    ],
    steps: {for (var i = 0; i < days; i++) _key(DateTime(from.year, from.month, from.day + i)): 5000 + i},
    stepsFrom: const {},
    showStepsFrom: false,
    bodyweight: fixtureBodyweight(),
    measures: fixtureMeasures(),
    profileWeightKg: fixtureProfileWeightKg,
    toWeight: (kg) => kg,
    toMeasure: (key, raw) => raw,
    toDistance: (km) => km,
    restFor: fixtureRestFor,
    exerciseName: exerciseName ?? fixtureExerciseName,
  );
}

const _languages = ['ar', 'de', 'en', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pl', 'pt', 'ru', 'tr', 'uk', 'zh', 'zh_Hant'];
const _fullCoverage = ['de', 'en', 'es', 'fr', 'it', 'nl', 'pl', 'pt', 'ru', 'tr', 'uk'];

void main() {
  late PdfFonts fonts;

  setUpAll(() async {
    await initializeDateFormatting();
    fonts = _fonts();
  });

  test('the PDF is well formed and has no scripts, links or attachments', () async {
    final b = await _pdf(fixtureReport(), fonts);
    final s = _latin(b);
    expect(s, startsWith('%PDF-'));
    expect(s.trimRight(), endsWith('%%EOF'));
    expect(s, contains('/Type/Catalog'));
    expect(RegExp(r'startxref\s+(\d+)').firstMatch(s), isNotNull);
    for (final bad in ['/JavaScript', '/JS', '/URI', '/Launch', '/EmbeddedFile', '/OpenAction', '/AA']) {
      expect(s.contains(bad), isFalse, reason: bad);
    }
    expect(_extract(b).pages, 1);
    expect(s, contains('/MediaBox[0 0 595.27559 841.88976]'));
    expect(b.length, lessThan(60 * 1024));
  });

  for (final lang in ['es', 'en']) {
    test('$lang text comes back from the PDF through ToUnicode, with its glyphs', () async {
      final r = fixtureReport(language: lang);
      final x = _extract(await _pdf(r, fonts));
      final wanted = _outlineWords(r, lang);
      final got = [...x.words];
      for (final w in wanted) {
        expect(got.remove(w), isTrue, reason: 'missing "$w" in $lang: ${x.words}');
      }
      expect(pdfUncoveredRunes(wanted, fonts), isEmpty);
      final joined = x.words.join(' ');
      for (final ch in ['×', '≈', '·']) {
        expect(joined, contains(ch));
      }
      if (lang == 'es') {
        expect(joined, contains('Calorías'));
        expect(joined, contains('Página'));
        expect(joined, contains('Domingo,'));
      }
      expect(x.words, contains('Infyter'));
      expect(joined, isNot(contains('�')));
    });
  }

  test('n with tilde, u with diaeresis, accents and symbols in an exercise name survive', () async {
    const name = 'Remo ñandú ÑÜ áéíóú ÁÉÍÓÚ × ≈ · – …';
    final r = _custom(language: 'es', exerciseName: (_, _) => name);
    final x = _extract(await _pdf(r, fonts));
    for (final w in name.split(' ')) {
      expect(x.words, contains(w), reason: w);
    }
    expect(pdfUncoveredRunes([name], fonts), isEmpty);
  });

  test('the PDF draws the same outline as the text export, with no profile name', () {
    final r = fixtureReport();
    final l = lookupAppLocalizations(localeOf('es'));
    final f = ExportFormat('es');
    final outline = pdfOutlineFor(r, l, f);
    expect(outline, buildReportOutline(r, l, f));
    expect(outline.first, const OutlineBlock(OutlineKind.title, 'Infyter · Progreso'));
    expect(outline.where((b) => b.kind == OutlineKind.dayHeading), hasLength(2));
  });

  test('a long report breaks across pages and numbers them', () async {
    final r = _custom(language: 'es', days: 40);
    final x = _extract(await _pdf(r, fonts));
    expect(x.pages, greaterThan(2));
    expect(x.words, contains('Página'));
    expect(x.words, contains('${x.pages}'));
  });

  test('an exercise with 90 sets does not overflow a page', () async {
    final sets = [for (var i = 0; i < 90; i++) LoggedSet(10, 20.0 + i)];
    final r = buildProgressReport(
      from: fixtureFrom,
      to: fixtureFrom,
      wholeHistory: false,
      now: fixtureNow,
      language: 'en',
      locale: 'en',
      units: const ReportUnits(weight: 'kg', length: 'cm', distance: 'km', effort: 'rpe'),
      sessions: [
        LoggedSession(DateTime(2026, 11, 20, 18), 3600, [LoggedExercise('bench_press', 'Bench', 'chest', sets)]),
      ],
      steps: const {},
      stepsFrom: const {},
      showStepsFrom: false,
      bodyweight: const [],
      measures: const [],
      profileWeightKg: 75,
      toWeight: (kg) => kg,
      toMeasure: (k, v) => v,
      toDistance: (km) => km,
      restFor: (_) => 90,
      exerciseName: (_, fb) => fb,
    );
    final x = _extract(await _pdf(r, fonts));
    expect(x.pages, greaterThanOrEqualTo(2));
    expect(x.words.where((w) => w == '×'), hasLength(90));
  });

  test('a character with no glyph (emoji, CJK, Arabic) does not break the export', () async {
    final r = _custom(language: 'es', exerciseName: (_, _) => 'Press 🏋 日本語 한국어 العربية');
    final b = await _pdf(r, fonts);
    expect(_latin(b), startsWith('%PDF-'));
    expect(pdfUncoveredRunes(['🏋日本語'], fonts), isNotEmpty);
  });

  test('all 16 languages build a PDF; coverage of the bundled Nunito is reported', () async {
    final missing = <String, String>{};
    for (final lang in _languages) {
      final r = fixtureReport(language: lang);
      final l = lookupAppLocalizations(localeOf(lang));
      final f = ExportFormat(r.locale);
      final texts = [
        for (final b in pdfOutlineFor(r, l, f)) ...[b.text, ?b.detail],
        f.clean(l.exportPage(1, 1)),
      ];
      final b = await _pdf(r, fonts);
      expect(_latin(b), startsWith('%PDF-'), reason: lang);
      final runes = pdfUncoveredRunes(texts, fonts);
      if (runes.isNotEmpty) missing[lang] = String.fromCharCodes(runes);
    }
    // ignore: avoid_print
    print('Languages with glyphs missing from Nunito: ${missing.map((k, v) => MapEntry(k, v.length))}');
    for (final lang in _fullCoverage) {
      expect(missing.containsKey(lang), isFalse, reason: '$lang: ${missing[lang]}');
    }
  });
}
