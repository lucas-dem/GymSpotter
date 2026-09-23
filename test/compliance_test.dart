import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('required distribution notices are present', () {
    for (final path in [
      'LICENSE',
      'NOTICE.md',
      'CREDITS.md',
      'MODIFICATIONS.md',
      'PRIVACY.md',
      'assets/fonts/Nunito-OFL.txt',
      'docs/store/RELEASE_CHECKLIST.md',
      'ios/Runner/PrivacyInfo.xcprivacy',
    ]) {
      expect(File(path).existsSync(), isTrue, reason: '$path must ship with the corresponding source');
    }
  });

  test('mobile store identifiers and privacy metadata are configured', () {
    final android = File('android/app/build.gradle.kts').readAsStringSync();
    final ios = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final privacy = File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();

    expect(android, contains('applicationId = "com.gymspotter.app"'));
    expect(android, contains('debug signing is not allowed'));
    expect(ios, contains('PRODUCT_BUNDLE_IDENTIFIER = com.gymspotter.app;'));
    expect(ios, contains('PrivacyInfo.xcprivacy in Resources'));
    expect(privacy, contains('<key>NSPrivacyTracking</key>'));
    expect(privacy, contains('<false/>'));
  });

  test('legal documents are bundled in the application', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final asset in ['LICENSE', 'NOTICE.md', 'CREDITS.md', 'PRIVACY.md']) {
      expect(pubspec, contains('- $asset'), reason: '$asset must be readable from the legal screen');
    }
  });

  test('store build scripts require exact source metadata', () {
    final android = File('scripts/build_android_store.ps1').readAsStringSync();
    final ios = File('scripts/build_ios_store.sh').readAsStringSync();
    for (final define in ['SOURCE_CODE_URL', 'SOURCE_REVISION', 'BUILD_DATE']) {
      expect(android, contains(define));
      expect(ios, contains(define));
    }
  });
}
