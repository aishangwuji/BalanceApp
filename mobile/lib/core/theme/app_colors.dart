import 'package:flutter/material.dart';

/// Semantic color tokens shared by light and dark themes.
///
/// Business Rule: all UI colors come from this palette; widgets must not
/// hardcode hex values except for brand hues and transparent overlays.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.pageBg,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceRow,
    required this.fill,
    required this.inputBg,
    required this.divider,
    required this.borderSoft,
    required this.borderCard,
    required this.textPrimary,
    required this.textTitle,
    required this.textSecondary,
    required this.textMuted,
    required this.textFaint,
    required this.iconMuted,
    required this.accent,
    required this.accentSolid,
    required this.accentContrast,
    required this.accentSoft,
    required this.accentSoftSelected,
    required this.accentOutline,
    required this.iconTile,
    required this.reasoningText,
    required this.reasoningMuted,
    required this.reasoningBar,
    required this.userBubbleText,
    required this.heroBg,
    required this.heroText,
    required this.heroAccent,
    required this.heroMuted,
    required this.dangerText,
    required this.dangerFill,
    required this.statusGood,
    required this.overlayScrim,
  });

  final Color pageBg;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceRow;
  final Color fill;
  final Color inputBg;
  final Color divider;
  final Color borderSoft;
  final Color borderCard;
  final Color textPrimary;
  final Color textTitle;
  final Color textSecondary;
  final Color textMuted;
  final Color textFaint;
  final Color iconMuted;
  final Color accent;
  final Color accentSolid;
  final Color accentContrast;
  final Color accentSoft;
  final Color accentSoftSelected;
  final Color accentOutline;
  final Color iconTile;
  final Color reasoningText;
  final Color reasoningMuted;
  final Color reasoningBar;
  final Color userBubbleText;
  final Color heroBg;
  final Color heroText;
  final Color heroAccent;
  final Color heroMuted;
  final Color dangerText;
  final Color dangerFill;
  final Color statusGood;
  final Color overlayScrim;

  static const AppColors light = AppColors(
    pageBg: Color(0xFFF5F3EE),
    surface: Color(0xFFFFFEFB),
    surfaceAlt: Color(0xFFFAF8F3),
    surfaceRow: Color(0xFFF4F1EA),
    fill: Color(0xFFEEEAE1),
    inputBg: Color(0xFFF8F6F1),
    divider: Color(0xFFEAE6DD),
    borderSoft: Color(0xFFEDE8DE),
    borderCard: Color(0xFFE1DBCF),
    textPrimary: Color(0xFF292822),
    textTitle: Color(0xFF191915),
    textSecondary: Color(0xFF68665D),
    textMuted: Color(0xFF898579),
    textFaint: Color(0xFFA7A395),
    iconMuted: Color(0xFFAAA596),
    accent: Color(0xFF856C4E),
    accentSolid: Color(0xFF29271F),
    accentContrast: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFF0ECE3),
    accentSoftSelected: Color(0xFFF5F0E6),
    accentOutline: Color(0xFFD8C8A9),
    iconTile: Color(0xFFF1EBDD),
    reasoningText: Color(0xFF6D6B62),
    reasoningMuted: Color(0xFF918D80),
    reasoningBar: Color(0xFFD8C7A0),
    userBubbleText: Color(0xFF353127),
    heroBg: Color(0xFF29271F),
    heroText: Color(0xFFF4EDDF),
    heroAccent: Color(0xFFD9BC83),
    heroMuted: Color(0xFFC2BCAD),
    dangerText: Color(0xFFA34F44),
    dangerFill: Color(0xFFF7EAE6),
    statusGood: Color(0xFF667B62),
    overlayScrim: Color(0x660E0D0A),
  );

  static const AppColors dark = AppColors(
    pageBg: Color(0xFF191815),
    surface: Color(0xFF22211D),
    surfaceAlt: Color(0xFF2B2A25),
    surfaceRow: Color(0xFF2B2A25),
    fill: Color(0xFF33312B),
    inputBg: Color(0xFF302F29),
    divider: Color(0xFF393730),
    borderSoft: Color(0xFF393730),
    borderCard: Color(0xFF48453D),
    textPrimary: Color(0xFFE9E4D9),
    textTitle: Color(0xFFF5F0E6),
    textSecondary: Color(0xFFC4BFB3),
    textMuted: Color(0xFFA29D90),
    textFaint: Color(0xFF888477),
    iconMuted: Color(0xFF777267),
    accent: Color(0xFFD2B67D),
    accentSolid: Color(0xFFD2B67D),
    accentContrast: Color(0xFF242119),
    accentSoft: Color(0xFF343127),
    accentSoftSelected: Color(0xFF39352A),
    accentOutline: Color(0xFF62553C),
    iconTile: Color(0xFFE6DDCC),
    reasoningText: Color(0xFFC7C2B6),
    reasoningMuted: Color(0xFF999386),
    reasoningBar: Color(0xFF5A5140),
    userBubbleText: Color(0xFFEAE3D4),
    heroBg: Color(0xFF24231F),
    heroText: Color(0xFFF4EDDF),
    heroAccent: Color(0xFFD9BC83),
    heroMuted: Color(0xFFC2BCAD),
    dangerText: Color(0xFFE28A7F),
    dangerFill: Color(0xFF3A2523),
    statusGood: Color(0xFFA6C39A),
    overlayScrim: Color(0x990A0907),
  );

  @override
  AppColors copyWith({
    Color? pageBg,
    Color? surface,
    Color? surfaceAlt,
    Color? surfaceRow,
    Color? fill,
    Color? inputBg,
    Color? divider,
    Color? borderSoft,
    Color? borderCard,
    Color? textPrimary,
    Color? textTitle,
    Color? textSecondary,
    Color? textMuted,
    Color? textFaint,
    Color? iconMuted,
    Color? accent,
    Color? accentSolid,
    Color? accentContrast,
    Color? accentSoft,
    Color? accentSoftSelected,
    Color? accentOutline,
    Color? iconTile,
    Color? reasoningText,
    Color? reasoningMuted,
    Color? reasoningBar,
    Color? userBubbleText,
    Color? heroBg,
    Color? heroText,
    Color? heroAccent,
    Color? heroMuted,
    Color? dangerText,
    Color? dangerFill,
    Color? statusGood,
    Color? overlayScrim,
  }) {
    return AppColors(
      pageBg: pageBg ?? this.pageBg,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      surfaceRow: surfaceRow ?? this.surfaceRow,
      fill: fill ?? this.fill,
      inputBg: inputBg ?? this.inputBg,
      divider: divider ?? this.divider,
      borderSoft: borderSoft ?? this.borderSoft,
      borderCard: borderCard ?? this.borderCard,
      textPrimary: textPrimary ?? this.textPrimary,
      textTitle: textTitle ?? this.textTitle,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textFaint: textFaint ?? this.textFaint,
      iconMuted: iconMuted ?? this.iconMuted,
      accent: accent ?? this.accent,
      accentSolid: accentSolid ?? this.accentSolid,
      accentContrast: accentContrast ?? this.accentContrast,
      accentSoft: accentSoft ?? this.accentSoft,
      accentSoftSelected: accentSoftSelected ?? this.accentSoftSelected,
      accentOutline: accentOutline ?? this.accentOutline,
      iconTile: iconTile ?? this.iconTile,
      reasoningText: reasoningText ?? this.reasoningText,
      reasoningMuted: reasoningMuted ?? this.reasoningMuted,
      reasoningBar: reasoningBar ?? this.reasoningBar,
      userBubbleText: userBubbleText ?? this.userBubbleText,
      heroBg: heroBg ?? this.heroBg,
      heroText: heroText ?? this.heroText,
      heroAccent: heroAccent ?? this.heroAccent,
      heroMuted: heroMuted ?? this.heroMuted,
      dangerText: dangerText ?? this.dangerText,
      dangerFill: dangerFill ?? this.dangerFill,
      statusGood: statusGood ?? this.statusGood,
      overlayScrim: overlayScrim ?? this.overlayScrim,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) {
      return this;
    }
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return AppColors(
      pageBg: mix(pageBg, other.pageBg),
      surface: mix(surface, other.surface),
      surfaceAlt: mix(surfaceAlt, other.surfaceAlt),
      surfaceRow: mix(surfaceRow, other.surfaceRow),
      fill: mix(fill, other.fill),
      inputBg: mix(inputBg, other.inputBg),
      divider: mix(divider, other.divider),
      borderSoft: mix(borderSoft, other.borderSoft),
      borderCard: mix(borderCard, other.borderCard),
      textPrimary: mix(textPrimary, other.textPrimary),
      textTitle: mix(textTitle, other.textTitle),
      textSecondary: mix(textSecondary, other.textSecondary),
      textMuted: mix(textMuted, other.textMuted),
      textFaint: mix(textFaint, other.textFaint),
      iconMuted: mix(iconMuted, other.iconMuted),
      accent: mix(accent, other.accent),
      accentSolid: mix(accentSolid, other.accentSolid),
      accentContrast: mix(accentContrast, other.accentContrast),
      accentSoft: mix(accentSoft, other.accentSoft),
      accentSoftSelected: mix(accentSoftSelected, other.accentSoftSelected),
      accentOutline: mix(accentOutline, other.accentOutline),
      iconTile: mix(iconTile, other.iconTile),
      reasoningText: mix(reasoningText, other.reasoningText),
      reasoningMuted: mix(reasoningMuted, other.reasoningMuted),
      reasoningBar: mix(reasoningBar, other.reasoningBar),
      userBubbleText: mix(userBubbleText, other.userBubbleText),
      heroBg: mix(heroBg, other.heroBg),
      heroText: mix(heroText, other.heroText),
      heroAccent: mix(heroAccent, other.heroAccent),
      heroMuted: mix(heroMuted, other.heroMuted),
      dangerText: mix(dangerText, other.dangerText),
      dangerFill: mix(dangerFill, other.dangerFill),
      statusGood: mix(statusGood, other.statusGood),
      overlayScrim: mix(overlayScrim, other.overlayScrim),
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;
}
