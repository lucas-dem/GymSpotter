import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'update_check.dart';

/// Where "Update" takes the person on Android: the Play Store app, or Google Play on the web if that fails.
const kPlayStoreUrl = 'market://details?id=com.infyter.app';
const kPlayStoreWebUrl = 'https://play.google.com/store/apps/details?id=com.infyter.app';

/// Test builds only (`--dart-define=INFYTER_TIENDA_SIMULADA=true`): the Play answer is read from
/// `<Documents>/tienda_simulada.json` (`{"versionCode": 5, "stalenessDays": 3}`), written with adb. Store builds never
/// pass this define, so the simulated store is compiled out.
const kTiendaSimulada = bool.fromEnvironment('INFYTER_TIENDA_SIMULADA');

/// Play Core's UpdateAvailability.UPDATE_AVAILABLE.
const _updateAvailable = 2;

/// The version check on Android: asks the Play Store app on the phone through Play In-App Updates. The app itself
/// has no INTERNET permission; it only checks, with ACCESS_NETWORK_STATE, that the phone is online.
class PlayUpdateSource {
  PlayUpdateSource({
    MethodChannel channel = const MethodChannel('infyter/store_update'),
    this.timeout = const Duration(seconds: 8),
    this.simulated = kTiendaSimulada,
    Future<String?> Function()? readSimulated,
  }) : _channel = channel,
       _readSimulated = readSimulated ?? _readSimulatedFile;

  final MethodChannel _channel;
  final Duration timeout;
  final bool simulated;
  final Future<String?> Function() _readSimulated;

  Future<UpdateCheck> check() async {
    try {
      final device = await _channel.invokeMapMethod<String, Object?>('device').timeout(timeout);
      final online = device?['online'] == true;
      final installed = device?['installedVersionCode'];
      if (installed is! int) return const UpdateCheck(UpdateReason.noVersion);
      if (!online) return evaluatePlay(online: false, installed: installed, play: null);
      final fake = simulated ? await _simulatedAnswer(installed) : null;
      final play = fake ?? await _channel.invokeMapMethod<String, Object?>('play').timeout(timeout);
      return evaluatePlay(online: online, installed: installed, play: play);
    } on TimeoutException {
      return const UpdateCheck(UpdateReason.timeout);
    } catch (_) {
      // PlatformException (no Play Store, not installed from Play), MissingPluginException, a broken fake file.
      return const UpdateCheck(UpdateReason.playError);
    }
  }

  // What Play would answer for the simulated published versionCode.
  Future<Map<String, Object?>?> _simulatedAnswer(int installed) async {
    final raw = await _readSimulated();
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final code = data['versionCode'] as int;
    final newer = code > installed;
    return {
      'availability': newer ? _updateAvailable : 1,
      'availableVersionCode': newer ? code : 0,
      'immediateAllowed': newer,
      'stalenessDays': newer ? data['stalenessDays'] as int? : null,
    };
  }

  static Future<String?> _readSimulatedFile() async {
    final file = File('${(await getApplicationDocumentsDirectory()).path}/tienda_simulada.json');
    return file.existsSync() ? file.readAsString() : null;
  }
}

/// Decides from what the phone and Google Play said. Play gives no version name, so [UpdateCheck.storeVersion] is
/// null here.
UpdateCheck evaluatePlay({
  required bool online,
  required int installed,
  required Map<String, Object?>? play,
}) {
  if (!online) return const UpdateCheck(UpdateReason.offline);
  if (play == null) return const UpdateCheck(UpdateReason.playError);
  if (play['availability'] != _updateAvailable) return const UpdateCheck(UpdateReason.notAvailable);
  final code = play['availableVersionCode'];
  if (code is! int) return const UpdateCheck(UpdateReason.playError);
  if (code <= installed) return const UpdateCheck(UpdateReason.equal);
  if (play['immediateAllowed'] != true) return const UpdateCheck(UpdateReason.notAllowed);
  final days = play['stalenessDays'];
  if (days is! int || days < kUpdateGrace.inDays) return const UpdateCheck(UpdateReason.grace);
  return const UpdateCheck(UpdateReason.newer);
}
