import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../l10n/app_localizations.dart';
import '../../models/progress_report.dart';
import 'export_format.dart';
import 'report_outline.dart';

const kPdfFontAssets = (
  regular: 'assets/fonts/Nunito-Regular.ttf',
  bold: 'assets/fonts/Nunito-Bold.ttf',
  italic: 'assets/fonts/Nunito-Italic.ttf',
);

/// The raw bytes of the PDF fonts, so the export can run in an isolate without rootBundle.
class PdfFonts {
  const PdfFonts({required this.regular, required this.bold, required this.italic});

  final Uint8List regular;
  final Uint8List bold;
  final Uint8List italic;

  List<Uint8List> get all => [regular, bold, italic];
}

/// The blocks the PDF draws: the same list the text export writes.
List<OutlineBlock> pdfOutlineFor(ProgressReport report, AppLocalizations l, ExportFormat f) =>
    buildReportOutline(report, l, f);

/// The characters of [texts] that none of the fonts can draw.
Set<int> pdfUncoveredRunes(Iterable<String> texts, PdfFonts fonts) {
  final maps = [for (final bytes in fonts.all) TtfParser(ByteData.sublistView(bytes)).charToGlyphIndexMap];
  return {
    for (final text in texts)
      for (final r in text.runes)
        if (r > 0x20 && !(r >= 0x7F && r <= 0x9F) && !maps.any((m) => m.containsKey(r))) r,
  };
}

const _setsPerChunk = 20;
const _margin = 36.0;

Future<Uint8List> buildPdf(ProgressReport report, AppLocalizations l, ExportFormat f, PdfFonts fonts) async {
  final regular = pw.Font.ttf(ByteData.sublistView(fonts.regular));
  final bold = pw.Font.ttf(ByteData.sublistView(fonts.bold));
  final italic = pw.Font.ttf(ByteData.sublistView(fonts.italic));
  const grey = PdfColor.fromInt(0xFF6B6F76);
  final base = pw.TextStyle(fontSize: 10.5, lineSpacing: 2);

  final doc = pw.Document(
    title: f.clean(l.exportDocTitle),
    producer: 'Infyter',
    theme: pw.ThemeData.withFont(base: regular, bold: bold, italic: italic, boldItalic: bold),
  );

  final widgets = <pw.Widget>[];
  var group = <pw.Widget>[];
  var setsInGroup = 0;
  var headingOpen = false;

  void flush() {
    if (group.isNotEmpty) widgets.add(pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: group));
    group = [];
    setsInGroup = 0;
    headingOpen = false;
  }

  void add(pw.Widget w) {
    group.add(w);
    if (headingOpen) flush();
  }

  for (final b in pdfOutlineFor(report, l, f)) {
    switch (b.kind) {
      case OutlineKind.title:
        add(pw.Text(b.text, style: base.copyWith(fontSize: 20, fontWeight: pw.FontWeight.bold)));
      case OutlineKind.period || OutlineKind.units:
        add(pw.Text(b.text, style: base.copyWith(color: grey)));
      case OutlineKind.dayHeading:
        flush();
        group.add(
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 14),
            padding: const pw.EdgeInsets.only(top: 6, bottom: 4),
            decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: grey, width: 0.6))),
            child: pw.Text(b.text, style: base.copyWith(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          ),
        );
        headingOpen = true;
      case OutlineKind.session:
        if (!headingOpen) flush();
        add(pw.Padding(padding: const pw.EdgeInsets.only(top: 2), child: pw.Text(b.text, style: base.copyWith(fontWeight: pw.FontWeight.bold))));
      case OutlineKind.exercise:
        if (!headingOpen) flush();
        group.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(text: b.text, style: base.copyWith(fontWeight: pw.FontWeight.bold)),
                  pw.TextSpan(text: '  ${b.detail}', style: base.copyWith(color: grey, fontSize: 9)),
                ],
              ),
            ),
          ),
        );
        headingOpen = false;
      case OutlineKind.set:
        if (setsInGroup >= _setsPerChunk) flush();
        setsInGroup++;
        group.add(pw.Padding(padding: const pw.EdgeInsets.only(left: 14), child: pw.Text(b.text, style: base)));
      case OutlineKind.fact:
        if (!headingOpen) flush();
        add(
          pw.RichText(
            text: pw.TextSpan(
              children: [
                pw.TextSpan(text: '${b.text}: ', style: base.copyWith(fontWeight: pw.FontWeight.bold)),
                pw.TextSpan(text: b.detail, style: base),
              ],
            ),
          ),
        );
      case OutlineKind.note:
        if (!headingOpen) flush();
        add(pw.Padding(padding: const pw.EdgeInsets.only(top: 8), child: pw.Text(b.text, style: base.copyWith(fontStyle: pw.FontStyle.italic, fontSize: 9, color: grey))));
      case OutlineKind.footer:
        if (!headingOpen) flush();
        add(pw.Padding(padding: const pw.EdgeInsets.only(top: 10), child: pw.Text(b.text, style: base.copyWith(color: grey))));
    }
  }
  flush();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(_margin),
      textDirection: report.language == 'ar' ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      build: (_) => widgets,
      footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          f.clean(l.exportPage(c.pageNumber, c.pagesCount)),
          style: base.copyWith(fontSize: 8.5, color: grey),
        ),
      ),
    ),
  );
  return doc.save();
}
