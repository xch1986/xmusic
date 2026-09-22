import 'package:flutter/material.dart';

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

  static const Color _lightSurface = Color(0xFFF5F2EA); // 暖白象牙
  static const Color _lightPrimary = Color(0xFF4452C7); // 精炼靛蓝
  static const Color _lightOnSurface = Color(0xFF1C2130);

  static const Color _darkSurface = Color(0xFF0E121B); // 深蓝炭黑
  static const Color _darkPrimary = Color(0xFF93A0FF); // 亮靛蓝
  static const Color _darkOnSurface = Color(0xFFE8EBF2);

  // 背景通透度：浅色稍实（暖白底保证可读），深色保持玻璃但更沉稳（避免发灰发脏）。
  static const double _lightBgAlpha = 0.70;
  static const double _darkBgAlpha = 0.42;
  // 面板/卡片/弹层的不透明度下限（雾面玻璃，透明时文字仍可读）。
  static const double _lightPanelAlpha = 0.94;
  static const double _lightSheetAlpha = 0.97;
  static const double _darkPanelAlpha = 0.88;
  static const double _darkSheetAlpha = 0.94;

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
    final scheme = ColorScheme.light(
      primary: _lightPrimary,
      onPrimary: Colors.white,
      secondary: Color(0xFF6E7BD9),
      onSecondary: Colors.white,
      error: Color(0xFFB3261E),
      onError: Colors.white,
      surface: surfaceColor,
      onSurface: onSurfaceColor,
      surfaceContainerLowest: Color(0xFFFFFDF7),
      surfaceContainerLow: Color(0xFFFBF8F0),
      surfaceContainer: Color(0xFFF3EFE4),
      surfaceContainerHigh: Color(0xFFEAE5D7),
      surfaceContainerHighest: Color(0xFFE0DAC9),
      outline: Color(0xFF7A746A),
      outlineVariant: Color(0xFFD5CFC0),
      shadow: Color(0xFF2A2A33),
      scrim: Color(0xFF141414),
      inverseSurface: Color(0xFF32363F),
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
        backgroundColor: panelLow.withValues(alpha: 0.32),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: onSurface,
        iconTheme: IconThemeData(color: onSurface),
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          shadows: [Shadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 8)],
        ),
      ),
      // ---- 导航栏：雾面玻璃 ----
      navigationBarTheme: NavigationBarThemeData(
        // 参照车机桌面导航栏：高透明浮在壁纸上，靠图标阴影保证可读
        backgroundColor: panelLow.withValues(alpha: 0.32),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 62,
        indicatorColor: primary.withValues(alpha: 0.16),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 12,
            color: onSurface,
            fontWeight: FontWeight.w600,
            shadows: [Shadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 6)],
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final sel = states.contains(WidgetState.selected);
          return IconThemeData(
            color: sel ? primary : onSurface.withValues(alpha: 0.65),
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
        ),
      ),
      // ---- 列表/条目 ----
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        iconColor: onSurface.withValues(alpha: 0.75),
        textColor: onSurface,
        titleTextStyle: TextStyle(color: onSurface, fontSize: 15),
        subtitleTextStyle: TextStyle(
          color: onSurface.withValues(alpha: 0.6),
          fontSize: 12.5,
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
      // ---- 全局文字 ----
      textTheme: const TextTheme().apply(
        bodyColor: onSurface,
        displayColor: onSurface,
      ),
    );
  }
}
