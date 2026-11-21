import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // TenX Foundations Surface Tokens (Main.dc.html)
  static const Color darkCanvas = Color(0xFF000000); // Pure OLED Canvas
  static const Color darkSurface1 = Color(0xFF1C1C1E); // Surface 1
  static const Color darkSurface2 = Color(0xFF2C2C2E); // Surface 2
  static const Color darkSurface3 = Color(0xFF3A3A3C); // Surface 3
  static const Color darkBorder = Color(
    0x17FFFFFF,
  ); // rgba(255,255,255,0.09) Hairline
  static const Color darkGlass = Color.fromRGBO(44, 44, 46, 0.66); // Glass 66%

  // Semantic Tokens
  static const Color darkPrimary = Color(0xFF0A84FF); // Accent Blue
  static const Color darkBullish = Color(0xFF30D158); // Bull Green
  static const Color darkBearish = Color(0xFFFF453A); // Bear Red
  static const Color darkAmber = Color(0xFFFF9F0A); // Alert Amber
  static const Color darkAmberGold = Color(0xFFFFB340); // Alert Bright Amber
  static const Color darkViolet = Color(0xFFBF5AF2); // AI / Bollinger Violet
  static const Color darkCyan = Color(0xFF64D2FF); // Info / Drawing Cyan
  static const Color darkFastMa = Color(0xFFFFD60A); // Fast MA Gold

  // Text Tokens
  static const Color darkTextPrimary = Color(0xFFFFFFFF); // 100% white
  static const Color darkTextSecondary = Color.fromRGBO(
    235,
    235,
    245,
    0.62,
  ); // 62% label
  static const Color darkTextTertiary = Color.fromRGBO(
    235,
    235,
    245,
    0.34,
  ); // 34% label

  // Light Mode Palette
  static const Color lightCanvas = Color(0xFFF2F2F7);
  static const Color lightSurface1 = Color(0xFFFFFFFF);
  static const Color lightSurface2 = Color(0xFFE5E5EA);
  static const Color lightBorder = Color(0x1A000000);
  static const Color lightPrimary = Color(0xFF007AFF);
  static const Color lightBullish = Color(0xFF34C759);
  static const Color lightBearish = Color(0xFFFF3B30);
  static const Color lightTextPrimary = Color(0xFF000000);
  static const Color lightTextSecondary = Color.fromRGBO(60, 60, 67, 0.60);

  // Exact Geist Typography Helpers
  static TextStyle sans({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.geist(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? darkTextPrimary,
      letterSpacing: letterSpacing ?? (-0.01 * fontSize),
      height: height,
    );
  }

  static TextStyle mono({
    BuildContext? context,
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w500,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    Color? resolvedColor = color;
    if (resolvedColor == null && context != null) {
      resolvedColor = Theme.of(context).colorScheme.onSurface;
    }
    return GoogleFonts.geistMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: resolvedColor ?? darkTextPrimary,
      letterSpacing: letterSpacing ?? (-0.02 * fontSize),
      height: height,
      fontFeatures: const [
        FontFeature.tabularFigures(),
        FontFeature.liningFigures(),
      ],
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkCanvas,
      colorScheme: const ColorScheme.dark(
        surface: darkSurface1,
        primary: darkPrimary,
        secondary: darkBullish,
        error: darkBearish,
        outline: darkBorder,
        onSurface: darkTextPrimary,
        onSurfaceVariant: darkTextSecondary,
      ),
      dividerColor: darkBorder,
      cardColor: darkSurface1,
      textTheme: TextTheme(
        displayLarge: sans(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.03 * 34,
          color: darkTextPrimary,
        ),
        headlineMedium: sans(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.02 * 22,
          color: darkTextPrimary,
        ),
        headlineSmall: sans(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.01 * 17,
          color: darkTextPrimary,
        ),
        bodyLarge: sans(
          fontSize: 17,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.01 * 17,
          color: darkTextPrimary,
        ),
        bodyMedium: sans(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.01 * 15,
          color: darkTextPrimary,
        ),
        bodySmall: sans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: darkTextSecondary,
        ),
        labelSmall: sans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.09 * 11,
          color: darkTextSecondary,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface1,
        modalBackgroundColor: darkSurface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightCanvas,
      colorScheme: const ColorScheme.light(
        surface: lightSurface1,
        primary: lightPrimary,
        secondary: lightBullish,
        error: lightBearish,
        outline: lightBorder,
        onSurface: lightTextPrimary,
        onSurfaceVariant: lightTextSecondary,
      ),
      dividerColor: lightBorder,
      cardColor: lightSurface1,
      textTheme: TextTheme(
        displayLarge: sans(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.03 * 34,
          color: lightTextPrimary,
        ),
        headlineMedium: sans(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.02 * 22,
          color: lightTextPrimary,
        ),
        headlineSmall: sans(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.01 * 17,
          color: lightTextPrimary,
        ),
        bodyLarge: sans(
          fontSize: 17,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.01 * 17,
          color: lightTextPrimary,
        ),
        bodyMedium: sans(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.01 * 15,
          color: lightTextPrimary,
        ),
        bodySmall: sans(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: lightTextSecondary,
        ),
        labelSmall: sans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.09 * 11,
          color: lightTextSecondary,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: lightSurface1,
        modalBackgroundColor: lightSurface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
    );
  }
}

class AppColors {
  static const Color darkBackground = AppTheme.darkCanvas;
  static const Color lightBackground = AppTheme.lightCanvas;
  static const Color darkSurface = AppTheme.darkSurface1;
  static const Color lightSurface = AppTheme.lightSurface1;
  static const Color darkDivider = AppTheme.darkBorder;
  static const Color lightDivider = AppTheme.lightBorder;
  static const Color accentBlue = AppTheme.darkPrimary;
  static const Color bullishGreen = AppTheme.darkBullish;
  static const Color bearishRed = AppTheme.darkBearish;
}
