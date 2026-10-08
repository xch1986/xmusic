import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'settings.dart';

/// 高级浅/深主题：透明加深、雾面玻璃、车机友好。
///
/// 设计要点：
/// - 移除可调“玻璃通透度”滑块：通透度由主题内置（浅色更透、深色更沉），
///   设置里不再有重复的拖动条。
/// - 背景色带 alpha：车窗桌面壁纸透出（配合 Android 透明窗口），
///   文字所在的面板/卡片设有不透明度下限，保证任何背景下可读。
/// - 跟随车机深浅：ThemeMode.system（设置-主题模式-跟随系统）。
class AppTheme {
  const AppTheme._();

  static const Color _lightSurface = Color(0xFFFFFFFF); // 纯白
  static const Color _lightPrimary = Color(0xFF4452C7); // 精炼靛蓝
  static const Color _lightOnSurface = Color(0xFF1C2130);

  static const Color _darkSurface = Color(0xFF0E121B); // 深蓝炭黑
  static const Color _darkPrimary = Color(0xFF93A0FF); // 亮靛蓝
  static const Color _darkOnSurface = Color(0xFFE8EBF2);

  // 背景通透度（玻璃拟态）：主背景保持透明让车机壁纸透出。
  // 文字可读性不靠把背景改实（用户要的是透明+玻璃），而是靠 onSurface 文字的描边阴影兜底
  //（见 _build 里的 tShadows：白字配黑影、黑字配白影，任意壁纸下都可读）。
  static const double _lightBgAlpha = 0.92;
  static const double _darkBgAlpha = 0.55;
  // 面板/卡片/弹层的不透明度下限（雾面玻璃，透明时文字仍可读）。
  static const double _lightPanelAlpha = 0.95;
  static const double _lightSheetAlpha = 0.97;
  static const double _darkPanelAlpha = 0.90;
  static const double _darkSheetAlpha = 0.95;

  static Color withAlpha255(Color c, double alpha) =>
      c.withValues(alpha: alpha.clamp(0.0, 1.0));

  /// 玻璃高光：卡片/面板顶部的 1px 反光渐变（浅色下白、深色下微白），
  /// 模拟毛玻璃边缘反光，替代被车机禁用的 BackdropFilter。
  static BoxDecoration glassHighlight(ColorScheme scheme, {double strength = 1.0}) {
    final isDark = scheme.brightness == Brightness.dark;
    final top = Colors.white.withValues(alpha: (isDark ? 0.07 : 0.18) * strength);
    final bottom = Colors.transparent;
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [top, bottom],
        stops: const [0.0, 0.35],
      ),
    );
  }

  static ThemeData light(AppSettings settings) {
    Color surfaceColor = _lightSurface;
    Color onSurfaceColor = _lightOnSurface;
    if (settings.bgColor != 0) {
      surfaceColor = Color(settings.bgColor);
      // Auto-compute text color based on background luminance
      final lum = surfaceColor.computeLuminance();
      onSurfaceColor = lum > 0.5 ? const Color(0xFF1C2130) : const Color(0xFFE8EBF2);
    }
    final scheme = ColorScheme.light(/* light */
      primary: _lightPrimary,
      onPrimary: Colors.white,
      secondary: Color(0xFF6E7BD9),
      onSecondary: Colors.white,
      error: Color(0xFFB3261E),
      onError: Colors.white,
      surface: surfaceColor,
      onSurface: onSurfaceColor,
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFFAFAFA),
      surfaceContainer: Color(0xFFF5F5F5),
      surfaceContainerHigh: Color(0xFFEEEEEE),
      surfaceContainerHighest: Color(0xFFE8E8E8),
      outline: Color(0xFF7A746A),
      outlineVariant: Color(0xFFD5CFC0),
      shadow: Color(0xFF2A2A33),
      scrim: Color(0xFF141414),
      inverseSurface: Color(0xFF222222),
      onInverseSurface: Color(0xFFF2F0EB),
      inversePrimary: Color(0xFFBEC4FF),
      surfaceTint: _lightPrimary,
    );
    return _build(
      scheme,
      _lightBgAlpha,
      _lightPanelAlpha,
      _lightSheetAlpha,
      surfaceColor,
      _lightPrimary,
      onSurfaceColor,
    );
  }

  static ThemeData dark(AppSettings settings) {
    Color surfaceColor = _darkSurface;
    Color onSurfaceColor = _darkOnSurface;
    if (settings.bgColor != 0) {
      surfaceColor = Color(settings.bgColor);
      final lum = surfaceColor.computeLuminance();
      onSurfaceColor = lum > 0.5 ? const Color(0xFF1C2130) : const Color(0xFFE8EBF2);
    }
    final scheme = ColorScheme.dark(
      primary: _darkPrimary,
      onPrimary: Color(0xFF10142E),
      secondary: Color(0xFF7A86E8),
      onSecondary: Color(0xFF10142E),
      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      surface: surfaceColor,
      onSurface: onSurfaceColor,
      surfaceContainerLowest: Color(0xFF0A0D14),
      surfaceContainerLow: Color(0xFF121722),
      surfaceContainer: Color(0xFF171C29),
      surfaceContainerHigh: Color(0xFF1D2333),
      surfaceContainerHighest: Color(0xFF252C40),
      outline: Color(0xFF8A90A2),
      outlineVariant: Color(0xFF3A4155),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFE8EBF2),
      onInverseSurface: Color(0xFF1C2130),
      inversePrimary: Color(0xFF4452C7),
      surfaceTint: _darkPrimary,
    );
    return _build(
      scheme,
      _darkBgAlpha,
      _darkPanelAlpha,
      _darkSheetAlpha,
      surfaceColor,
      _darkPrimary,
      onSurfaceColor,
    );
  }

  static ThemeData _build(
    ColorScheme scheme,
    double bgAlpha,
    double panelAlpha,
    double sheetAlpha,
    Color surface,
    Color primary,
    Color onSurface,
  ) {
    // 背景：透明加深。文字所在组件统一用不透明度下限。
    final scaffoldBg = withAlpha255(surface, bgAlpha);
    final panel = withAlpha255(surface, panelAlpha);
    final sheet = withAlpha255(surface, sheetAlpha);
    final panelLow = withAlpha255(surface, panelAlpha - 0.08);
    // 卡片：比面板再透一档（壁纸透出），配合柔和投影=车机桌面卡片质感
    final card = withAlpha255(surface, (panelAlpha - 0.06).clamp(0.4, 0.92));
    final border = scheme.outlineVariant.withValues(alpha: 0.65);

    // [xmusic] 2026-09-27 白字可读性：透明背景+浅色字时，靠文字描边阴影兜底（车机玻璃标准做法）。
    // 阴影颜色随 onSurface 亮度自动取反——白字配黑影、黑字配白影，任意壁纸亮度下都可读。
    final lightText = onSurface.computeLuminance() > 0.5;
    final shColor = lightText ? Colors.black : Colors.white;
    final tShadows = <Shadow>[
      Shadow(color: shColor.withValues(alpha: 0.45), blurRadius: 8, offset: const Offset(0, 2)),
      Shadow(color: shColor.withValues(alpha: 0.30), blurRadius: 16, offset: Offset.zero),
    ];

    final base = ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffoldBg,
      canvasColor: panel,
      cardColor: panel,
      dialogBackgroundColor: sheet,
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: sheet,
        modalBackgroundColor: sheet,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dividerColor: scheme.outlineVariant.withValues(alpha: 0.4),
    );

    return base.copyWith(
      // ---- AppBar：玻璃透明条（顶部高光边，模拟毛玻璃边缘反光） ----
      appBarTheme: AppBarTheme(
        // [xmusic] 2026-09-28 全 App 封面玻璃：AppBar/状态栏区域透明，让封面图片背景透上来；
        // 文字可读靠全局描边阴影（tShadows）兜底，不再用半透明底色遮封面。
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 52,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: scheme.brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: scheme.brightness == Brightness.dark
              ? Brightness.dark
              : Brightness.light,
        ),
        centerTitle: false,
        foregroundColor: onSurface,
        iconTheme: IconThemeData(color: onSurface),
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          shadows: tShadows,
        ),
      ),
      // ---- 导航栏：雾面玻璃 ----
      navigationBarTheme: NavigationBarThemeData(
        // 0.32→0.62：导航标签白字可读
        backgroundColor: panelLow.withValues(alpha: 0.62),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 62,
        indicatorColor: primary.withValues(alpha: 0.16),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 12,
            color: onSurface,
            fontWeight: FontWeight.w600,
            shadows: tShadows,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final sel = states.contains(WidgetState.selected);
          return IconThemeData(
            color: sel ? primary : onSurface,
          );
        }),
      ),
      // ---- 卡片/面板：雾面玻璃 + 细描边 + 柔和投影（车机桌面卡片质感） ----
      cardTheme: CardThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shadowColor: scheme.shadow.withValues(alpha: 0.30),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: border, width: 0.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: sheet,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          shadows: tShadows,
        ),
      ),
      // ---- 列表/条目 ----
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        iconColor: onSurface,
        textColor: onSurface,
        titleTextStyle: TextStyle(color: onSurface, fontSize: 15, shadows: tShadows),
        subtitleTextStyle: TextStyle(
          color: onSurface.withValues(alpha: 0.7),
          fontSize: 12.5,
          shadows: tShadows,
        ),
      ),
      // ---- 按钮：大、圆润、车机友好 ----
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 46)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          textStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: scheme.onPrimary),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 46)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          backgroundColor: WidgetStatePropertyAll(panel),
          foregroundColor: WidgetStatePropertyAll(primary),
          elevation: const WidgetStatePropertyAll(0),
          side: WidgetStatePropertyAll(BorderSide(color: border)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 42)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          iconSize: const WidgetStatePropertyAll(26),
          minimumSize: const WidgetStatePropertyAll(Size(46, 46)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          foregroundColor: WidgetStatePropertyAll(onSurface),
        ),
      ),
      // ---- 输入框/开关/滑块/分段 ----
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.68),
        labelStyle: TextStyle(color: onSurface.withValues(alpha: 0.72)),
        hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.52)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? scheme.onPrimary : onSurface.withValues(alpha: 0.7)),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? primary : scheme.surfaceContainerHighest),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: primary,
        overlayColor: primary.withValues(alpha: 0.15),
        trackHeight: 4,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected) ? primary : onSurface.withValues(alpha: 0.65)),
          backgroundColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? primary.withValues(alpha: 0.14)
                  : Colors.transparent),
          side: WidgetStatePropertyAll(BorderSide(color: border)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: onSurface.withValues(alpha: 0.55),
        indicatorColor: primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: sheet,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: TextStyle(color: onSurface, fontSize: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      // ---- 全局文字（全部加描边阴影：白字在透明玻璃/任意壁纸下都可读） ----
      textTheme: _shadowedTextTheme(onSurface, tShadows),
    );
  }

  /// 给全部文字样式加描边阴影（尺寸/字重沿用 Material 默认，仅叠加 color+shadows）。
  static TextTheme _shadowedTextTheme(Color onSurface, List<Shadow> shadows) {
    TextStyle st(double size, FontWeight w) => TextStyle(
          color: onSurface,
          fontSize: size,
          fontWeight: w,
          shadows: shadows,
        );
    return const TextTheme().apply(
      bodyColor: onSurface,
      displayColor: onSurface,
    ).copyWith(
      displayLarge: st(57, FontWeight.w300),
      displayMedium: st(45, FontWeight.w400),
      displaySmall: st(36, FontWeight.w400),
      headlineLarge: st(32, FontWeight.w700),
      headlineMedium: st(28, FontWeight.w700),
      headlineSmall: st(24, FontWeight.w600),
      titleLarge: st(22, FontWeight.w600),
      titleMedium: st(16, FontWeight.w600),
      titleSmall: st(14, FontWeight.w600),
      bodyLarge: st(16, FontWeight.w400),
      bodyMedium: st(14, FontWeight.w400),
      bodySmall: st(12, FontWeight.w400),
      labelLarge: st(14, FontWeight.w600),
      labelMedium: st(12, FontWeight.w500),
      labelSmall: st(11, FontWeight.w500),
    );
  }
}
