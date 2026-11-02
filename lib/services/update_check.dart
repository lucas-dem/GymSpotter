/// Shared core of the store version check (Android and iOS).
///
/// The check fails open: only a fresh, readable answer that names a newer version, released at least
/// [kUpdateGrace] ago and installable on this device, asks the person to update. Any other answer, error or missing
/// piece of information leaves the app usable.
library;

enum UpdateVerdict { upToDate, mustUpdate, unknown }

enum UpdateReason {
  /// The store has a newer version: the only reason that asks to update.
  newer,

  /// Installed and published are the same version.
  equal,

  /// The installed version is newer than the published one (TestFlight, internal testing).
  older,

  /// The store has no Infyter for that country (or at all).
  noResults,

  /// The answer is about another app.
  otherApp,

  /// The answer could not be read.
  badJson,

  timeout,

  /// No connection to the store, or the connection failed.
  network,

  /// The store answered with an HTTP error.
  http,

  /// The device says it has no internet connection.
  offline,

  /// The newer version came out less than [kUpdateGrace] ago (or its date is unknown).
  grace,

  /// The newer version needs a newer operating system than this device has (or the system version is unknown).
  minOs,

  /// The installed version is not known (a build without the version defines).
  noVersion,

  /// The device has no country to ask the store about.
  noRegion,

  /// Google Play could not answer (no Play Store, not installed from Play, any error).
  playError,

  /// Google Play has no update for this device.
  notAvailable,

  /// Google Play does not allow an update right now.
  notAllowed,

  /// Anything else went wrong while checking.
  error,
}

class UpdateCheck {
  const UpdateCheck(this.reason, {this.storeVersion});

  final UpdateReason reason;

  /// The published version, when the answer named one.
  final String? storeVersion;

  UpdateVerdict get verdict => switch (reason) {
    UpdateReason.newer => UpdateVerdict.mustUpdate,
    UpdateReason.equal || UpdateReason.older => UpdateVerdict.upToDate,
    _ => UpdateVerdict.unknown,
  };

  bool get mustUpdate => verdict == UpdateVerdict.mustUpdate;

  @override
  String toString() => 'UpdateCheck(${reason.name}${storeVersion == null ? '' : ', $storeVersion'})';
}

/// Time a newer version must have been published before it is required. On iOS the lookup can name a version
/// before it can be downloaded everywhere; on both stores it leaves time to stop a bad release.
const kUpdateGrace = Duration(hours: 48);

final RegExp _versionPattern = RegExp(r'^\d+(\.\d+)*$');

/// Compares two numeric versions ("1.3.10" > "1.3.9"; "1.3" == "1.3.0"). Throws [FormatException] when either is
/// not made of numbers and dots.
int compareVersions(String a, String b) {
  final x = _parts(a);
  final y = _parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

List<int> _parts(String v) {
  if (!_versionPattern.hasMatch(v)) throw FormatException('Not a version', v);
  return [for (final p in v.split('.')) int.parse(p)];
}
