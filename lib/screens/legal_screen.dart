import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../legal/compliance.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return Scaffold(
      backgroundColor: gc.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenHeader(
                title: LegalCopy.title,
                onBack: () => Navigator.of(context).pop(),
                titleSize: 18,
                titleSpacing: 1,
              ),
              const SizedBox(height: 20),
              _notice(gc),
              const SizedBox(height: 18),
              _links(context, gc),
            ],
          ),
        ),
      ),
    );
  }

  Widget _notice(GymColors gc) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: gc.bgRaised, borderRadius: BorderRadius.circular(20)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          Compliance.appName,
          style: AppTheme.f(22, weight: FontWeight.w800, color: gc.text),
        ),
        const SizedBox(height: 6),
        Text(
          'Versión ${Compliance.version}',
          style: AppTheme.f(12.5, weight: FontWeight.w600, color: gc.textSecondary),
        ),
        const SizedBox(height: 14),
        Text(
          '${LegalCopy.freeSoftware} Versión modificada desde el ${Compliance.modifiedSince}.',
          style: AppTheme.f(13, weight: FontWeight.w500, color: gc.textSecondary, height: 1.5),
        ),
        if (Compliance.sourceRevision.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Revisión: ${Compliance.sourceRevision}\nCompilación: ${Compliance.buildDate}',
            style: AppTheme.f(11.5, weight: FontWeight.w600, color: gc.textTertiary, height: 1.45),
          ),
        ],
      ],
    ),
  );

  Widget _links(BuildContext context, GymColors gc) {
    final rows = <(IconData, String, VoidCallback)>[
      if (Compliance.sourceCodeUrl.isNotEmpty)
        (
          PhosphorIconsRegular.code,
          LegalCopy.source,
          () => launchUrl(Uri.parse(Compliance.sourceCodeUrl), mode: LaunchMode.externalApplication),
        ),
      (PhosphorIconsRegular.fileText, LegalCopy.gpl, () => _openText(context, LegalCopy.gpl, 'LICENSE')),
      (
        PhosphorIconsRegular.users,
        LegalCopy.credits,
        () => _openText(context, LegalCopy.creditsTitle, 'CREDITS.md'),
      ),
      (
        PhosphorIconsRegular.shieldCheck,
        LegalCopy.privacy,
        () => _openText(context, LegalCopy.privacy, 'PRIVACY.md'),
      ),
      (
        PhosphorIconsRegular.package,
        LegalCopy.dependencies,
        () => showLicensePage(
          context: context,
          applicationName: Compliance.appName,
          applicationVersion: Compliance.version,
          applicationLegalese: 'Distribuido bajo GNU GPL-3.0. Sin garantía.',
        ),
      ),
    ];

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: gc.bgRaised, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            InkWell(
              onTap: rows[i].$3,
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: i < rows.length - 1
                      ? Border(bottom: BorderSide(color: gc.border.withValues(alpha: 0.6)))
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(rows[i].$1, size: 19, color: gc.textSecondary),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        rows[i].$2,
                        style: AppTheme.f(14, weight: FontWeight.w600, color: gc.text),
                      ),
                    ),
                    Icon(PhosphorIconsRegular.caretRight, size: 15, color: gc.textTertiary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openText(BuildContext context, String title, String asset) async {
    final text = await DefaultAssetBundle.of(context).loadString(asset);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _LegalTextScreen(title: title, text: text),
      ),
    );
  }
}

class _LegalTextScreen extends StatelessWidget {
  const _LegalTextScreen({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final gc = context.gc;
    return Scaffold(
      backgroundColor: gc.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenHeader(
                title: title,
                onBack: () => Navigator.of(context).pop(),
                titleSize: 18,
                titleSpacing: 1,
              ),
              const SizedBox(height: 18),
              SelectableText(
                text,
                style: AppTheme.f(12.5, weight: FontWeight.w500, color: gc.textSecondary, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
