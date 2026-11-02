/// تم ثابت و یکپارچهٔ برنامه — فقط حالت تاریک (Dark Mode).
///
/// رنگ‌بندی مستقل از رنگ آیکون بازی انتخاب شده است و برای وضعیت‌های مختلف
/// (تأیید، تکراری، رد، خالی) رنگ‌های قابل تشخیص دارد.
library;

import 'package:flutter/material.dart';

/// رنگ‌های ثابت برنامه.
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF0E1116);
  static const Color surface = Color(0xFF161B22);
  static const Color surfaceHigh = Color(0xFF1E2530);
  static const Color outline = Color(0xFF2C3542);

  static const Color primary = Color(0xFF7C6CFF);
  static const Color primarySoft = Color(0xFF2A2550);

  static const Color textPrimary = Color(0xFFF2F4F8);
  static const Color textSecondary = Color(0xFF9AA4B2);
  static const Color textMuted = Color(0xFF6B7684);

  static const Color confirmed = Color(0xFF2FBF71);
  static const Color duplicate = Color(0xFFF2B01E);
  static const Color rejected = Color(0xFFF0555A);
  static const Color warning = Color(0xFFFFA726);
  static const Color timer = Color(0xFF4FC3F7);
}

/// ساخت تم برنامه.
ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Vazirmatn',
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.timer,
      onSecondary: Colors.black,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.rejected,
      onError: Colors.white,
      outline: AppColors.outline,
    ),
  );

  return base.copyWith(
    textTheme: base.textTheme
        .apply(
          fontFamily: 'Vazirmatn',
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        )
        .copyWith(
          headlineSmall: const TextStyle(
            fontFamily: 'Vazirmatn',
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          titleLarge: const TextStyle(
            fontFamily: 'Vazirmatn',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          titleMedium: const TextStyle(
            fontFamily: 'Vazirmatn',
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          bodyMedium: const TextStyle(
            fontFamily: 'Vazirmatn',
            fontSize: 14,
            height: 1.7,
            color: AppColors.textPrimary,
          ),
          bodySmall: const TextStyle(
            fontFamily: 'Vazirmatn',
            fontSize: 12.5,
            height: 1.6,
            color: AppColors.textSecondary,
          ),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: 'Vazirmatn',
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      iconTheme: IconThemeData(color: AppColors.textPrimary),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.outline,
      thickness: 0.7,
      space: 1,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: TextStyle(
        fontFamily: 'Vazirmatn',
        color: AppColors.textPrimary,
        fontSize: 13.5,
      ),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: 'Vazirmatn',
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      contentTextStyle: TextStyle(
        fontFamily: 'Vazirmatn',
        fontSize: 14,
        height: 1.8,
        color: AppColors.textPrimary,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: const TextStyle(
        fontFamily: 'Vazirmatn',
        color: AppColors.textMuted,
        fontSize: 13.5,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        textStyle: const TextStyle(
          fontFamily: 'Vazirmatn',
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        minimumSize: const Size.fromHeight(52),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.outline),
        textStyle: const TextStyle(
          fontFamily: 'Vazirmatn',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        minimumSize: const Size.fromHeight(48),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(
          fontFamily: 'Vazirmatn',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
