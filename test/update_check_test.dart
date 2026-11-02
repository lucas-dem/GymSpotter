// Núcleo del validador de versión (sesión 28): comparar versiones X.Y.Z y qué significa cada resultado.
import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/services/update_check.dart';

void main() {
  group('compareVersions', () {
    test('compara número por número, no como texto', () {
      expect(compareVersions('1.3.10', '1.3.9'), greaterThan(0));
      expect(compareVersions('1.3.9', '1.3.10'), lessThan(0));
      expect(compareVersions('2.0.0', '1.9.9'), greaterThan(0));
      expect(compareVersions('1.4', '1.3.9'), greaterThan(0));
    });

    test('lo que falta cuenta como 0', () {
      expect(compareVersions('1.3', '1.3.0'), 0);
      expect(compareVersions('1.3.1', '1.3.1'), 0);
      expect(compareVersions('2', '2.0.0'), 0);
    });

    test('una versión que no es numérica lanza FormatException', () {
      expect(() => compareVersions('1.3.x', '1.3.1'), throwsFormatException);
      expect(() => compareVersions('', '1.3.1'), throwsFormatException);
      expect(() => compareVersions('1.3.1', '1..3'), throwsFormatException);
      expect(() => compareVersions('v1.3.1', '1.3.1'), throwsFormatException);
    });
  });

  group('UpdateCheck', () {
    test('solo "hay una versión más nueva" obliga a actualizar', () {
      for (final reason in UpdateReason.values) {
        expect(UpdateCheck(reason).mustUpdate, reason == UpdateReason.newer, reason: reason.name);
      }
    });

    test('igual o instalada mayor es estar al día; cualquier problema es "no se sabe"', () {
      expect(const UpdateCheck(UpdateReason.equal).verdict, UpdateVerdict.upToDate);
      expect(const UpdateCheck(UpdateReason.older).verdict, UpdateVerdict.upToDate);
      for (final reason in [
        UpdateReason.timeout,
        UpdateReason.network,
        UpdateReason.offline,
        UpdateReason.badJson,
        UpdateReason.grace,
      ]) {
        expect(UpdateCheck(reason).verdict, UpdateVerdict.unknown, reason: reason.name);
      }
    });
  });
}
