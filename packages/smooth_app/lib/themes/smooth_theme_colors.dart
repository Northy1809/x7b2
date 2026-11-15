import 'package:flutter/material.dart';

class SmoothColorsThemeExtension
    extends ThemeExtension<SmoothColorsThemeExtension> {
  SmoothColorsThemeExtension({
    required this.primaryUltraBlack,
    required this.primaryBlack,
    required this.primaryDark,
    required this.primarySemiDark,
    required this.primaryTone,
    required this.primaryNormal,
    required this.primaryAccent,
    required this.primaryMedium,
    required this.primaryLight,
    required this.secondaryNormal,
    required this.secondaryVibrant,
    required this.secondaryLight,
    required this.error,
    required this.errorGradient,
    required this.successBackground,
    required this.warning,
    required this.warningGradient,
    required this.warningBackground,
    required this.success,
    required this.successGradient,
    required this.errorBackground,
    required this.greyDark,
    required this.greyNormal,
    required this.greyMedium,
    required this.greyLight,
    required this.cellOdd,
    required this.cellEven,
  });

  SmoothColorsThemeExtension.defaultValues(bool lightTheme)
    // Owned (13/11 2026): Cal AI's greys. Success, warning and error have
    // no hue either; they read from the icon and the words.
    : primaryUltraBlack = const Color(0xFF000000),
      primaryBlack = const Color(0xFF1E1A22),
      primaryDark = const Color(0xFF2E2A33),
      primarySemiDark = const Color(0xFF3A363D),
      primaryTone = const Color(0xFF767676),
      primaryAccent = const Color(0xFF1E1A22),
      primaryNormal = const Color(0xFFAFAEB3),
      primaryMedium = const Color(0xFFEBEAF1),
      primaryLight = const Color(0xFFF6F5FC),
      secondaryNormal = const Color(0xFF3A363D),
      secondaryVibrant = const Color(0xFF1E1A22),
      secondaryLight = const Color(0xFFD5D4DA),
      success = const Color(0xFF1E1A22),
      successGradient = const Color(0xFF3A363D),
      successBackground = const Color(0xFFF6F5FC),
      warning = const Color(0xFF1E1A22),
      warningGradient = const Color(0xFF3A363D),
      warningBackground = const Color(0xFFF6F5FC),
      error = const Color(0xFF1E1A22),
      errorGradient = const Color(0xFF3A363D),
      errorBackground = const Color(0xFFF6F5FC),
      greyDark = const Color(0xFF666666),
      greyNormal = const Color(0xFF767676),
      greyMedium = const Color(0xFFAFAEB3),
      greyLight = const Color(0xFFEBEAF1),
      cellOdd = lightTheme ? const Color(0xFFF9F8FD) : const Color(0xFF1C1B1F),
      cellEven = lightTheme ? const Color(0xFFFFFFFF) : const Color(0xFF161519);

  // Ristreto
  final Color primaryUltraBlack;

  // Chocolate
  final Color primaryBlack;

  // Cortado
  final Color primaryDark;

  // Mocha
  final Color primarySemiDark;

  // Darker Macchiato (from old palette)
  final Color primaryTone;

  final Color primaryAccent;

  // Macchiato
  final Color primaryNormal;

  // Cappuccino
  final Color primaryMedium;

  // Latte
  final Color primaryLight;
  final Color secondaryNormal;
  final Color secondaryVibrant;
  final Color secondaryLight;

  /// When used alone
  final Color error;
  final Color errorBackground;
  final Color warning;
  final Color warningBackground;
  final Color success;
  final Color successBackground;

  /// When used together
  final Color errorGradient;
  final Color warningGradient;
  final Color successGradient;

  final Color greyDark;
  final Color greyNormal;
  final Color greyMedium;
  final Color greyLight;

  final Color cellOdd;
  final Color cellEven;

  @override
  ThemeExtension<SmoothColorsThemeExtension> copyWith({
    Color? primaryUltraBlack,
    Color? primaryBlack,
    Color? primaryDark,
    Color? primarySemiDark,
    Color? primaryTone,
    Color? primaryNormal,
    Color? primaryAccent,
    Color? primaryMedium,
    Color? primaryLight,
    Color? secondaryNormal,
    Color? secondaryLight,
    Color? secondaryVibrant,
    Color? error,
    Color? errorGradient,
    Color? errorBackground,
    Color? warning,
    Color? warningGradient,
    Color? warningBackground,
    Color? success,
    Color? successGradient,
    Color? successBackground,
    Color? greyDark,
    Color? greyNormal,
    Color? greyMedium,
    Color? greyLight,
    Color? cellOdd,
    Color? cellEven,
  }) {
    return SmoothColorsThemeExtension(
      primaryUltraBlack: primaryUltraBlack ?? this.primaryUltraBlack,
      primaryBlack: primaryBlack ?? this.primaryBlack,
      primaryDark: primaryDark ?? this.primaryDark,
      primarySemiDark: primarySemiDark ?? this.primarySemiDark,
      primaryTone: primaryTone ?? this.primaryTone,
      primaryNormal: primaryNormal ?? this.primaryNormal,
      primaryAccent: primaryAccent ?? this.primaryAccent,
      primaryMedium: primaryMedium ?? this.primaryMedium,
      primaryLight: primaryLight ?? this.primaryLight,
      secondaryNormal: secondaryNormal ?? this.secondaryNormal,
      secondaryLight: secondaryLight ?? this.secondaryLight,
      secondaryVibrant: secondaryVibrant ?? this.secondaryVibrant,
      error: error ?? this.error,
      errorGradient: errorGradient ?? this.errorGradient,
      errorBackground: errorBackground ?? this.errorBackground,
      warning: warning ?? this.warning,
      warningGradient: warningGradient ?? this.warningGradient,
      warningBackground: warningBackground ?? this.warningBackground,
      success: success ?? this.success,
      successGradient: successGradient ?? this.successGradient,
      successBackground: successBackground ?? this.successBackground,
      greyDark: greyDark ?? this.greyDark,
      greyNormal: greyDark ?? this.greyDark,
      greyMedium: greyMedium ?? this.greyMedium,
      greyLight: greyLight ?? this.greyLight,
      cellOdd: cellOdd ?? this.cellOdd,
      cellEven: cellEven ?? this.cellEven,
    );
  }

  @override
  ThemeExtension<SmoothColorsThemeExtension> lerp(
    covariant ThemeExtension<SmoothColorsThemeExtension>? other,
    double t,
  ) {
    if (other is! SmoothColorsThemeExtension) {
      return this;
    }

    return SmoothColorsThemeExtension(
      primaryUltraBlack: Color.lerp(
        primaryUltraBlack,
        other.primaryUltraBlack,
        t,
      )!,
      primaryBlack: Color.lerp(primaryBlack, other.primaryBlack, t)!,
      primaryDark: Color.lerp(primaryDark, other.primaryDark, t)!,
      primarySemiDark: Color.lerp(primarySemiDark, other.primarySemiDark, t)!,
      primaryTone: Color.lerp(primaryTone, other.primaryTone, t)!,
      primaryNormal: Color.lerp(primaryNormal, other.primaryNormal, t)!,
      primaryAccent: Color.lerp(primaryAccent, other.primaryAccent, t)!,
      primaryMedium: Color.lerp(primaryMedium, other.primaryMedium, t)!,
      primaryLight: Color.lerp(primaryLight, other.primaryLight, t)!,
      secondaryNormal: Color.lerp(secondaryNormal, other.secondaryNormal, t)!,
      secondaryLight: Color.lerp(secondaryLight, other.secondaryLight, t)!,
      secondaryVibrant: Color.lerp(
        secondaryVibrant,
        other.secondaryVibrant,
        t,
      )!,

      error: Color.lerp(error, other.error, t)!,
      errorGradient: Color.lerp(errorGradient, other.errorGradient, t)!,
      errorBackground: Color.lerp(errorBackground, other.errorBackground, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningGradient: Color.lerp(warningGradient, other.warningGradient, t)!,
      warningBackground: Color.lerp(
        warningBackground,
        other.warningBackground,
        t,
      )!,
      success: Color.lerp(success, other.success, t)!,
      successGradient: Color.lerp(successGradient, other.successGradient, t)!,
      successBackground: Color.lerp(
        successBackground,
        other.successBackground,
        t,
      )!,
      greyDark: Color.lerp(greyDark, other.greyDark, t)!,
      greyNormal: Color.lerp(greyNormal, other.greyNormal, t)!,
      greyMedium: Color.lerp(greyMedium, other.greyMedium, t)!,
      greyLight: Color.lerp(greyLight, other.greyLight, t)!,
      cellOdd: Color.lerp(cellOdd, other.cellOdd, t)!,
      cellEven: Color.lerp(cellEven, other.cellEven, t)!,
    );
  }
}

extension SmoothThemeExtension on BuildContext {
  T extension<T>() {
    return Theme.of(this).extension<T>()!;
  }
}
