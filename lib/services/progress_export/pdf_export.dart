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
const kPdfArabicAssets = (
  regular: 'assets/fonts/InfyterPdfArabic-Regular.ttf',
  bold: 'assets/fonts/InfyterPdfArabic-Bold.ttf',
);
const kPdfCjkAsset = 'assets/fonts/DroidSansFallbackFull.ttf';
const kPdfHangulAsset = 'assets/fonts/NanumGothic-Regular.ttf';

typedef PdfFontAssets = ({String regular, String bold, String italic, List<String> fallback});

/// The font files the PDF of [language] draws with. The library joins Arabic letters and orders a
/// line right to left only inside a run of one font, so Arabic uses Nunito and Noto Sans Arabic
/// merged into one file; the CJK and Hangul fonts only fill in what Nunito lacks.
PdfFontAssets pdfFontAssetsFor(String language) => switch (language) {
      'ar' => (
          regular: kPdfArabicAssets.regular,
          bold: kPdfArabicAssets.bold,
          italic: kPdfArabicAssets.regular,
          fallback: const [],
        ),
      'ja' || 'zh' || 'zh_Hant' => (
          regular: kPdfFontAssets.regular,
          bold: kPdfFontAssets.bold,
          italic: kPdfFontAssets.italic,
          fallback: [kPdfCjkAsset],
        ),
      'ko' => (
          regular: kPdfFontAssets.regular,
          bold: kPdfFontAssets.bold,
          italic: kPdfFontAssets.italic,
          fallback: [kPdfHangulAsset],
        ),
      _ => (
          regular: kPdfFontAssets.regular,
          bold: kPdfFontAssets.bold,
          italic: kPdfFontAssets.italic,
          fallback: const [],
        ),
    };

/// The raw bytes of the PDF fonts, so the export can run in an isolate without rootBundle.
class PdfFonts {
  const PdfFonts({required this.regular, required this.bold, required this.italic, this.fallback = const []});

  final Uint8List regular;
  final Uint8List bold;
  final Uint8List italic;
  final List<Uint8List> fallback;

  List<Uint8List> get all => [regular, bold, italic, ...fallback];
}

/// Reads the fonts of [language] through [read], which gets an asset path.
Future<PdfFonts> readPdfFonts(String language, Future<Uint8List> Function(String path) read) async {
  final a = pdfFontAssetsFor(language);
  return PdfFonts(
    regular: await read(a.regular),
    bold: await read(a.bold),
    italic: await read(a.italic),
    fallback: [for (final path in a.fallback) await read(path)],
  );
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

const _margin = 36.0;
const _footerHeight = 16.0;

/// The room a day has on an empty page, below the margins and above the footer.
final double _pageRoom = PdfPageFormat.a4.height - 2 * _margin - _footerHeight - 1;

/// Keeps a day on one page, moving it to the next one when it does not fit in what is left.
/// Only a day taller than a whole page is split, between its lines.
class _KeepTogether extends pw.SingleChildWidget {
  _KeepTogether(pw.Widget child) : super(child: child);

  bool _tooTall = false;

  @override
  bool get canSpan => _tooTall && super.canSpan;

  @override
  bool get hasMoreWidgets => _tooTall && super.hasMoreWidgets;

  @override
  void layout(pw.Context context, pw.BoxConstraints constraints, {bool parentUsesSize = false}) {
    super.layout(context, constraints, parentUsesSize: parentUsesSize);
    if (!constraints.hasBoundedHeight && box!.height > _pageRoom) _tooTall = true;
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    paintChild(context);
  }
}

Future<Uint8List> buildPdf(ProgressReport report, AppLocalizations l, ExportFormat f, PdfFonts fonts) async {
  final regular = pw.Font.ttf(ByteData.sublistView(fonts.regular));
  final bold = pw.Font.ttf(ByteData.sublistView(fonts.bold));
  final italic = pw.Font.ttf(ByteData.sublistView(fonts.italic));
  final fallback = [for (final bytes in fonts.fallback) pw.Font.ttf(ByteData.sublistView(bytes))];
  const grey = PdfColor.fromInt(0xFF6B6F76);
  final base = pw.TextStyle(fontSize: 10.5, lineSpacing: 2);

  final doc = pw.Document(
    title: f.clean(l.exportDocTitle),
    producer: 'Infyter',
    theme: pw.ThemeData.withFont(base: regular, bold: bold, italic: italic, boldItalic: bold, fontFallback: fallback),
  );

  final widgets = <pw.Widget>[];
  List<pw.Widget>? day;
  pw.Widget? heldLine;

  void add(pw.Widget w) {
    final held = heldLine;
    heldLine = null;
    (day ?? widgets).add(
      held == null ? w : pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [held, w]),
    );
  }

  // A day heading or an exercise name stays on the same page as the line after it.
  void hold(pw.Widget w) {
    final held = heldLine;
    if (held != null) {
      heldLine = null;
      add(held);
    }
    heldLine = w;
  }

  void closeDay() {
    final held = heldLine;
    if (held != null) {
      heldLine = null;
      add(held);
    }
    final lines = day;
    day = null;
    if (lines != null) {
      widgets.add(_KeepTogether(pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: lines)));
    }
  }

  for (final b in pdfOutlineFor(report, l, f)) {
    switch (b.kind) {
      case OutlineKind.title:
        add(pw.Text(b.text, style: base.copyWith(fontSize: 20, fontWeight: pw.FontWeight.bold)));
      case OutlineKind.period || OutlineKind.units:
        add(pw.Text(b.text, style: base.copyWith(color: grey)));
      case OutlineKind.dayHeading:
        closeDay();
        day = [];
        hold(
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 14),
            padding: const pw.EdgeInsets.only(top: 6, bottom: 4),
            decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: grey, width: 0.6))),
            child: pw.Text(b.text, style: base.copyWith(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          ),
        );
      case OutlineKind.session:
        add(pw.Padding(padding: const pw.EdgeInsets.only(top: 2), child: pw.Text(b.text, style: base.copyWith(fontWeight: pw.FontWeight.bold))));
      case OutlineKind.exercise:
        hold(
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
      case OutlineKind.set:
        add(pw.Padding(padding: const pw.EdgeInsets.only(left: 14), child: pw.Text(b.text, style: base)));
      case OutlineKind.fact:
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
        closeDay();
        add(pw.Padding(padding: const pw.EdgeInsets.only(top: 8), child: pw.Text(b.text, style: base.copyWith(fontStyle: pw.FontStyle.italic, fontSize: 9, color: grey))));
      case OutlineKind.footer:
        closeDay();
        add(pw.Padding(padding: const pw.EdgeInsets.only(top: 10), child: pw.Text(b.text, style: base.copyWith(color: grey))));
    }
  }
  closeDay();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(_margin),
      textDirection: report.language == 'ar' ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      build: (_) => widgets,
      footer: (c) => pw.SizedBox(
        height: _footerHeight,
        child: pw.Align(
          alignment: pw.Alignment.bottomRight,
          child: pw.Text(
            f.clean(l.exportPage(c.pageNumber, c.pagesCount)),
            style: base.copyWith(fontSize: 8.5, color: grey),
          ),
        ),
      ),
    ),
  );
  return doc.save();
}
