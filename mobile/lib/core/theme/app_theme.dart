import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import 'app_colors.dart';

/// Builds the light/dark themes from the shared semantic palette.
///
/// Visual direction: warm paper, ink and restrained champagne gold.
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: c.accentSolid,
      onPrimary: c.accentContrast,
      primaryContainer: c.accentSoft,
      onPrimaryContainer: c.accent,
      secondary: c.accent,
      onSecondary: c.accentContrast,
      secondaryContainer: c.accentSoftSelected,
      onSecondaryContainer: c.textPrimary,
      tertiary: c.heroAccent,
      onTertiary: c.heroBg,
      error: c.dangerText,
      onError: Colors.white,
      errorContainer: c.dangerFill,
      onErrorContainer: c.dangerText,
      surface: c.surface,
      onSurface: c.textPrimary,
      surfaceContainerHighest: c.surfaceAlt,
      onSurfaceVariant: c.textSecondary,
      outline: c.borderCard,
      outlineVariant: c.borderSoft,
      shadow: const Color(0xFF231E14),
      scrim: c.overlayScrim,
      inverseSurface: c.heroBg,
      onInverseSurface: c.heroText,
      inversePrimary: c.heroAccent,
    );

    final TextTheme textTheme = TextTheme(
      displaySmall: TextStyle(
        fontSize: 30,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: c.textTitle,
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: c.textTitle,
      ),
      headlineSmall: TextStyle(
        fontSize: 21,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: c.textTitle,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: c.textTitle,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: c.textTitle,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.55,
        color: c.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.5,
        color: c.textPrimary,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        height: 1.45,
        color: c.textMuted,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        height: 1.3,
        color: c.textMuted,
      ),
      labelSmall: TextStyle(
        fontSize: 10,
        height: 1.3,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w500,
        color: c.textMuted,
      ),
    );

    OutlineInputBorder outline(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: color),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.pageBg,
      canvasColor: c.pageBg,
      dividerColor: c.divider,
      splashFactory: InkRipple.splashFactory,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[
        c,
        GptMarkdownThemeData(brightness: brightness),
      ],
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.textTitle,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleMedium,
      ),
      dividerTheme: DividerThemeData(color: c.divider, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.inputBg,
        hintStyle: TextStyle(color: c.textFaint, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: outline(c.borderCard),
        enabledBorder: outline(c.borderCard),
        focusedBorder: outline(c.accentOutline),
        errorBorder: outline(c.dangerText),
        focusedErrorBorder: outline(c.dangerText),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.accentSolid,
          foregroundColor: c.accentContrast,
          disabledBackgroundColor: c.fill,
          disabledForegroundColor: c.textFaint,
          elevation: 0,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textSecondary,
          backgroundColor: c.surface,
          side: BorderSide(color: c.borderCard),
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconTheme: IconThemeData(color: c.textSecondary, size: 22),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.accentSolid,
        foregroundColor: c.accentContrast,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        barrierColor: c.overlayScrim,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titleTextStyle: textTheme.titleMedium,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: c.overlayScrim,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: true,
        dragHandleColor: c.borderCard,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.heroBg,
        contentTextStyle: TextStyle(color: c.heroText, fontSize: 13),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return c.accentContrast;
          }
          return c.surface;
        }),
        trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.selected)) {
            return c.accentSolid;
          }
          return c.fill;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> states) =>
              states.contains(WidgetState.selected) ? c.accentSolid : c.borderCard,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.accent,
        textColor: c.textPrimary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.fill,
        circularTrackColor: c.fill,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: c.surface,
        scrimColor: c.overlayScrim,
      ),
    );
  }
}
