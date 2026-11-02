import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../legal/compliance.dart';
import '../services/app_store_lookup.dart';
import '../services/play_update.dart';
import '../services/update_check.dart';
import 'fit_state.dart';

typedef UpdateSource = Future<UpdateCheck> Function();

/// After returning to the app, the store is asked again only when the last attempt is at least this old.
const kUpdateRecheck = Duration(hours: 1);

/// Editors the update screen does not cover, because closing them loses what is not saved yet: a diary note being
/// written (its attached copies are deleted too) and an AI plan being pasted.
const kUpdateWaitRoutes = {'note-edit', 'ai-plan'};

/// Decides when to ask the store and whether "Update Infyter" covers the app. The last answer rules: a failed check
/// after a block lifts it (fail-open).
class UpdateGate extends ChangeNotifier {
  UpdateGate({UpdateSource? source, DateTime Function()? clock})
    : _source = source,
      _clock = clock ?? DateTime.now;

  final UpdateSource? _source;
  final DateTime Function() _clock;
  UpdateCheck? _last;
  DateTime? _lastAttempt;
  Future<void>? _running;

  UpdateCheck? get last => _last;

  bool get mustUpdate => _last?.mustUpdate ?? false;

  String? get storeVersion => _last?.storeVersion;

  /// Whether the update screen covers the app now. Never while a workout is open, paused or waiting to be saved, nor
  /// in an editor whose input is not saved yet ([kUpdateWaitRoutes]): it waits until they are finished or closed.
  bool blocks(FitState fit) => mustUpdate && fit.session == null && !kUpdateWaitRoutes.contains(fit.route);

  /// Asks the store now (one check at a time).
  Future<void> checkNow() => _running ??= _check().whenComplete(() => _running = null);

  /// Back in the foreground: asks again if the last attempt is [kUpdateRecheck] old.
  Future<void> resumed() async {
    final at = _lastAttempt;
    if (at != null && _clock().difference(at) < kUpdateRecheck) return;
    await checkNow();
  }

  Future<void> _check() async {
    final source = _source;
    if (source == null) return;
    _lastAttempt = _clock();
    UpdateCheck result;
    try {
      result = await source();
    } catch (e) {
      debugPrint('Validador de versión: la consulta falló: $e');
      result = const UpdateCheck(UpdateReason.error);
    }
    _last = result;
    debugPrint('Validador de versión: $result');
    notifyListeners();
  }
}

const _appVersion = MethodChannel('infyter/app_version');

/// The version of this iPhone binary (CFBundleShortVersionString, set by --build-name): the one the App Store
/// compares. Null when it can't be read; then there is no check.
Future<String?> bundleVersionName() async {
  try {
    return await _appVersion.invokeMethod<String>('versionName');
  } catch (e) {
    debugPrint('Validador de versión: no se pudo leer la versión del binario: $e');
    return null;
  }
}

/// The store each system asks. Android asks Google Play, which knows the installed versionCode. iPhone compares the
/// version of the binary with Apple's lookup, never the APP_BUILD_NAME define: a define typed wrong in a release
/// must not lock out everyone who installed it. Only store builds (the ones with the version defines) check on
/// iPhone, so development builds never block. Other systems (tests, desktop) have none.
UpdateSource? updateSourceFor({
  required String os,
  required bool storeBuild,
  Future<String?> Function() installedVersion = bundleVersionName,
  AppStoreLookup? lookup,
  String? Function()? country,
  String Function()? osVersion,
  DateTime Function()? now,
}) {
  switch (os) {
    case 'android':
      return PlayUpdateSource().check;
    case 'ios':
      if (!storeBuild) return null;
      final store = lookup ?? AppStoreLookup();
      return () async {
        String? installed;
        try {
          installed = await installedVersion();
        } catch (e) {
          debugPrint('Validador de versión: no se pudo leer la versión del binario: $e');
        }
        if (installed == null || installed.isEmpty) return const UpdateCheck(UpdateReason.noVersion);
        const built = String.fromEnvironment('APP_BUILD_NAME');
        if (built.isNotEmpty && built != installed) {
          debugPrint('Validador de versión: APP_BUILD_NAME ($built) no coincide con el binario ($installed)');
        }
        return store.check(
          installed: installed,
          country: (country ?? () => regionOf(Platform.localeName))(),
          osVersion: (osVersion ?? () => Platform.operatingSystemVersion)(),
          now: (now ?? DateTime.now)(),
        );
      };
  }
  return null;
}

/// The app's gate. Tests replace it with one that has a fake source.
UpdateGate updateGate = UpdateGate(
  source: updateSourceFor(os: Platform.operatingSystem, storeBuild: Compliance.hasStoreVersion),
);
