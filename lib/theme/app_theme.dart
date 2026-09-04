import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Legacy palette kept for feature code that has not migrated yet.
/// New UI should use [Theme.of(context).colorScheme] or [AppTokens].
class AppColors {
  /// Brand accent: matches the indigo chrome of the browser shell.
  static const Color brand = Color(0xFF4353C4);
  static const Color brandStrong = Color(0xFF36449E);
  static const Color primary = brandStrong;
  static const Color accent = brand;
  static const Color danger = Color(0xFFD92D20);
  static const Color success = Color(0xFF168A4A);
  static const Color warn = Color(0xFFB54708);
  static const Color ink = Color(0xFF182230);
  static const Color subText = Color(0xFF667085);
  static const Color bg = Color(0xFFF5F7FB);
  static const Color darkBg = Color(0xFF0E1420);
  static const Color darkSurface = Color(0xFF151D2B);
  static const Color darkSurfaceRaised = Color(0xFF1D2939);
}

/// Product-wide semantic design tokens. Keep geometry and elevation here so
/// components do not grow their own one-off values.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceMuted,
    required this.outline,
    required this.outlineStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.onAccent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.scrim,
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.radiusXl,
    required this.space1,
    required this.space2,
    required this.space3,
    required this.space4,
    required this.space5,
    required this.space6,
    required this.space8,
    required this.shadowSm,
    required this.shadowMd,
    required this.shadowLg,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceMuted;
  final Color outline;
  final Color outlineStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color onAccent;
  final Color success;
  final Color warning;
  final Color danger;
  final Color scrim;
  final double radiusSm;
  final double radiusMd;
  final double radiusLg;
  final double radiusXl;
  final double space1;
  final double space2;
  final double space3;
  final double space4;
  final double space5;
  final double space6;
  final double space8;
  final List<BoxShadow> shadowSm;
  final List<BoxShadow> shadowMd;
  final List<BoxShadow> shadowLg;

  static const AppTokens light = AppTokens(
    canvas: Color(0xFFEEF1F8),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFE7EBF3),
    outline: Color(0xFFDCE2EC),
    outlineStrong: Color(0xFFB8C2D0),
    textPrimary: Color(0xFF182230),
    textSecondary: Color(0xFF667085),
    textDisabled: Color(0xFF98A2B3),
    onAccent: Color(0xFFFFFFFF),
    success: Color(0xFF168A4A),
    warning: Color(0xFFB54708),
    danger: Color(0xFFD92D20),
    scrim: Color(0x520E1420),
    radiusSm: 8,
    radiusMd: 12,
    radiusLg: 16,
    radiusXl: 24,
    space1: 4,
    space2: 8,
    space3: 12,
    space4: 16,
    space5: 20,
    space6: 24,
    space8: 32,
    shadowSm: <BoxShadow>[],
    shadowMd: <BoxShadow>[
      BoxShadow(color: Color(0x140E1420), blurRadius: 12, offset: Offset(0, 4)),
    ],
    shadowLg: <BoxShadow>[
      BoxShadow(
          color: Color(0x240E1420), blurRadius: 28, offset: Offset(0, 12)),
    ],
  );

  static const AppTokens dark = AppTokens(
    canvas: Color(0xFF0E1420),
    surface: Color(0xFF151D2B),
    surfaceRaised: Color(0xFF1D2939),
    surfaceMuted: Color(0xFF243247),
    outline: Color(0xFF344054),
    outlineStrong: Color(0xFF475467),
    textPrimary: Color(0xFFF2F4F7),
    textSecondary: Color(0xFFB8C2D0),
    textDisabled: Color(0xFF667085),
    onAccent: Color(0xFF101828),
    success: Color(0xFF6CE9A6),
    warning: Color(0xFFFDB022),
    danger: Color(0xFFF97066),
    scrim: Color(0x99000000),
    radiusSm: 8,
    radiusMd: 12,
    radiusLg: 16,
    radiusXl: 24,
    space1: 4,
    space2: 8,
    space3: 12,
    space4: 16,
    space5: 20,
    space6: 24,
    space8: 32,
    shadowSm: <BoxShadow>[],
    shadowMd: <BoxShadow>[
      BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4)),
    ],
    shadowLg: <BoxShadow>[
      BoxShadow(
          color: Color(0x99000000), blurRadius: 28, offset: Offset(0, 12)),
    ],
  );

  @override
  AppTokens copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceMuted,
    Color? outline,
    Color? outlineStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textDisabled,
    Color? onAccent,
    Color? success,
    Color? warning,
    Color? danger,
    Color? scrim,
  }) =>
      AppTokens(
        canvas: canvas ?? this.canvas,
        surface: surface ?? this.surface,
        surfaceRaised: surfaceRaised ?? this.surfaceRaised,
        surfaceMuted: surfaceMuted ?? this.surfaceMuted,
        outline: outline ?? this.outline,
        outlineStrong: outlineStrong ?? this.outlineStrong,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textDisabled: textDisabled ?? this.textDisabled,
        onAccent: onAccent ?? this.onAccent,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
        scrim: scrim ?? this.scrim,
        radiusSm: radiusSm,
        radiusMd: radiusMd,
        radiusLg: radiusLg,
        radiusXl: radiusXl,
        space1: space1,
        space2: space2,
        space3: space3,
        space4: space4,
        space5: space5,
        space6: space6,
        space8: space8,
        shadowSm: shadowSm,
        shadowMd: shadowMd,
        shadowLg: shadowLg,
      );

  @override
  AppTokens lerp(covariant ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      outlineStrong: Color.lerp(outlineStrong, other.outlineStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      radiusSm: radiusSm,
      radiusMd: radiusMd,
      radiusLg: radiusLg,
      radiusXl: radiusXl,
      space1: space1,
      space2: space2,
      space3: space3,
      space4: space4,
      space5: space5,
      space6: space6,
      space8: space8,
      shadowSm: shadowSm,
      shadowMd: shadowMd,
      shadowLg: shadowLg,
    );
  }
}

/// Browser-specific semantic colors, retained separately from general UI.
@immutable
class BrowserDesignTokens extends ThemeExtension<BrowserDesignTokens> {
  const BrowserDesignTokens(
      {required this.chromeBackground,
      required this.toolbarBackground,
      required this.addressBarBackground,
      required this.addressBarForeground,
      required this.divider,
      required this.webViewBackground,
      required this.privateAccent});
  final Color chromeBackground;
  final Color toolbarBackground;
  final Color addressBarBackground;
  final Color addressBarForeground;
  final Color divider;
  final Color webViewBackground;
  final Color privateAccent;
  static const light = BrowserDesignTokens(
      chromeBackground: Color(0xFFF5F7FB),
      toolbarBackground: Color(0xFFFFFFFF),
      addressBarBackground: Color(0xFFEEF2F8),
      addressBarForeground: Color(0xFF182230),
      divider: Color(0xFFD9E0EA),
      webViewBackground: Color(0xFFF5F7FB),
      privateAccent: Color(0xFF7656D8));
  static const dark = BrowserDesignTokens(
      chromeBackground: Color(0xFF0E1420),
      toolbarBackground: Color(0xFF151D2B),
      addressBarBackground: Color(0xFF243247),
      addressBarForeground: Color(0xFFF2F4F7),
      divider: Color(0xFF344054),
      webViewBackground: Color(0xFF0E1420),
      privateAccent: Color(0xFFD0BCFF));
  @override
  BrowserDesignTokens copyWith(
          {Color? chromeBackground,
          Color? toolbarBackground,
          Color? addressBarBackground,
          Color? addressBarForeground,
          Color? divider,
          Color? webViewBackground,
          Color? privateAccent}) =>
      BrowserDesignTokens(
          chromeBackground: chromeBackground ?? this.chromeBackground,
          toolbarBackground: toolbarBackground ?? this.toolbarBackground,
          addressBarBackground:
              addressBarBackground ?? this.addressBarBackground,
          addressBarForeground:
              addressBarForeground ?? this.addressBarForeground,
          divider: divider ?? this.divider,
          webViewBackground: webViewBackground ?? this.webViewBackground,
          privateAccent: privateAccent ?? this.privateAccent);
  @override
  BrowserDesignTokens lerp(
      covariant ThemeExtension<BrowserDesignTokens>? other, double t) {
    if (other is! BrowserDesignTokens) return this;
    return BrowserDesignTokens(
        chromeBackground:
            Color.lerp(chromeBackground, other.chromeBackground, t)!,
        toolbarBackground:
            Color.lerp(toolbarBackground, other.toolbarBackground, t)!,
        addressBarBackground:
            Color.lerp(addressBarBackground, other.addressBarBackground, t)!,
        addressBarForeground:
            Color.lerp(addressBarForeground, other.addressBarForeground, t)!,
        divider: Color.lerp(divider, other.divider, t)!,
        webViewBackground:
            Color.lerp(webViewBackground, other.webViewBackground, t)!,
        privateAccent: Color.lerp(privateAccent, other.privateAccent, t)!);
  }
}

extension ThemeTokens on BuildContext {
  AppTokens get tokens =>
      Theme.of(this).extension<AppTokens>() ?? AppTokens.light;
  BrowserDesignTokens get browserTokens =>
      Theme.of(this).extension<BrowserDesignTokens>() ??
      BrowserDesignTokens.light;
}

const List<List<Color>> _palette = [
  [Color(0xFFE9ECFB), Color(0xFF4353C4)],
  [Color(0xFFFFF0DB), Color(0xFFC07A17)],
  [Color(0xFFE1F5EB), Color(0xFF1E9C68)],
  [Color(0xFFFCE7EF), Color(0xFFCE4A7F)],
  [Color(0xFFEFE9FB), Color(0xFF7A5BD6)],
  [Color(0xFFE3F2FC), Color(0xFF2E8EC7)],
];
int _hash(String key) =>
    key.codeUnits.fold(0, (h, c) => (h * 31 + c) & 0x7fffffff);
LinearGradient tileGradient(String key) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: _palette[_hash(key) % _palette.length]);

ThemeData _buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final t = dark ? AppTokens.dark : AppTokens.light;
  final browser = dark ? BrowserDesignTokens.dark : BrowserDesignTokens.light;
  final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: brightness,
      primary: dark ? AppColors.brand : AppColors.primary,
      secondary: dark ? AppColors.brand : AppColors.accent,
      error: t.danger,
      surface: t.surface);
  final shape =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusMd));
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.canvas,
    fontFamily:
        defaultTargetPlatform == TargetPlatform.iOS ? '.SF Pro Text' : null,
    fontFamilyFallback: const ['PingFang SC', 'Noto Sans CJK SC'],
    extensions: <ThemeExtension<dynamic>>[t, browser],
    textTheme: Typography.material2021(platform: defaultTargetPlatform)
        .black
        .apply(bodyColor: t.textPrimary, displayColor: t.textPrimary),
    appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: t.surface,
        foregroundColor: t.textPrimary,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w700, color: t.textPrimary)),
    navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: t.surface.withValues(alpha: .92),
        indicatorColor: scheme.primary.withValues(alpha: .14),
        shadowColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: t.textSecondary)),
        iconTheme:
            WidgetStatePropertyAll(IconThemeData(color: t.textSecondary)),
        surfaceTintColor: Colors.transparent),
    cardTheme: CardThemeData(
        color: t.surfaceRaised,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: shape,
        surfaceTintColor: Colors.transparent),
    dividerTheme: DividerThemeData(color: t.outline, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surfaceMuted,
        contentPadding:
            EdgeInsets.symmetric(horizontal: t.space4, vertical: t.space3),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(t.radiusMd),
            borderSide: BorderSide(color: t.outline)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(t.radiusMd),
            borderSide: BorderSide(color: t.outline)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(t.radiusMd),
            borderSide: BorderSide(color: scheme.primary, width: 2)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(t.radiusMd),
            borderSide: BorderSide(color: t.danger)),
        hintStyle: TextStyle(color: t.textSecondary)),
    elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: EdgeInsets.symmetric(horizontal: t.space4),
            shape: shape,
            elevation: 0,
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary)),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: EdgeInsets.symmetric(horizontal: t.space4),
            shape: shape)),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: EdgeInsets.symmetric(horizontal: t.space4),
            shape: shape,
            side: BorderSide(color: t.outlineStrong))),
    textButtonTheme: TextButtonThemeData(
        style:
            TextButton.styleFrom(minimumSize: const Size(0, 44), shape: shape)),
    switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? scheme.onPrimary
                : t.textSecondary),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? scheme.primary
                : t.surfaceMuted)),
    snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: t.surfaceRaised,
        contentTextStyle: TextStyle(color: t.textPrimary),
        shape: shape),
    bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(t.radiusXl)))),
    dialogTheme: DialogThemeData(
        backgroundColor: t.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(t.radiusXl))),
  );
}

ThemeData buildAppLightTheme() => _buildTheme(Brightness.light);
ThemeData buildAppDarkTheme() => _buildTheme(Brightness.dark);
ThemeData buildAppTheme() => buildAppLightTheme();

/// Layered bookmark background with theme-aware glow.
class Wallpaper extends StatelessWidget {
  const Wallpaper({super.key});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return DecoratedBox(
        decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [t.canvas, t.surfaceMuted, t.canvas])),
        child: Stack(children: [
          Positioned(
              right: -60,
              top: -40,
              child: _glow(
                  Theme.of(context).colorScheme.primary.withValues(alpha: .12),
                  320)),
          Positioned(
              left: -80,
              bottom: -60,
              child: _glow(
                  Theme.of(context)
                      .colorScheme
                      .secondary
                      .withValues(alpha: .10),
                  340))
        ]));
  }

  Widget _glow(Color color, double size) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient:
              RadialGradient(colors: [color, color.withValues(alpha: 0)])));
}
