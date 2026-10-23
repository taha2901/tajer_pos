import 'package:flutter/material.dart';

/// Semantic colors beyond the Material scheme.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.danger,
    required this.dangerBg,
    required this.info,
    required this.infoBg,
    required this.border,
    required this.muted,
    required this.subtle,
  });

  final Color success, successBg, warning, warningBg, danger, dangerBg, info, infoBg;

  /// Hairline borders / dividers.
  final Color border;

  /// Secondary text.
  final Color muted;

  /// Very light fill for grouped content.
  final Color subtle;

  static const light = AppPalette(
    success: Color(0xFF12805C),
    successBg: Color(0xFFE6F4EE),
    warning: Color(0xFFB54708),
    warningBg: Color(0xFFFEF3E2),
    danger: Color(0xFFC0362C),
    dangerBg: Color(0xFFFDECEA),
    info: Color(0xFF2E5AAC),
    infoBg: Color(0xFFEAF0FB),
    border: Color(0xFFEBECEE),
    muted: Color(0xFF7A808A),
    subtle: Color(0xFFF4F5F6),
  );

  static const dark = AppPalette(
    success: Color(0xFF4CC38A),
    successBg: Color(0xFF15302A),
    warning: Color(0xFFF5A524),
    warningBg: Color(0xFF3A2A12),
    danger: Color(0xFFFF6B5E),
    dangerBg: Color(0xFF3B1C1A),
    info: Color(0xFF7AA2F7),
    infoBg: Color(0xFF1B2640),
    border: Color(0xFF262B32),
    muted: Color(0xFF959CA6),
    subtle: Color(0xFF1D2128),
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) => t < 0.5 ? this : (other as AppPalette? ?? this);
}

extension ThemeX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}

abstract final class AppTheme {
  static const brand = Color(0xFF1F7A68);
  static const font = 'PlexArabic';

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final isDark = b == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    final scheme = ColorScheme.fromSeed(seedColor: brand, brightness: b).copyWith(
      primary: isDark ? const Color(0xFF5CC2AA) : brand,
      onPrimary: isDark ? const Color(0xFF00201A) : Colors.white,
      surface: isDark ? const Color(0xFF171B21) : Colors.white,
      onSurface: isDark ? const Color(0xFFE8EAED) : const Color(0xFF1B1F24),
      onSurfaceVariant: palette.muted,
      surfaceContainerLowest: isDark ? const Color(0xFF0F1215) : const Color(0xFFF6F7F8),
      surfaceContainerLow: isDark ? const Color(0xFF181E26) : const Color(0xFFF6F7F9),
      surfaceContainer: isDark ? const Color(0xFF1C232C) : const Color(0xFFF1F3F6),
      surfaceContainerHighest: isDark ? const Color(0xFF242C36) : const Color(0xFFE9ECF0),
      outline: palette.border,
      outlineVariant: palette.border,
      error: palette.danger,
    );
    final bg = scheme.surfaceContainerLowest;
    // Soft fill for fields and chips — visible on both the page and white sheets.
    final fill = isDark ? const Color(0xFF23282F) : const Color(0xFFEDEFF1);

    final base = ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      fontFamily: font,
      scaffoldBackgroundColor: bg,
      extensions: [palette],
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
    );

    final t = base.textTheme;
    final text = t.copyWith(
      headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 26, height: 1.3),
      headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 22, height: 1.3),
      titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 19),
      titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 16.5),
      titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w500, fontSize: 14.5),
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 15, height: 1.5),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 14, height: 1.5),
      bodySmall: t.bodySmall?.copyWith(fontSize: 12.5, height: 1.45, color: palette.muted),
      labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 14.5),
      labelMedium: t.labelMedium?.copyWith(fontWeight: FontWeight.w500, fontSize: 12.5),
      labelSmall: t.labelSmall?.copyWith(fontWeight: FontWeight.w500, fontSize: 11.5, letterSpacing: 0),
    );

    final radius = BorderRadius.circular(14);
    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface, fontFamily: font, fontSize: 18),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dividerTheme: DividerThemeData(color: palette.border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: fill,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.primary, width: 1.6)),
        errorBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: palette.danger)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: palette.danger, width: 1.6)),
        labelStyle: TextStyle(color: palette.muted, fontFamily: font),
        hintStyle: TextStyle(color: palette.muted.withValues(alpha: 0.8), fontFamily: font),
        prefixIconColor: palette.muted,
        suffixIconColor: palette.muted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: text.labelLarge?.copyWith(fontFamily: font, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: palette.border, width: 1.2),
          foregroundColor: scheme.onSurface,
          textStyle: text.labelLarge?.copyWith(fontFamily: font),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: text.labelLarge?.copyWith(fontFamily: font)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
        backgroundColor: fill,
        selectedColor: scheme.primary.withValues(alpha: isDark ? 0.25 : 0.1),
        labelStyle: text.labelMedium?.copyWith(fontFamily: font, color: scheme.onSurface),
        secondaryLabelStyle: text.labelMedium?.copyWith(fontFamily: font, color: scheme.primary),
        checkmarkColor: scheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        showCheckmark: false,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: palette.border,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface, fontFamily: font),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        height: 66,
        elevation: 0,
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.10),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelSmall?.copyWith(
            fontFamily: font,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? scheme.primary : palette.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? scheme.primary : palette.muted, size: 24),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 1,
        highlightElevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        extendedTextStyle: text.labelLarge?.copyWith(fontFamily: font),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        iconColor: palette.muted,
        titleTextStyle: text.titleSmall?.copyWith(color: scheme.onSurface, fontFamily: font),
        subtitleTextStyle: text.bodySmall?.copyWith(fontFamily: font),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          side: BorderSide(color: palette.border),
          selectedBackgroundColor: scheme.primary.withValues(alpha: isDark ? 0.25 : 0.1),
          selectedForegroundColor: scheme.primary,
          textStyle: text.labelMedium?.copyWith(fontFamily: font),
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: palette.muted,
        indicatorColor: scheme.primary,
        dividerColor: palette.border,
        labelStyle: text.titleSmall?.copyWith(fontFamily: font),
        unselectedLabelStyle: text.titleSmall?.copyWith(fontFamily: font, fontWeight: FontWeight.w500),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentTextStyle: text.bodyMedium?.copyWith(fontFamily: font, color: isDark ? Colors.black : Colors.white),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.onPrimary : null),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.primary : null),
      ),
    );
  }
}
