import 'package:intl/intl.dart';

/// Numbers, dates and times written the same way by every export format. Dates need initializeDateFormatting first.
class ExportFormat {
  ExportFormat(this.locale)
      : _dayHeading = DateFormat.yMMMMEEEEd(locale),
        _shortDate = DateFormat.yMMMd(locale),
        _numericDate = DateFormat.yMd(locale),
        decimalComma = NumberFormat.decimalPattern(locale).symbols.DECIMAL_SEP == ',';

  final String locale;
  final bool decimalComma;
  final DateFormat _dayHeading;
  final DateFormat _shortDate;
  final DateFormat _numericDate;
  final Map<int, NumberFormat> _grouped = {};
  final Map<int, NumberFormat> _plain = {};

  String get csvSeparator => decimalComma ? ';' : ',';

  NumberFormat _numbers(int decimals, {required bool grouping}) {
    final cache = grouping ? _grouped : _plain;
    return cache[decimals] ??= () {
      final f = NumberFormat.decimalPattern(locale)
        ..minimumFractionDigits = 0
        ..maximumFractionDigits = decimals;
      if (!grouping) f.turnOffGrouping();
      return f;
    }();
  }

  String number(num v, {int decimals = 1}) => clean(_numbers(decimals, grouping: true).format(v));

  String plainNumber(num v, {int decimals = 1}) => clean(_numbers(decimals, grouping: false).format(v));

  String dayHeading(DateTime d) {
    final s = clean(_dayHeading.format(d));
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }

  String shortDate(DateTime d) => clean(_shortDate.format(d));

  String numericDate(DateTime d) => clean(_numericDate.format(d));

  String clock(int minuteOfDay) =>
      '${(minuteOfDay ~/ 60).toString().padLeft(2, '0')}:${(minuteOfDay % 60).toString().padLeft(2, '0')}';

  String duration(int sec) {
    final s = sec < 0 ? 0 : sec;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final r = (s % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$r' : '$m:$r';
  }

  static final RegExp _invisible = RegExp('[⁠​­‎‏]');

  // The bundled Nunito has no glyph for U+202F, U+2060 or U+200F.
  String clean(String s) => s.replaceAll(_invisible, '').replaceAll(' ', ' ');
}
