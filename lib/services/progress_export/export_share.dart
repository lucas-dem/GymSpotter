import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'export_job.dart';

const kExportTextLimit = 60000;

/// Empties and returns the folder that holds the file being shared.
Future<Directory> freshExportDir() async {
  final tmp = await getTemporaryDirectory();
  final dir = Directory('${tmp.path}/progress_export');
  if (await dir.exists()) await dir.delete(recursive: true);
  return dir.create(recursive: true);
}

final _sharedCopyName = RegExp(r'^infyter-progreso-\d{4}-\d{2}-\d{2}_\d{4}-\d{2}-\d{2}\.(txt|pdf|xlsx|csv|json)$');

/// Deletes the export folder and the copy share_plus makes of [fileName] on Android.
Future<void> deleteExportFiles([String? fileName]) async {
  try {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/progress_export');
    if (await dir.exists()) await dir.delete(recursive: true);
    if (fileName != null) {
      final copy = File('${tmp.path}/share_plus/$fileName');
      if (await copy.exists()) await copy.delete();
    }
  } catch (_) {}
}

/// Removes what an earlier export left behind, for example after the app was killed. Runs at app start
/// and when the sheet opens.
Future<void> sweepExportLeftovers() async {
  await deleteExportFiles();
  try {
    final tmp = await getTemporaryDirectory();
    final shared = Directory('${tmp.path}/share_plus');
    if (!await shared.exists()) return;
    await for (final entry in shared.list()) {
      if (entry is File && _sharedCopyName.hasMatch(entry.uri.pathSegments.last)) await entry.delete();
    }
  } catch (_) {}
}

/// Deletes [file] and the copy share_plus made of it on Android.
Future<void> deleteSharedFile(File file) async {
  try {
    if (await file.exists()) await file.delete();
    final tmp = await getTemporaryDirectory();
    final copy = File('${tmp.path}/share_plus/${file.uri.pathSegments.last}');
    if (await copy.exists()) await copy.delete();
  } catch (_) {}
}

final _dataExportName = RegExp(r'^infyter-(backup-\d{4}-\d{2}-\d{2}\.zip|workouts-\d{4}-\d{2}-\d{2}\.csv)$');

/// Removes the backup and workouts CSV that an earlier share left in the temporary folder. Runs at app start.
Future<void> sweepDataExportLeftovers() async {
  try {
    final tmp = await getTemporaryDirectory();
    for (final dir in [Directory(tmp.path), Directory('${tmp.path}/share_plus')]) {
      if (!await dir.exists()) continue;
      await for (final entry in dir.list()) {
        if (entry is File && _dataExportName.hasMatch(entry.uri.pathSegments.last)) await entry.delete();
      }
    }
  } catch (_) {}
}

/// Deletes every file Infyter left in the temporary folder to share it, the copies share_plus made of them and the
/// copies image_picker keeps of the photos and videos the person chose.
Future<void> deleteAllShareFiles() async {
  await deleteExportFiles();
  try {
    final tmp = await getTemporaryDirectory();
    for (final dir in [Directory(tmp.path), Directory('${tmp.path}/share_plus')]) {
      if (!await dir.exists()) continue;
      await for (final entry in dir.list()) {
        final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => '');
        final ours = entry is File && name.startsWith('infyter-');
        final picked = dir.path == tmp.path && (name.startsWith('image_picker') || name.startsWith('scaled_'));
        if (!ours && !picked) continue;
        try {
          await entry.delete(recursive: true);
        } catch (_) {}
      }
    }
  } catch (_) {}
}

Future<File> writeExportFile(Directory dir, String name, Uint8List bytes) =>
    File('${dir.path}/$name').writeAsBytes(bytes, flush: true);

Future<ShareResult> shareExportFile(File file, ExportKind kind, String subject, Rect? origin) =>
    SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: kind.mime)],
        subject: subject,
        sharePositionOrigin: origin,
      ),
    );

Future<void> copyExportText(String text) => Clipboard.setData(ClipboardData(text: text));
