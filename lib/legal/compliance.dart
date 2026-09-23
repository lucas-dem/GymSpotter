/// Release metadata used to comply with the licenses of GymSpotter and its
/// bundled assets. Store builds must provide all three values with
/// `--dart-define`; see `docs/store/RELEASE_CHECKLIST.md`.
abstract final class Compliance {
  static const sourceCodeUrl = String.fromEnvironment('SOURCE_CODE_URL');
  static const sourceRevision = String.fromEnvironment('SOURCE_REVISION');
  static const buildDate = String.fromEnvironment('BUILD_DATE');

  static const appName = 'GymSpotter';
  static const version = '1.3.0+5';
  static const license = 'GNU General Public License v3.0';
  static const modifiedSince = '22 de septiembre de 2026';

  static bool get hasReleaseMetadata =>
      sourceCodeUrl.startsWith('https://') && sourceRevision.isNotEmpty && buildDate.isNotEmpty;
}

/// Spanish legal copy kept outside the widget tree so the wording can be
/// reviewed independently from layout code.
abstract final class LegalCopy {
  static const section = 'LEGAL';
  static const settingsLabel = 'Información legal y licencias';
  static const title = 'Información legal';
  static const freeSoftware =
      'Software libre distribuido bajo GNU General Public License v3.0. '
      'Podés usarlo, estudiarlo, modificarlo y redistribuirlo conforme a esa licencia. '
      'Se entrega sin garantía.';
  static const source = 'Código fuente de esta versión';
  static const gpl = 'Licencia GPL-3.0';
  static const credits = 'Créditos y licencias de recursos';
  static const creditsTitle = 'Créditos';
  static const privacy = 'Privacidad';
  static const dependencies = 'Licencias de dependencias';
}
