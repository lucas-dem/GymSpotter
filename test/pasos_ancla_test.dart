import 'package:flutter_test/flutter_test.dart';
import 'package:infyter/services/step_anchor.dart';
import 'package:infyter/services/step_source.dart';

const int _minute = 60 * 1000;
const int _hour = 60 * _minute;

void main() {
  var tz = -180;

  StepLocalTime clock(int wallMs) {
    final t = DateTime.fromMillisecondsSinceEpoch(wallMs, isUtc: true).add(Duration(minutes: tz));
    final day = '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    return StepLocalTime(day, t.hour * 60 + t.minute, tz);
  }

  int local(int month, int day, int hour, [int minute = 0]) =>
      DateTime.utc(2026, month, day, hour, minute).millisecondsSinceEpoch - tz * _minute;

  StepCounterReading reading(int counter, int wallMs, int elapsedMs, {int boot = 7}) =>
      StepCounterReading(counter: counter, wallMs: wallMs, elapsedMs: elapsedMs, bootCount: boot);

  StepAnchor advance(StepAnchor? anchor, StepCounterReading r) =>
      advanceStepAnchor(anchor, r, localTime: clock);

  final eight = local(11, 20, 8);
  const bootElapsed = 10 * _hour;

  setUp(() => tz = -180);

  group('primer dia', () {
    test('sin ancla: no suma nada y el dia cuenta desde la hora de la lectura', () {
      final a = advance(null, reading(5000, eight, bootElapsed));
      expect(a.day, '2026-11-20');
      expect(a.steps, 0);
      expect(a.fromMinute, 8 * 60);
      expect(a.counter, 5000);
      expect(a.offsetMinutes, -180);
    });

    test('primera lectura a las 00:00: el dia conto desde el principio', () {
      final a = advance(null, reading(5000, local(11, 20, 0), bootElapsed));
      expect(a.fromMinute, isNull);
    });
  });

  group('mismo dia', () {
    test('suma lo contado entre dos lecturas y mantiene desde cuando cuenta', () {
      final a = advance(null, reading(5000, eight, bootElapsed));
      final b = advance(a, reading(7000, eight + _hour, bootElapsed + _hour));
      expect(b.steps, 2000);
      expect(b.fromMinute, 8 * 60);
      expect(b.counter, 7000);
      final c = advance(b, reading(7600, eight + 2 * _hour, bootElapsed + 2 * _hour));
      expect(c.steps, 2600);
    });

    test('releer lo mismo no cambia nada', () {
      final a = advance(null, reading(5000, eight, bootElapsed));
      final r = reading(6000, eight + _hour, bootElapsed + _hour);
      final b = advance(a, r);
      expect(advance(b, r).steps, b.steps);
    });

    test('un dia con 0 pasos medidos vale 0, no falta', () {
      final a = advance(null, reading(5000, eight, bootElapsed));
      final b = advance(a, reading(5000, eight + _hour, bootElapsed + _hour));
      expect(b.reading.day, '2026-11-20');
      expect(b.reading.steps, 0);
    });

    test('mas de 4 pasos por segundo no se suma, pero la lectura pasa a ser el ancla', () {
      final a = advance(null, reading(5000, eight, bootElapsed));
      final b = advance(a, reading(5000 + 241, eight + _minute, bootElapsed + _minute));
      expect(b.steps, 0);
      expect(b.counter, 5241);
      final c = advance(b, reading(5241 + 240, eight + 2 * _minute, bootElapsed + 2 * _minute));
      expect(c.steps, 240);
    });
  });

  group('otro dia', () {
    test('no reparte los pasos entre dias y marca el dia nuevo como parcial', () {
      final a = advance(null, reading(5000, local(11, 20, 22), bootElapsed));
      final b = advance(a, reading(5400, local(11, 20, 23), bootElapsed + _hour));
      expect(b.steps, 400);
      final c = advance(b, reading(9000, local(11, 21, 9, 15), bootElapsed + 11 * _hour));
      expect(c.day, '2026-11-21');
      expect(c.steps, 0);
      expect(c.fromMinute, 9 * 60 + 15);
      expect(b.reading.steps, 400);
    });

    test('con la app abierta a medianoche el dia nuevo cuenta completo', () {
      final a = advance(null, reading(5000, local(11, 20, 23, 50), bootElapsed));
      final b = advance(a, reading(5010, local(11, 21, 0), bootElapsed + 10 * _minute));
      expect(b.fromMinute, isNull);
      final c = advance(b, reading(5300, local(11, 21, 0, 30), bootElapsed + 40 * _minute));
      expect(c.steps, 290);
      expect(c.fromMinute, isNull);
    });
  });

  group('reinicio', () {
    test('mismo dia con contador menor y arranque despues del ancla: suma lo dado desde el arranque', () {
      final a = advance(null, reading(5000, eight, bootElapsed));
      final b = advance(a, reading(6000, eight + _hour, bootElapsed + _hour));
      final after = advance(b, reading(300, eight + 3 * _hour, _hour, boot: 8));
      expect(after.steps, 1000 + 300);
      expect(after.fromMinute, 8 * 60);
      expect(after.bootCount, 8);
      final later = advance(after, reading(500, eight + 4 * _hour, 2 * _hour, boot: 8));
      expect(later.steps, 1500);
    });

    test('contador menor sin poder leer bootCount tambien es reinicio', () {
      final a = advance(null, reading(5000, eight, bootElapsed, boot: -1));
      final b = advance(a, reading(200, eight + 2 * _hour, _hour, boot: -1));
      expect(b.steps, 200);
    });

    test('bootCount cambio pero el contador es mayor: no se puede saber, no suma', () {
      final a = advance(null, reading(100, eight, bootElapsed));
      final b = advance(a, reading(900, eight + 2 * _hour, _hour, boot: 8));
      expect(b.steps, 0);
      expect(b.counter, 900);
      final c = advance(b, reading(1000, eight + 3 * _hour, 2 * _hour, boot: 8));
      expect(c.steps, 100);
    });

    test('el tiempo desde el arranque bajo con contador mayor y sin bootCount: no suma', () {
      final a = advance(null, reading(100, eight, bootElapsed, boot: -1));
      final b = advance(a, reading(900, eight + 2 * _hour, _hour, boot: -1));
      expect(b.steps, 0);
    });

    test('arranque antes del ancla: no suma', () {
      final a = advance(null, reading(5000, eight, bootElapsed));
      final b = advance(a, reading(300, eight + _hour, 2 * _hour, boot: 8));
      expect(b.steps, 0);
    });

    test('reinicio que cae en otro dia: no recupera nada', () {
      final a = advance(null, reading(5000, local(11, 20, 21), bootElapsed));
      final b = advance(a, reading(5500, local(11, 20, 22), bootElapsed + _hour));
      final c = advance(b, reading(400, local(11, 21, 1), 2 * _hour, boot: 8));
      expect(c.day, '2026-11-21');
      expect(c.steps, 0);
      expect(c.fromMinute, 60);
      expect(b.reading.steps, 500);
    });

    test('lo dado desde el arranque con mas de 4 pasos por segundo no se suma', () {
      final a = advance(null, reading(5000, eight, bootElapsed));
      final b = advance(a, reading(20000, eight + 2 * _hour, _minute, boot: 8));
      expect(b.steps, 0);
      expect(b.counter, 20000);
    });
  });

  group('reloj y zona', () {
    test('cambio de zona horaria: corta el tramo aunque el dia se llame igual', () {
      final a = advance(null, reading(5000, eight, bootElapsed));
      tz = -240;
      final b = advance(a, reading(6000, eight + _hour, bootElapsed + _hour));
      expect(b.day, '2026-11-20');
      expect(b.offsetMinutes, -240);
      expect(b.steps, 0);
      expect(b.fromMinute, 8 * 60);
    });

    test('reloj atrasado sin reinicio (hora automatica): sigue el tramo y conserva lo sumado', () {
      final a = advance(null, reading(5000, eight, bootElapsed));
      final b = advance(a, reading(5100, eight + _hour, bootElapsed + _hour));
      final c = advance(b, reading(5600, eight + _hour - 5000, bootElapsed + _hour + 5 * _minute));
      expect(c.steps, 600);
      expect(c.fromMinute, 8 * 60);
      expect(c.wallMs, eight + _hour - 5000);
      final d = advance(c, reading(5700, eight + _hour + 10 * _minute, bootElapsed + _hour + 15 * _minute));
      expect(d.steps, 700);
    });

    test(
      'reloj atrasado sin reinicio con un salto imposible: no suma ese salto pero no pierde lo anterior',
      () {
        final a = advance(null, reading(5000, eight, bootElapsed));
        final b = advance(a, reading(5100, eight + _hour, bootElapsed + _hour));
        final c = advance(b, reading(9000, eight + 30 * _minute, bootElapsed + _hour + _minute));
        expect(c.steps, 100);
      },
    );

    test(
      'reloj atrasado con reinicio el mismo dia: conserva lo sumado y no suma lo de antes del arranque',
      () {
        final a = advance(null, reading(5000, eight, bootElapsed));
        final b = advance(a, reading(5100, eight + _hour, bootElapsed + _hour));
        final c = advance(b, reading(300, eight + 30 * _minute, 20 * _minute, boot: 8));
        expect(c.day, '2026-11-20');
        expect(c.steps, 100);
        expect(c.fromMinute, 8 * 60);
        expect(c.bootCount, 8);
        final d = advance(c, reading(400, eight + 40 * _minute, 30 * _minute, boot: 8));
        expect(d.steps, 200);
        expect(d.fromMinute, 8 * 60);
      },
    );

    test('la hora automatica vuelve unos segundos al dia anterior: sigue el tramo del dia del ancla', () {
      final a = advance(null, reading(5000, local(11, 20, 23, 50), bootElapsed));
      final b = advance(a, reading(5050, local(11, 21, 0) + 3000, bootElapsed + 10 * _minute + 3000));
      expect(b.day, '2026-11-21');
      expect(b.fromMinute, isNull);
      final c = advance(b, reading(5060, local(11, 21, 0) - 2000, bootElapsed + 10 * _minute + 13000));
      expect(c.day, '2026-11-21');
      expect(c.steps, 10);
      expect(c.fromMinute, isNull);
      final d = advance(c, reading(5100, local(11, 21, 0, 1), bootElapsed + 11 * _minute + 13000));
      expect(d.day, '2026-11-21');
      expect(d.steps, 50);
      expect(d.fromMinute, isNull);
    });

    test(
      'varios atrasos chicos seguidos no estiran el tramo: pasados 5 min antes de la medianoche, corta',
      () {
        final a = advance(null, reading(5000, local(11, 21, 0, 0) + 30000, bootElapsed));
        final b = advance(a, reading(5010, local(11, 20, 23, 58), bootElapsed + _minute));
        expect(b.day, '2026-11-21');
        final c = advance(b, reading(5020, local(11, 20, 23, 55), bootElapsed + 2 * _minute));
        expect(c.day, '2026-11-21');
        expect(c.steps, 20);
        final d = advance(c, reading(5030, local(11, 20, 23, 52), bootElapsed + 3 * _minute));
        expect(d.day, '2026-11-20');
        expect(d.steps, 0);
        expect(d.fromMinute, 23 * 60 + 52);
      },
    );

    test('el reloj vuelve mucho al dia anterior: corta el tramo', () {
      final a = advance(null, reading(5000, local(11, 21, 0, 10), bootElapsed));
      final b = advance(a, reading(5100, local(11, 20, 23), bootElapsed + 10 * _minute));
      expect(b.day, '2026-11-20');
      expect(b.steps, 0);
      expect(b.fromMinute, 23 * 60);
    });

    test('el dia vuelve atras con reinicio: corta el tramo', () {
      final a = advance(null, reading(5000, local(11, 21, 0, 1), bootElapsed));
      final b = advance(a, reading(20, local(11, 20, 23, 59), 5 * _minute, boot: 8));
      expect(b.day, '2026-11-20');
      expect(b.steps, 0);
    });
  });

  group('guardado', () {
    test('ida y vuelta por JSON', () {
      final a = advance(null, reading(5000, eight, bootElapsed));
      final b = advance(a, reading(5300, eight + _hour, bootElapsed + _hour));
      final json = b.toJson();
      expect(json.keys, containsAll(['c', 't', 'e', 'b', 'day', 'tz', 'acc', 'f']));
      final back = StepAnchor.fromJson(json)!;
      expect(back.toJson(), json);
    });

    test('sin desde cuando no se guarda f', () {
      final a = advance(null, reading(5000, local(11, 20, 0), bootElapsed));
      expect(a.toJson().containsKey('f'), isFalse);
      expect(StepAnchor.fromJson(a.toJson())!.fromMinute, isNull);
    });

    test('un ancla rota o ajena se descarta', () {
      expect(StepAnchor.fromJson(null), isNull);
      expect(StepAnchor.fromJson('x'), isNull);
      expect(StepAnchor.fromJson({'c': 1}), isNull);
      final good = advance(null, reading(5000, eight, bootElapsed)).toJson();
      expect(StepAnchor.fromJson({...good, 'acc': -1}), isNull);
      expect(StepAnchor.fromJson({...good, 'day': '20-11-2026'}), isNull);
      expect(StepAnchor.fromJson({...good, 'c': 1.5}), isNull);
    });
  });
}
