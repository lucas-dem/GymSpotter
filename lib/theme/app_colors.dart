import 'package:flutter/material.dart';

@immutable
class GymColors extends ThemeExtension<GymColors> {
  const GymColors({
    required this.pageBg,
    required this.bg,
    required this.bgRaised,
    required this.bgRaised2,
    required this.border,
    required this.navBg,
    required this.text,
    required this.textSecondary,
    required this.textTertiary,
    required this.ember,
    required this.emberDeep,
    required this.onEmber,
    required this.emberSoft,
    required this.emberShadow,
    required this.accent,
    required this.accentSoft,
    required this.brass,
    required this.sage,
    required this.sageSoft,
    required this.mutedFill,
    required this.heatEmpty,
    required this.info,
    required this.warn,
    required this.danger,
  });

  final Color pageBg;
  final Color bg;
  final Color bgRaised;
  final Color bgRaised2;
  final Color border;
  final Color navBg;
  final Color text;
  final Color textSecondary;
  final Color textTertiary;
  final Color ember;
  final Color emberDeep;
  final Color onEmber;
  final Color emberSoft;
  final Color emberShadow;
  final Color accent;
  final Color accentSoft;
  final Color brass;
  final Color sage;
  final Color sageSoft;
  final Color mutedFill;
  final Color heatEmpty;
  final Color info;
  final Color warn;
  final Color danger;

  static const dark = GymColors(
    pageBg: Color(0xFF08090A),
    bg: Color(0xFF0A0B0C),
    bgRaised: Color(0xFF17191C),
    bgRaised2: Color(0xFF24272B),
    border: Color(0xFF41464D),
    navBg: Color(0xF2101214),
    text: Color(0xFFF5F6F7),
    textSecondary: Color(0xFFA5AAB0),
    textTertiary: Color(0xFF676C73),
    ember: Color(0xFFB00020),
    emberDeep: Color(0xFF760012),
    onEmber: Color(0xFFFFFFFF),
    emberSoft: Color(0x29E20D2F),
    emberShadow: Color(0x669E001B),
    accent: Color(0xFFE20D2F),
    accentSoft: Color(0x33E20D2F),
    brass: Color(0xFFC9CDD2),
    sage: Color(0xFF9299A1),
    sageSoft: Color(0x299299A1),
    mutedFill: Color(0xFF25282C),
    heatEmpty: Color(0xFF202327),
    info: Color(0xFF91A7C0),
    warn: Color(0xFFE0B15A),
    danger: Color(0xFFFF3655),
  );

  static const light = GymColors(
    pageBg: Color(0xFFFAF7F4),
    bg: Color(0xFFF7F2EE),
    bgRaised: Color(0xFFFFFFFF),
    bgRaised2: Color(0xFFE9E2DC),
    border: Color(0xFFD7CDC5),
    navBg: Color(0xF2FAF7F4),
    text: Color(0xFF15171A),
    textSecondary: Color(0xFF555B62),
    textTertiary: Color(0xFF7B828A),
    ember: Color(0xFFB00020),
    emberDeep: Color(0xFF760012),
    onEmber: Color(0xFFFFFFFF),
    emberSoft: Color(0x1FE20D2F),
    emberShadow: Color(0x339E001B),
    accent: Color(0xFFB00020),
    accentSoft: Color(0x1FB00020),
    brass: Color(0xFF747B83),
    sage: Color(0xFF69717A),
    sageSoft: Color(0x1F69717A),
    mutedFill: Color(0xFFE5E8EB),
    heatEmpty: Color(0xFFE1E4E7),
    info: Color(0xFF3D6388),
    warn: Color(0xFF9A6A12),
    danger: Color(0xFFC90024),
  );

  @override
  GymColors copyWith({
    Color? pageBg,
    Color? bg,
    Color? bgRaised,
    Color? bgRaised2,
    Color? border,
    Color? navBg,
    Color? text,
    Color? textSecondary,
    Color? textTertiary,
    Color? ember,
    Color? emberDeep,
    Color? onEmber,
    Color? emberSoft,
    Color? emberShadow,
    Color? accent,
    Color? accentSoft,
    Color? brass,
    Color? sage,
    Color? sageSoft,
    Color? mutedFill,
    Color? heatEmpty,
    Color? info,
    Color? warn,
    Color? danger,
  }) {
    return GymColors(
      pageBg: pageBg ?? this.pageBg,
      bg: bg ?? this.bg,
      bgRaised: bgRaised ?? this.bgRaised,
      bgRaised2: bgRaised2 ?? this.bgRaised2,
      border: border ?? this.border,
      navBg: navBg ?? this.navBg,
      text: text ?? this.text,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      ember: ember ?? this.ember,
      emberDeep: emberDeep ?? this.emberDeep,
      onEmber: onEmber ?? this.onEmber,
      emberSoft: emberSoft ?? this.emberSoft,
      emberShadow: emberShadow ?? this.emberShadow,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      brass: brass ?? this.brass,
      sage: sage ?? this.sage,
      sageSoft: sageSoft ?? this.sageSoft,
      mutedFill: mutedFill ?? this.mutedFill,
      heatEmpty: heatEmpty ?? this.heatEmpty,
      info: info ?? this.info,
      warn: warn ?? this.warn,
      danger: danger ?? this.danger,
    );
  }

  @override
  GymColors lerp(GymColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return GymColors(
      pageBg: c(pageBg, other.pageBg),
      bg: c(bg, other.bg),
      bgRaised: c(bgRaised, other.bgRaised),
      bgRaised2: c(bgRaised2, other.bgRaised2),
      border: c(border, other.border),
      navBg: c(navBg, other.navBg),
      text: c(text, other.text),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      ember: c(ember, other.ember),
      emberDeep: c(emberDeep, other.emberDeep),
      onEmber: c(onEmber, other.onEmber),
      emberSoft: c(emberSoft, other.emberSoft),
      emberShadow: c(emberShadow, other.emberShadow),
      accent: c(accent, other.accent),
      accentSoft: c(accentSoft, other.accentSoft),
      brass: c(brass, other.brass),
      sage: c(sage, other.sage),
      sageSoft: c(sageSoft, other.sageSoft),
      mutedFill: c(mutedFill, other.mutedFill),
      heatEmpty: c(heatEmpty, other.heatEmpty),
      info: c(info, other.info),
      warn: c(warn, other.warn),
      danger: c(danger, other.danger),
    );
  }
}

extension GymColorsX on BuildContext {
  GymColors get gc => Theme.of(this).extension<GymColors>()!;
}
