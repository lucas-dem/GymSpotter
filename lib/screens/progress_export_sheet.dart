import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../models/progress_report.dart';
import '../services/progress_export/export_job.dart';
import '../services/progress_export/export_share.dart';
import '../services/progress_report_source.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';
import '../widgets/liquid_notch.dart';
import '../widgets/ui_kit.dart';
import 'share_sheet.dart';

Future<void> showShareChooser(BuildContext context) => showAppSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheet) {
        final gc = sheet.gc;
        return Container(
          decoration: BoxDecoration(
            color: gc.bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SheetHandle(margin: EdgeInsets.symmetric(vertical: 14)),
                  SheetTitle(t.shareChooserTitle),
                  const SizedBox(height: 16),
                  OptionGroup([
                    OptionItem(
                      t.shareChooserCard,
                      icon: PhosphorIconsRegular.image,
                      detail: t.shareChooserCardHint,
                      onTap: () {
                        Navigator.of(sheet).pop();
                        showShareSheet(context);
                      },
                    ),
                    OptionItem(
                      t.shareChooserProgress,
                      icon: PhosphorIconsRegular.fileText,
                      detail: t.shareChooserProgressHint,
                      onTap: () {
                        Navigator.of(sheet).pop();
                        showProgressExportSheet(context);
                      },
                    ),
                  ]),
                ],
              ),
            ),
          ),
        );
      },
    );

Future<void> showProgressExportSheet(BuildContext context, {DateTime? today}) => showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProgressExportSheet(today: today),
    );

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

class _ProgressExportSheet extends StatefulWidget {
  const _ProgressExportSheet({this.today});

  final DateTime? today;

  @override
  State<_ProgressExportSheet> createState() => _ProgressExportSheetState();
}

class _ProgressExportSheetState extends State<_ProgressExportSheet> {
  final GlobalKey _exportButton = GlobalKey();
  late final DateTime _today = _dayOf(widget.today ?? DateTime.now());
  late DateTime _from = DateTime(_today.year, _today.month, _today.day - 29);
  late DateTime _to = _today;
  late final ({DateTime from, DateTime to})? _span = recordedSpanFromFit();
  late ProgressReport _report = _buildReport();
  bool _whole = false;
  ExportKind _kind = ExportKind.text;
  bool _busy = false;
  String? _fileName;
  String? _notice;

  bool get _wholeActive => _whole && _span != null;

  ProgressReport _buildReport() => _wholeActive
      ? progressReportFromFit(from: _span!.from, to: _span.to, wholeHistory: true)
      : progressReportFromFit(from: _from, to: _to, wholeHistory: false);

  void _update(VoidCallback change) => setState(() {
        change();
        _report = _buildReport();
      });

  @override
  void initState() {
    super.initState();
    sweepExportLeftovers();
  }

  @override
  void dispose() {
    deleteExportFiles(_fileName);
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime initial) {
    final span = _span;
    final first = span != null && span.from.isBefore(DateTime(2015)) ? span.from : DateTime(2015);
    return showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : (initial.isAfter(_today) ? _today : initial),
      firstDate: first,
      lastDate: _today,
    );
  }

  Future<void> _pickFrom() async {
    final picked = await _pick(_from);
    if (picked == null || !mounted) return;
    _update(() {
      _from = picked;
      if (_to.isBefore(_from)) _to = _from;
    });
  }

  Future<void> _pickTo() async {
    final picked = await _pick(_to);
    if (picked == null || !mounted) return;
    _update(() {
      _to = picked;
      if (_to.isBefore(_from)) _from = _to;
    });
  }

  Rect? _origin() {
    final box = _exportButton.currentContext?.findRenderObject() as RenderBox?;
    return box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size;
  }

  void _failed() {
    if (!mounted) return;
    showNotchToast(context, t.exportFailed, icon: PhosphorIconsFill.warningCircle, accent: context.gc.warn);
  }

  Future<ExportResult> _build(ExportKind kind, ProgressReport report) async {
    final fonts = kind == ExportKind.pdf ? await loadPdfFonts() : null;
    return compute(runExportJob, ExportJob(report: report, kind: kind, fonts: fonts));
  }

  Future<void> _copy() async {
    if (_busy || _report.isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await _build(ExportKind.text, _report);
      final text = result.text!;
      if (!mounted) return;
      if (text.length > kExportTextLimit) {
        showNotchToast(context, t.exportTextTooLong);
        return;
      }
      await copyExportText(text);
      if (mounted) showNotchToast(context, t.copiedDone);
    } catch (_) {
      _failed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    if (_busy) return;
    if (_report.isEmpty) {
      showNotchToast(context, t.exportEmpty);
      return;
    }
    final kind = _kind;
    setState(() {
      _busy = true;
      _notice = null;
    });
    String? written;
    try {
      final result = await _build(kind, _report);
      if (!mounted) return;
      final text = result.text;
      if (text != null && text.length <= kExportTextLimit) {
        await copyExportText(text);
        if (!mounted) return;
        setState(() => _notice = t.exportCopiedClipboard);
        showNotchToast(context, t.exportCopiedClipboard);
        await shareExportText(text, result.title, _origin());
        return;
      }
      await deleteExportFiles(_fileName);
      written = result.fileName;
      _fileName = written;
      final dir = await freshExportDir();
      final file = await writeExportFile(dir, written, result.bytes);
      if (!mounted) {
        await deleteExportFiles(written);
        return;
      }
      final shared = await shareExportFile(file, kind, result.title, _origin());
      if (shared.status == ShareResultStatus.dismissed) await deleteExportFiles(written);
    } catch (_) {
      await deleteExportFiles(written);
      _failed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ToolRow _dateRow(String label, DateTime value, VoidCallback onTap) {
    final gc = context.gc;
    final locked = _wholeActive || _busy;
    return ToolRow(
      label: label,
      control: Semantics(
        enabled: !locked,
        child: IgnorePointer(
          ignoring: locked,
          child: Pill(
            label: t.shortDateYear(value),
            bg: gc.bgRaised2,
            fg: locked ? gc.textTertiary : gc.text,
            onTap: onTap,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    final span = _span;
    final shownFrom = _wholeActive ? span!.from : _from;
    final shownTo = _wholeActive ? span!.to : _to;
    final nothingAtAll = span == null;
    final empty = _report.isEmpty;
    final status = nothingAtAll
        ? t.exportNothingAtAll
        : empty
            ? t.exportEmpty
            : t.exportDayCount(_report.days.length);

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      decoration: BoxDecoration(
        color: gc.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(margin: EdgeInsets.symmetric(vertical: 14)),
              SheetTitle(t.shareChooserProgress, subtitle: t.exportSheetHint),
              const SizedBox(height: 16),
              ToolGroup([
                _dateRow(t.exportFrom, shownFrom, _pickFrom),
                _dateRow(t.exportTo, shownTo, _pickTo),
                ToolRow(
                  label: t.exportWholeHistory,
                  control: Semantics(
                    toggled: _wholeActive,
                    enabled: !nothingAtAll && !_busy,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: nothingAtAll || _busy ? null : () => _update(() => _whole = !_whole),
                      child: TinySwitch(on: _wholeActive),
                    ),
                  ),
                ),
              ]),
              if (_wholeActive)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4),
                  child: Text(
                    t.exportWholeHistoryHint(t.shortDateYear(span!.from), t.shortDateYear(span.to)),
                    style: AppTheme.f(12, weight: FontWeight.w500, color: gc.textSecondary, height: 1.35),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 10, left: 4),
                child: Text(
                  status,
                  style: AppTheme.f(13, weight: FontWeight.w600, color: empty ? gc.warn : gc.textSecondary),
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  t.exportFormat,
                  style: AppTheme.f(13, weight: FontWeight.w700, color: gc.textSecondary),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in ExportKind.values)
                    Pill(
                      label: k == ExportKind.text ? t.exportFormatText : k.label,
                      bg: k == _kind ? gc.emberSoft : gc.bgRaised,
                      fg: k == _kind ? gc.text : gc.textSecondary,
                      fontSize: 12.5,
                      onTap: () {
                        if (!_busy) setState(() => _kind = k);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, left: 4),
                  child: Text(
                    _notice!,
                    style: AppTheme.f(12.5, weight: FontWeight.w600, color: gc.textSecondary),
                  ),
                ),
              Semantics(
                enabled: !empty,
                child: Opacity(
                  opacity: empty ? 0.4 : 1,
                  child: IgnorePointer(
                    ignoring: empty,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        KeyedSubtree(
                          key: _exportButton,
                          child: PrimaryButton(
                            label: _busy ? t.exportBusy : t.exportAction,
                            height: 54,
                            onTap: _export,
                          ),
                        ),
                        if (_kind == ExportKind.text) ...[
                          const SizedBox(height: 10),
                          GhostButton(label: t.exportCopy, icon: PhosphorIconsRegular.copy, onTap: _copy),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
