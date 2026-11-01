// Versión visible (sesiones 17 y 26). Se muestra "nombre (build)", por ejemplo "1.3.2 (3)". Sin defines: la de
// pubspec.yaml ("1.3.0+1" se ve "1.3.0 (1)"). Con los defines de tienda: la publicada. Para probar lo segundo:
//   flutter test test/version_visible_test.dart \
//     --dart-define=APP_BUILD_NAME=1.3.2 --dart-define=APP_BUILD_NUMBER=3
// Los casos que no aplican a la corrida se marcan como omitidos, no pasan solos.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/legal/compliance.dart';
import 'package:infyter/screens/legal_screen.dart';
import 'package:infyter/theme/app_theme.dart';

final _format = RegExp(r'^\d+\.\d+\.\d+ \(\d+\)$');

String _declared() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  return RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!.group(1)!;
}

void main() {
  test('el respaldo de desarrollo es exactamente el version: de pubspec.yaml', () {
    expect(
      Compliance.pubspecVersion,
      _declared(),
      reason: 'si cambia pubspec.yaml, actualizá pubspecVersion',
    );
  });

  test(
    'sin defines, se ve la versión de pubspec.yaml como "nombre (build)"',
    () {
      final parts = _declared().split('+');
      expect(Compliance.version, '${parts[0]} (${parts[1]})');
    },
    skip: Compliance.hasStoreVersion ? 'corrida con APP_BUILD_NAME/APP_BUILD_NUMBER' : false,
  );

  test(
    'con los defines de tienda, se ve "build-name (build-number)"',
    () {
      const name = String.fromEnvironment('APP_BUILD_NAME');
      const number = String.fromEnvironment('APP_BUILD_NUMBER');
      expect(Compliance.version, '$name ($number)');
    },
    skip: Compliance.hasStoreVersion ? false : 'corrida sin defines de tienda',
  );

  test('el formato es "X.Y.Z (N)"', () {
    expect(_format.hasMatch(Compliance.version), isTrue, reason: '"${Compliance.version}"');
  });

  test('los metadatos legales siguen saliendo de sus defines', () {
    expect(Compliance.sourceCodeUrl, const String.fromEnvironment('SOURCE_CODE_URL'));
    expect(Compliance.sourceRevision, const String.fromEnvironment('SOURCE_REVISION'));
    expect(Compliance.buildDate, const String.fromEnvironment('BUILD_DATE'));
  });

  testWidgets('la pantalla legal muestra la versión visible', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: const LegalScreen()));
    expect(find.text('Versión ${Compliance.version}'), findsOneWidget);
  });
}
