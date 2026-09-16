import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  /// 当前是否深色模式（main.dart 启动/切换时设置）
  static bool isDark = false;

  // 深浅两套色板
  static const Color _bgLight = Color(0xFFF8F5F0);
  static const Color _bgDark = Color(0xFF121212);
  static const Color _surfaceLight = Color(0xFFF2EDE6);
  static const Color _surfaceDark = Color(0xFF1E1E1E);
  static const Color _cardLight = Color(0xFFFFFFFF);
  static const Color _cardDark = Color(0xFF2A2A2A);
  static const Color _textPrimaryLight = Color(0xFF2B2118);
  static const Color _textPrimaryDark = Color(0xFFEAE2D8);
  static const Color _textSecondaryLight = Color(0xFF7A6E60);
  static const Color _textSecondaryDark = Color(0xFFA89B8C);
  static const Color _textHintLight = Color(0xFFB8AFA4);
  static const Color _textHintDark = Color(0xFF6B655E);
  static const Color _dividerLight = Color(0xFFE5DDD2);
  static const Color _dividerDark = Color(0xFF383838);

  // 主色（两模式同色系）
  static const Color primary = Color(0xFFC9A882);
  static const Color primaryLight = Color(0xFFE8D5C0);
  static const Color primaryDark = Color(0xFFB0906B);
  static const Color primarySoft = Color(0xFFF5EDE2);
  static const Color primarySoftDark = Color(0xFF3A332B);

  static const Color accent1 = Color(0xFFA8C4C9);
  static const Color accent2 = Color(0xFFC9A8B8);
  static const Color accent3 = Color(0xFFA8C9AE);
  static const Color accent4 = Color(0xFFC9B8A8);
  static const Color error = Color(0xFFE57373);
  static const Color success = Color(0xFF81C784);

  // 排行榜名次色
  static const Color goldRank = Color(0xFFE8B34B);
  static const Color silverRank = Color(0xFFB8BFC8);
  static const Color bronzeRank = Color(0xFFC89B6C);

  static Color get background => isDark ? _bgDark : _bgLight;
  static Color get surface => isDark ? _surfaceDark : _surfaceLight;
  static Color get card => isDark ? _cardDark : _cardLight;
  static Color get cardShadow => isDark ? const Color(0x00000000) : const Color(0x1A000000);
  static Color get cardShadowDark => isDark ? const Color(0x00000000) : const Color(0x0D000000);
  static Color get textPrimary => isDark ? _textPrimaryDark : _textPrimaryLight;
  static Color get textSecondary => isDark ? _textSecondaryDark : _textSecondaryLight;
  static Color get textHint => isDark ? _textHintDark : _textHintLight;
  static Color get divider => isDark ? _dividerDark : _dividerLight;
  static Color get primarySoftColor => isDark ? primarySoftDark : primarySoft;
  static Color get border => isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE5DDD2);
}


class AppNeumorphic {
  // 弥散式阴影 - 新拟态风格（深浅色自适应）
  // 浅色：白色高光 + 暗投影；深色：微亮高光 + 纯黑投影
  static Color get _highlight => AppColors.isDark
      ? Colors.white.withValues(alpha: 0.04)
      : Colors.white.withValues(alpha: 0.8);
  static Color get _shadow => AppColors.isDark
      ? Colors.black.withValues(alpha: 0.55)
      : AppColors.cardShadowDark;

  // 缓存：避免每次访问 getter 都创建新的 List<BoxShadow>
  // 主题切换时 AppColors.isDark 会变，因此缓存按当前主题标记
  static int _cachedThemeFlag = -1;
  static late List<BoxShadow> _lightCache;
  static late List<BoxShadow> _softCache;
  static late List<BoxShadow> _flatCache;
  static late List<BoxShadow> _insetCache;

  static List<BoxShadow> _ensure() {
    final flag = AppColors.isDark ? 1 : 0;
    if (_cachedThemeFlag == flag) return _lightCache;
    _cachedThemeFlag = flag;
    final hl = _highlight;
    final sh = _shadow;
    _lightCache = [
      BoxShadow(color: hl, blurRadius: 16, offset: const Offset(-4, -4)),
      BoxShadow(color: sh, blurRadius: 16, offset: const Offset(4, 4)),
    ];
    _softCache = [
      BoxShadow(color: hl, blurRadius: 12, offset: const Offset(-3, -3)),
      BoxShadow(color: sh, blurRadius: 12, offset: const Offset(3, 3)),
    ];
    _flatCache = [
      BoxShadow(color: hl, blurRadius: 8, offset: const Offset(-2, -2)),
      BoxShadow(color: sh, blurRadius: 8, offset: const Offset(2, 2)),
    ];
    _insetCache = [
      BoxShadow(color: sh, blurRadius: 6, offset: const Offset(2, 2)),
      BoxShadow(color: hl, blurRadius: 6, offset: const Offset(-2, -2)),
    ];
    return _lightCache;
  }

  static List<BoxShadow> get light {
    _ensure();
    return _lightCache;
  }

  static List<BoxShadow> get soft {
    _ensure();
    return _softCache;
  }

  static List<BoxShadow> get flat {
    _ensure();
    return _flatCache;
  }

  static List<BoxShadow> get inset {
    _ensure();
    return _insetCache;
  }
}

class AppTheme {
  static ThemeData get lightTheme => _build(Brightness.light);

  static ThemeData get darkTheme => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    // 临时切换全局色板构建对应主题，完成后立即恢复：
    // MaterialApp 会先后求值 light/dark 两个主题，若用构建副作用设置 isDark，
    // 求值顺序会把全局状态残留为最后构建的主题（曾导致浅色模式显示深色）。
    // 恢复后，页面渲染时 isDark 始终等于用户设置（由 main build 显式赋值）。
    final savedIsDark = AppColors.isDark;
    AppColors.isDark = brightness == Brightness.dark;
    try {
      return _buildTheme(brightness);
    } finally {
      AppColors.isDark = savedIsDark;
    }
  }

  static ThemeData _buildTheme(Brightness brightness) {    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.primaryLight,
        onSecondary: AppColors.textPrimary,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: AppColors.background,
      primaryColor: AppColors.primary,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.card,
        indicatorColor: AppColors.primarySoft,
        labelTextStyle: WidgetStateProperty.resolveWith((_) => TextStyle(
          fontSize: 11,
          color: AppColors.textSecondary,
        )),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: AppColors.primary, size: 22);
          }
          return IconThemeData(color: AppColors.textHint, size: 22);
        }),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.card,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textHint,
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        shadowColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.divider,
        thickness: 0.5,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.divider,
        thumbColor: AppColors.card,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6, elevation: 2),
        trackHeight: 3,
        overlayColor: AppColors.primarySoft,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return AppColors.textHint;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primaryLight;
          return AppColors.divider;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        checkColor: WidgetStateProperty.all(Colors.white),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.primary;
          return AppColors.divider;
        }),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      iconTheme: IconThemeData(color: AppColors.textSecondary),
      textTheme: TextTheme(
        headlineLarge: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 24),
        headlineMedium: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 20),
        titleLarge: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 18),
        titleMedium: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w500, fontSize: 16),
        titleSmall: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        bodyLarge: TextStyle(color: AppColors.textPrimary, fontSize: 16),
        bodyMedium: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        bodySmall: TextStyle(color: AppColors.textHint, fontSize: 12),
        labelLarge: TextStyle(color: AppColors.primary, fontSize: 14),
        labelSmall: TextStyle(color: AppColors.textHint, fontSize: 11),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.primary, width: 1),
        ),
        hintStyle: TextStyle(color: AppColors.textHint, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primaryLight,
        labelStyle: TextStyle(color: AppColors.textPrimary, fontSize: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.divider, width: 0.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
        titleTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 15),
        subtitleTextStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textHint,
        indicatorColor: AppColors.primary,
        labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 13),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.divider,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
    );
  }
}
