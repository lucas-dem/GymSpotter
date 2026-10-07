import 'dart:convert';
import 'dart:io' show zlib;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

import '../l10n/l10n.dart';
import '../models/workout.dart';
import '../screens/plan_import_sheet.dart';
import '../state/fit_state.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/liquid_notch.dart';
import '../widgets/glass.dart';
import '../widgets/ui_kit.dart';

const _qrPrefix = 'infyter:plan:1:';

String encodePlanQrJson(String json) {
  final compressed = zlib.encode(utf8.encode(json));
  return '$_qrPrefix${base64UrlEncode(compressed).replaceAll('=', '')}';
}

String? decodePlanQr(String raw) {
  if (!raw.startsWith(_qrPrefix)) return null;
  try {
    var encoded = raw.substring(_qrPrefix.length);
    encoded += '=' * ((4 - encoded.length % 4) % 4);
    return utf8.decode(zlib.decode(base64Url.decode(encoded)));
  } catch (_) {
    return null;
  }
}

Future<void> showPlanQr(
  BuildContext context,
  List<Routine> routines, {
  required String title,
  Map<int, String>? schedule,
}) async {
  if (routines.isEmpty) return;
  final data = encodePlanQrJson(fit.exportPlanJson(routines, schedule: schedule));
  final gc = context.gc;
  await showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheet) {
      final qrSize = math.min(340.0, MediaQuery.sizeOf(sheet).width - 40);
      final correctionLevel = data.length > 1000 ? QrErrorCorrectLevel.L : QrErrorCorrectLevel.M;
      return Container(
        padding: sheetPad(sheet),
        decoration: BoxDecoration(
          color: gc.bgRaised,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHandle(),
              const SizedBox(height: 18),
              Text(
                title,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.f(20, weight: FontWeight.w800, color: gc.text),
              ),
              const SizedBox(height: 6),
              Text(
                t.qrPlanInstructions,
                textAlign: TextAlign.center,
                style: AppTheme.f(12.5, weight: FontWeight.w500, color: gc.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 20),
              Container(
                width: qrSize,
                height: qrSize,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
                child: QrImageView(
                  data: data,
                  version: QrVersions.auto,
                  errorCorrectionLevel: correctionLevel,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(4),
                  gapless: true,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                  errorStateBuilder: (context, error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        t.qrTooLarge,
                        textAlign: TextAlign.center,
                        style: AppTheme.f(14, weight: FontWeight.w700, color: Colors.black),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                t.routineCount(routines.length),
                style: AppTheme.f(12, weight: FontWeight.w700, color: gc.textSecondary),
              ),
              const SizedBox(height: 18),
              GhostButton(label: t.close, icon: PhosphorIconsRegular.x, onTap: () => Navigator.pop(sheet)),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> scanPlanQr(BuildContext context) async {
  final raw = await Navigator.of(
    context,
  ).push<String>(MaterialPageRoute(builder: (_) => const _PlanQrScanner()));
  if (raw == null || !context.mounted) return;
  final decoded = decodePlanQr(raw);
  if (decoded == null) {
    showNotchToast(
      context,
      t.invalidInfyterQr,
      icon: PhosphorIconsFill.warningCircle,
      accent: context.gc.warn,
    );
    return;
  }
  await showPlanImportSheet(context, text: decoded);
}

class _PlanQrScanner extends StatefulWidget {
  const _PlanQrScanner();

  @override
  State<_PlanQrScanner> createState() => _PlanQrScannerState();
}

class _PlanQrScannerState extends State<_PlanQrScanner> {
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'infyterQrScanner');
  bool _handled = false;
  QRViewController? _controller;

  void _onQRViewCreated(QRViewController controller) {
    _controller = controller;
    controller.scannedDataStream.listen(_detect);
  }

  void _detect(Barcode barcode) {
    if (_handled) return;
    final value = barcode.code;
    if (value == null || value.isEmpty) return;
    _handled = true;
    _controller?.pauseCamera();
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewport = constraints.biggest;
            final scanWindow = _scannerWindow(viewport);
            return Stack(
              fit: StackFit.expand,
              children: [
                QRView(
                  key: _qrKey,
                  onQRViewCreated: _onQRViewCreated,
                  cameraFacing: CameraFacing.back,
                  formatsAllowed: const [BarcodeFormat.qrcode],
                ),
                IgnorePointer(child: CustomPaint(painter: _ScannerOverlay(scanWindow))),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RoundAction(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(PhosphorIconsRegular.x, size: 19, color: Colors.white),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              t.importByQr,
                              style: AppTheme.f(19, weight: FontWeight.w800, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 32,
                  right: 32,
                  bottom: 48,
                  child: SafeArea(
                    top: false,
                    child: Text(
                      t.alignQr,
                      textAlign: TextAlign.center,
                      style: AppTheme.f(14, weight: FontWeight.w600, color: gc.text),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

Rect _scannerWindow(Size size) {
  final availableWidth = math.max(0.0, size.width - 48);
  final availableHeight = math.max(0.0, size.height - 220);
  final side = math.min(320.0, math.min(availableWidth, availableHeight));
  return Rect.fromCenter(center: Offset(size.width / 2, size.height * .48), width: side, height: side);
}

class _ScannerOverlay extends CustomPainter {
  const _ScannerOverlay(this.scanWindow);

  final Rect scanWindow;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(scanWindow, const Radius.circular(24)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: .44));
    canvas.drawRRect(
      RRect.fromRectAndRadius(scanWindow, const Radius.circular(24)),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlay oldDelegate) => oldDelegate.scanWindow != scanWindow;
}
