import 'dart:io';

import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/l10n/l10n.dart';
import 'package:infyter/services/progress_export/export_job.dart';
import 'package:infyter/services/progress_export/pdf_export.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'compartir_progreso_fixture.dart';

const _languages = ['ar', 'de', 'en', 'es', 'fr', 'it', 'ja', 'ko', 'nl', 'pl', 'pt', 'ru', 'tr', 'uk', 'zh', 'zh_Hant'];

void main() {
  setUpAll(initializeDateFormatting);

  test('the file name is the same Latin name in all 16 languages: infyter-progreso and the period', () async {
    for (final lang in _languages) {
      final report = fixtureReport(language: lang);
      final fonts = await readPdfFonts(lang, (path) async => File(path).readAsBytesSync());
      for (final kind in ExportKind.values) {
        final result = await runExportJob(ExportJob(report: report, kind: kind, fonts: fonts));
        expect(result.fileName, 'infyter-progreso-2026-11-20_2026-11-22.${kind.extension}', reason: '$lang $kind');
        expect(result.fileName, matches(RegExp(r'^[a-z0-9._-]+$')), reason: '$lang $kind');
      }
    }
  });

  test('the Excel sheet names stay translated', () async {
    final names = <String, List<String>>{};
    for (final lang in ['es', 'ja', 'ar', 'ru']) {
      final result = await runExportJob(ExportJob(report: fixtureReport(language: lang), kind: ExportKind.excel));
      names[lang] = Excel.decodeBytes(result.bytes).tables.keys.toList();
      final l = lookupAppLocalizations(localeOf(lang));
      expect(names[lang], [l.exportSheetSummary, l.exportSheetDetail], reason: lang);
    }
    expect(names['ja'], isNot(names['es']));
    expect(names['ar'], isNot(names['es']));
  });
}
