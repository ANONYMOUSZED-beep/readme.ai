import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Global visual language for ReadMe.ai.
///
/// Headings use the bundled [AppFonts.serif] for an editorial, book-like feel;
/// interface text (body, labels, buttons) stays in the platform sans for
/// legibility at small sizes.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final canvas = isDark ? AppColors.night : AppColors.paper;
    final raised = isDark ? AppColors.nightRaised : AppColors.paperRaised;
    final sunken = isDark ? AppColors.nightSunken : AppColors.paperSunken;
    final ink = isDark ? AppColors.nightInk : AppColors.ink;
    final inkSoft = isDark ? AppColors.nightInkSoft : AppColors.inkSoft;
    final hairline = isDark ? AppColors.nightHairline : AppColors.hairline;
    final insight = isDark ? AppColors.insightDark : AppColors.insight;

    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.insight,
          brightness: brightness,
        ).copyWith(
          primary: ink,
          onPrimary: canvas,
          primaryContainer: sunken,
          onPrimaryContainer: ink,
          secondary: isDark ? const Color(0xFFE59A73) : AppColors.clay,
          onSecondary: canvas,
          secondaryContainer: isDark
              ? const Color(0xFF3F2A1E)
              : const Color(0xFFF6E3D3),
          onSecondaryContainer: isDark
              ? const Color(0xFFF6DCCB)
              : const Color(0xFF5A2A14),
          tertiary: insight,
          onTertiary: isDark ? AppColors.night : Colors.white,
          tertiaryContainer: isDark
              ? AppColors.insightSoftDark
              : AppColors.insightSoft,
          onTertiaryContainer: isDark
              ? const Color(0xFFE2E5FF)
              : const Color(0xFF1D2477),
          surface: raised,
          onSurface: ink,
          onSurfaceVariant: inkSoft,
          surfaceContainerLowest: raised,
          surfaceContainerLow: raised,
          surfaceContainer: canvas,
          surfaceContainerHigh: sunken,
          surfaceContainerHighest: sunken,
          outline: isDark ? const Color(0xFF5E5A53) : const Color(0xFFBDB6A8),
          outlineVariant: hairline,
          inverseSurface: ink,
          onInverseSurface: canvas,
        );

    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final sans = base.textTheme.apply(bodyColor: ink, displayColor: ink);
    TextStyle? serif(
      TextStyle? style, {
      required double size,
      double spacing = -0.3,
      double height = 1.18,
      FontWeight weight = FontWeight.w600,
    }) => style?.copyWith(
      fontFamily: AppFonts.serif,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: spacing,
      height: height,
    );

    final textTheme = sans.copyWith(
      displayLarge: serif(
        sans.displayLarge,
        size: 56,
        spacing: -1.4,
        height: 1.04,
      ),
      displayMedium: serif(
        sans.displayMedium,
        size: 44,
        spacing: -1.1,
        height: 1.06,
      ),
      displaySmall: serif(
        sans.displaySmall,
        size: 36,
        spacing: -0.9,
        height: 1.08,
      ),
      headlineLarge: serif(
        sans.headlineLarge,
        size: 32,
        spacing: -0.7,
        height: 1.12,
      ),
      headlineMedium: serif(sans.headlineMedium, size: 28, spacing: -0.5),
      headlineSmall: serif(sans.headlineSmall, size: 23, spacing: -0.3),
      titleLarge: serif(sans.titleLarge, size: 20, spacing: -0.2),
      titleMedium: sans.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      titleSmall: sans.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: sans.bodyLarge?.copyWith(height: 1.55),
      bodyMedium: sans.bodyMedium?.copyWith(height: 1.5),
      bodySmall: sans.bodySmall?.copyWith(height: 1.45, color: inkSoft),
      labelLarge: sans.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelMedium: sans.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: sans.labelSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    );

    const pill = StadiumBorder();

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: raised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: hairline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          shape: pill,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          foregroundColor: ink,
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
          shape: pill,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ink,
          shape: pill,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          foregroundColor: ink,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: sunken,
        hintStyle: TextStyle(color: inkSoft),
        prefixIconColor: inkSoft,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: ink.withValues(alpha: 0.5)),
        ),
      ),
      chipTheme: ChipThemeData(
        side: BorderSide.none,
        backgroundColor: sunken,
        shape: const StadiumBorder(),
        labelStyle: textTheme.labelMedium,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: sunken,
          foregroundColor: inkSoft,
          selectedBackgroundColor: raised,
          selectedForegroundColor: ink,
          side: BorderSide(color: hairline),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? canvas : inkSoft,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? ink : sunken,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: inkSoft,
        titleTextStyle: textTheme.titleMedium,
        subtitleTextStyle: textTheme.bodySmall,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: raised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: textTheme.headlineSmall,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: raised,
        modalBackgroundColor: raised,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: scheme.outline.withValues(alpha: 0.5),
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 2,
        highlightElevation: 0,
        backgroundColor: ink,
        foregroundColor: canvas,
        extendedTextStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        shape: pill,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        // The snackbar is inverted, so its action uses the opposite insight.
        actionTextColor: isDark ? AppColors.insight : AppColors.insightDark,
        contentTextStyle: TextStyle(color: canvas, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: ink,
        linearTrackColor: sunken,
        circularTrackColor: Colors.transparent,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: insight,
        selectionColor: insight.withValues(alpha: isDark ? 0.34 : 0.22),
        selectionHandleColor: insight,
      ),
      dividerTheme: DividerThemeData(color: hairline, space: 1, thickness: 1),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(color: canvas, fontSize: 12),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}
