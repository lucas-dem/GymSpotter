import '../../l10n/app_localizations.dart';
import '../../models/progress_report.dart';
import 'export_format.dart';
import 'report_outline.dart';

/// Writes the report as plain text with WhatsApp bold and italic marks.
String buildTextExport(ProgressReport report, AppLocalizations l, ExportFormat f) {
  final lines = <String>[];
  OutlineKind? previous;
  for (final b in buildReportOutline(report, l, f)) {
    if (b.kind == OutlineKind.dayHeading || (b.kind == OutlineKind.note && previous != OutlineKind.note)) {
      lines.add('');
    }
    lines.add(switch (b.kind) {
      OutlineKind.title || OutlineKind.dayHeading => '*${b.text}*',
      OutlineKind.exercise => '${b.text} · ${b.detail}',
      OutlineKind.set => '  ${b.text}',
      OutlineKind.fact => '${b.text}: ${b.detail}',
      OutlineKind.note => '_${b.text}_',
      _ => b.text,
    });
    previous = b.kind;
  }
  return lines.join('\n');
}
