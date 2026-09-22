import 'package:flutter/material.dart';
import 'settings.dart';

/// 高级主题：浅色 / 深色 + 玻璃通透。
/// 目标：车机可用（高透明、高对比、跟随系统深浅）、质感高级。
/// 通透度语义：glassOpacity = 1 完全不透明；= 0 完全透明（透出系统壁纸/桌面）。
/// 卡片/弹层/抽屉设置最低不透明度下限，保证高透明时文字依然可读（雾面玻璃）。
class AppTheme {
  /// 主色：精炼靛蓝（替代原亮蓝，更沉稳高级）
  static const Color accent = Color(0xFF4A6CF7);

  static ThemeData light(AppSettings s) => _build(s, Brightness.light);
  static ThemeData dark(AppSettings s) => _build(s, Brightness.dark);

  static Color _withAlpha(Color c, int alpha) {
    final argb = c.toARGB32();
    return Color((alpha << 24) | (argb & 0x00FFFFFF));
  }

  // ---- 浅色色板：暖白象牙 + 精炼靛蓝 ----
  static ColorScheme _lightScheme() {
    return const ColorScheme.light(
      primary: Color(0xFF4452C7),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFE0E2FF),
      onPrimaryContainer: Color(0xFF101458),
      secondary: Color(0xFF5A6077),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFE0E3F4),
      onSecondaryContainer: Color(0xFF171D31),
      tertiary: Color(0xFF9A5B33),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFFFDCC4),
      onTertiaryContainer: Color(0xFF351B04),
      error: Color(0xFFBA1A1A),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF1B1E23),
      surfaceDim: Color(0xFFDEDCD6),
      surfaceBright: Color(0xFFFFFFFF),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFFAF8F4),
      surfaceContainer: Color(0xFFF3F1EC),
      surfaceContainerHigh: Color(0xFFEDEBE5),
      surfaceContainerHighest: Color(0xFFE7E5DF),
      onSurfaceVariant: Color(0xFF636874),
      outline: Color(0xFFD8D6CF),
      outlineVariant: Color(0xFFE9E7E1),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF31363D),
      onInverseSurface: Color(0xFFF0F0F4),
      inversePrimary: Color(0xFFBFC3FF),
      surfaceTint: Color(0xFF4452C7),
    );
  }

  // ---- 深色色板：深蓝炭黑 + 亮靛蓝 ----
  static ColorScheme _darkScheme() {
    return const ColorScheme.dark(
      primary: Color(0xFF9DB0FF),
      onPrimary: Color(0xFF16205C),
      primaryContainer: Color(0xFF2A3763),
      onPrimaryContainer: Color(0xFFDDE3FF),
      secondary: Color(0xFFB4BAC9),
      onSecondary: Color(0xFF272D40),
      secondaryContainer: Color(0xFF3A4157),
      onSecondaryContainer: Color(0xFFD8DCF0),
      tertiary: Color(0xFFE2A576),
      onTertiary: Color(0xFF45270D),
      tertiaryContainer: Color(0xFF663C1C),
      onTertiaryContainer: Color(0xFFFFDCC4),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),
      surface: Color(0xFF12161F),
      onSurface: Color(0xFFE7E9EF),
      surfaceDim: Color(0xFF12161F),
      surfaceBright: Color(0xFF383D48),
      surfaceContainerLowest: Color(0xFF0D1017),
      surfaceContainerLow: Color(0xFF1A1F2A),
      surfaceContainer: Color(0xFF1E2430),
      surfaceContainerHigh: Color(0xFF292F3C),
      surfaceContainerHighest: Color(0xFF343A48),
      onSurfaceVariant: Color(0xFFA0A7B5),
      outline: Color(0xFF4A5262),
      outlineVariant: Color(0xFF262D3A),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFE7E9EF),
      onInverseSurface: Color(0xFF31363D),
      inversePrimary: Color(0xFF4452C7),
      surfaceTint: Color(0xFF9DB0FF),
    );
  }

  static ThemeData _build(AppSettings s, Brightness b) {
    final dark = b == Brightness.dark;
    final op = s.glassOpacity.clamp(0.0, 1.0);
    final int a = (op * 255).round();
    final custom = s.bgColor;

    final scheme = dark ? _darkScheme() : _lightScheme();

    // 背景：自定义背景色优先（实心）；否则按通透度叠加 alpha
    final scaffoldBg = custom != 0
        ? Color(custom)
        : _withAlpha(dark ? const Color(0xFF0B0E14) : const Color(0xFFF4F3F0), a);
    // 卡片/面板：比背景亮一档，并设不透明度下限（雾面玻璃）
    final panelAlpha = dark ? 226 : 232;
    final panel = _withAlpha(scheme.surface, a < panelAlpha ? panelAlpha : a);
    // 弹层/抽屉：更实一些，保证内容可读
    final sheetAlpha = dark ? 238 : 244;
    final sheet = _withAlpha(scheme.surface, a < sheetAlpha ? sheetAlpha : a);

    final base = ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _withAlpha(scheme.surfaceContainer, a < 236 ? 236 : a),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: _withAlpha(scheme.primaryContainer, 210),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final sel = states.contains(WidgetState.selected);
          return IconThemeData(
            color: sel ? scheme.primary : scheme.onSurfaceVariant,
            size: 24,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final sel = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
            color: sel ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),
      cardTheme: CardThemeData(
        elevation: dark ? 0 : 1,
        shadowColor: dark ? Colors.transparent : _withAlpha(Colors.black, 14),
        color: panel,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: dark
              ? BorderSide(color: scheme.outlineVariant, width: 1)
              : BorderSide.none,
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12.5,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: sheet,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: sheet,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: sheet,
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: _withAlpha(scheme.outlineVariant, 160),
        thickness: 0.6,
        space: 0.6,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(48, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: panel,
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(48, 46),
          elevation: 0,
          side: BorderSide(color: scheme.outlineVariant, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          minimumSize: const Size(48, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(48, 46),
          side: BorderSide(color: scheme.outline, width: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: scheme.outlineVariant, width: 1),
          ),
          textStyle: WidgetStatePropertyAll(
            const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.surfaceContainerHighest;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _withAlpha(scheme.primary, 120);
          }
          return scheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStatePropertyAll(Colors.transparent),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: _withAlpha(scheme.onSurfaceVariant, 60),
        thumbColor: scheme.primary,
        overlayColor: _withAlpha(scheme.primary, 28),
        trackHeight: 4,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xFF2A3140) : const Color(0xFF2B2F36),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 4,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: sheet,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _withAlpha(scheme.surfaceContainerHighest, 120),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: _withAlpha(scheme.primary, 80),
        selectionHandleColor: scheme.primary,
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
    );
  }
}
