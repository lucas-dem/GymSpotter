import 'dart:io';

import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../services/app_store_lookup.dart' show kAppStoreUrl;
import '../services/play_update.dart' show kPlayStoreUrl, kPlayStoreWebUrl;
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/app_background.dart';
import '../widgets/ui_kit.dart';

/// Opens the page where Infyter can be updated: on Android the Play Store app, or Google Play on the web when the
/// app is missing; on iPhone the fixed App Store page. Returns whether a page opened. Never throws.
Future<bool> openStoreForUpdate({String? os, Future<bool> Function(Uri uri)? launch}) async {
  final open = launch ?? (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
  final links = switch (os ?? Platform.operatingSystem) {
    'android' => const [kPlayStoreUrl, kPlayStoreWebUrl],
    'ios' => const [kAppStoreUrl],
    _ => const <String>[],
  };
  for (final link in links) {
    try {
      if (await open(Uri.parse(link))) return true;
    } catch (e) {
      debugPrint('Validador de versión: no se pudo abrir $link: $e');
    }
  }
  return false;
}

/// Covers the app while the store has a newer version (see UpdateGate). The only action is opening the store; the
/// person's data stays on the device.
class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({super.key, required this.version, this.openStore = openStoreForUpdate});

  /// The store's version, when the store gives one (App Store). Google Play only reports a build number, so on
  /// Android there is none and the screen shows no number.
  final String? version;
  final Future<bool> Function() openStore;

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  bool _opening = false;
  bool _failed = false;

  Future<void> _update() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _failed = false;
    });
    final opened = await widget.openStore();
    if (!mounted) return;
    setState(() {
      _opening = false;
      _failed = !opened;
    });
  }

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    final version = widget.version;
    return Scaffold(
      backgroundColor: gc.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: AppBackground(pattern: 'dots')),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(PhosphorIconsRegular.arrowCircleUp, size: 64, color: gc.ember),
                      const SizedBox(height: 22),
                      Text(
                        t.updateRequiredTitle,
                        textAlign: TextAlign.center,
                        style: AppTheme.f(27, weight: FontWeight.w800, color: gc.text),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        t.updateRequiredBody,
                        textAlign: TextAlign.center,
                        style: AppTheme.f(16, weight: FontWeight.w500, color: gc.textSecondary, height: 1.4),
                      ),
                      if (version != null && version.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          t.updateRequiredVersion(version),
                          textAlign: TextAlign.center,
                          style: AppTheme.f(14.5, color: gc.text),
                        ),
                      ],
                      const SizedBox(height: 26),
                      SoftCard(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(PhosphorIconsRegular.shieldCheck, size: 22, color: gc.sage),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                t.updateRequiredData,
                                style: AppTheme.f(
                                  14,
                                  weight: FontWeight.w500,
                                  color: gc.textSecondary,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      PrimaryButton(label: t.updateRequiredButton, onTap: _update),
                      if (_failed) ...[
                        const SizedBox(height: 14),
                        Text(
                          t.updateStoreFailed,
                          textAlign: TextAlign.center,
                          style: AppTheme.f(14, weight: FontWeight.w500, color: gc.danger, height: 1.35),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
