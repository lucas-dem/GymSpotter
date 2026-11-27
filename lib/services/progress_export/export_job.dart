import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/date_symbol_data_local.dart';

import '../../l10n/l10n.dart';
import '../../models/progress_report.dart';
import 'csv_export.dart';
import 'export_format.dart';
import 'json_export.dart';
import 'pdf_export.dart';
import 'text_export.dart';
import 'xlsx_export.dart';

enum ExportKind {
  text('txt', 'text/plain', 'Text'),
  pdf('pdf', 'application/pdf', 'PDF'),
  excel('xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'Excel'),
  csv('csv', 'text/csv', 'CSV'),
  json('json', 'application/json', 'JSON');

  const ExportKind(this.extension, this.mime, this.label);

  final String extension;
  final String mime;
  final String label;
}

class ExportJob {
  const ExportJob({required this.report, required this.kind, this.fonts});

  final ProgressReport report;
  final ExportKind kind;
  final PdfFonts? fonts;
}

class ExportResult {
  const ExportResult({required this.bytes, required this.fileName, required this.title, this.text});

  final Uint8List bytes;
  final String fileName;
  final String title;
  final String? text;
}

String _isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The same Latin name in every language: some apps break names with other scripts.
String exportFileName(ProgressReport report, ExportKind kind) =>
    'infyter-progreso-${_isoDay(report.from)}_${_isoDay(report.to)}.${kind.extension}';

Future<PdfFonts> loadPdfFonts(String language) => readPdfFonts(language, (path) async {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    });

/// Builds the chosen format from a plain-data job, so it can run in an isolate.
Future<ExportResult> runExportJob(ExportJob job) async {
  await initializeDateFormatting();
  final report = job.report;
  final l = lookupAppLocalizations(localeOf(report.language));
  final f = ExportFormat(report.locale);
  String? text;
  final Uint8List bytes;
  switch (job.kind) {
    case ExportKind.text:
      text = buildTextExport(report, l, f);
      bytes = utf8.encode(text);
    case ExportKind.csv:
      bytes = utf8.encode(buildCsvExport(report, l, f));
    case ExportKind.json:
      bytes = utf8.encode(buildJsonExport(report, f));
    case ExportKind.excel:
      bytes = buildXlsx(report, l, f);
    case ExportKind.pdf:
      bytes = await buildPdf(report, l, f, job.fonts!);
  }
  return ExportResult(
    bytes: bytes,
    fileName: exportFileName(report, job.kind),
    title: l.exportDocTitle,
    text: text,
  );
}
