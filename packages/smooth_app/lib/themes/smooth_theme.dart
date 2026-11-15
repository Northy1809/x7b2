import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/themes/color_provider.dart';
import 'package:smooth_app/themes/color_schemes.dart';
import 'package:smooth_app/themes/contrast_provider.dart';
import 'package:smooth_app/themes/smooth_theme_colors.dart';
import 'package:smooth_app/themes/theme_provider.dart';

class SmoothTheme {
  const SmoothTheme._();

  static const double ADDITIONAL_OPACITY_FOR_DARK = .3;
  static const double SECONDARY_COLOR_SHADE_VALUE = 0.4;

  static ThemeData getThemeData(
    final Brightness brightness,
    final ThemeProvider themeProvider,
    final ColorProvider Function() colorProvider,
    final TextContrastProvider Function() textContrastProvider,
  ) {
    final bool lightTheme = brightness == Brightness.light;
    ColorScheme myColorScheme;

    if (lightTheme) {
      myColorScheme = lightColorScheme;
    } else {
      if (themeProvider.currentTheme == THEME_AMOLED) {
        final ColorProvider colorNotifier = colorProvider();

        myColorScheme = trueDarkColorScheme.copyWith(
          primary: getColorValue(colorNotifier.currentColor),
          secondary: getShade(
            getColorValue(colorNotifier.currentColor),
            darker: true,
            value: SECONDARY_COLOR_SHADE_VALUE,
          ),
        );
      } else {
        myColorScheme = darkColorScheme;
      }
    }

    final SmoothColorsThemeExtension smoothExtension =
        SmoothColorsThemeExtension.defaultValues(lightTheme);

    final TextTheme textTheme = brightness == Brightness.dark
        ? getTextTheme(themeProvider, textContrastProvider)
        : _TEXT_THEME.apply(
            bodyColor: myColorScheme.onSurface,
            displayColor: myColorScheme.onSurface,
          );
    final Color paper = lightTheme ? BrandColors.paper : BrandColors.paperDark;
    final Color hairline = lightTheme
        ? BrandColors.hairline
        : BrandColors.hairlineDark;
    // Cal AI's pill: ink with white text, and #AFAEB3 with white text while
    // it can't be pressed yet (measured from its onboarding).
    final ButtonStyle pill = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) => states.contains(WidgetState.disabled)
            ? (lightTheme ? BrandColors.faint : BrandColors.hairlineDark)
            : myColorScheme.primary,
      ),
      foregroundColor: WidgetStateProperty.resolveWith<Color?>(
        (Set<WidgetState> states) => states.contains(WidgetState.disabled)
            ? (lightTheme ? Colors.white : BrandColors.mutedDark)
            : myColorScheme.onPrimary,
      ),
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      animationDuration: const Duration(milliseconds: 100),
      iconColor: WidgetStatePropertyAll<Color>(myColorScheme.onPrimary),
      elevation: const WidgetStatePropertyAll<double>(0),
      shape: const WidgetStatePropertyAll<OutlinedBorder>(StadiumBorder()),
      padding: const WidgetStatePropertyAll<EdgeInsets>(
        EdgeInsets.symmetric(horizontal: 24.0, vertical: 15.0),
      ),
      minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 54.0)),
      // A button's text style replaces the theme's, so it carries the family.
      textStyle: const WidgetStatePropertyAll<TextStyle?>(_BUTTON_TEXT),
    );

    final ThemeData base = ThemeData(
      primaryColor: myColorScheme.primary,
      extensions: <ThemeExtension<dynamic>>[smoothExtension],
      colorScheme: myColorScheme,
      canvasColor: themeProvider.currentTheme == THEME_AMOLED
          ? myColorScheme.surface
          : paper,
      scaffoldBackgroundColor: themeProvider.currentTheme == THEME_AMOLED
          ? null
          : paper,
      shadowColor: brightness == Brightness.light
          ? Colors.black26
          : Colors.white12,
      // No ink ripples, as on iOS and in Cal AI: things shrink a little
      // while pressed instead (PressScale).
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      hoverColor: Colors.transparent,
      elevatedButtonTheme: ElevatedButtonThemeData(style: pill),
      filledButtonTheme: FilledButtonThemeData(style: pill),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll<Color>(
            myColorScheme.onSurface,
          ),
          iconColor: WidgetStatePropertyAll<Color>(myColorScheme.onSurface),
          shape: const WidgetStatePropertyAll<OutlinedBorder>(
            StadiumBorder(),
          ),
          overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
          backgroundColor: WidgetStatePropertyAll<Color>(myColorScheme.surface),
          side: WidgetStatePropertyAll<BorderSide>(
            BorderSide(
              color: lightTheme ? BrandColors.hairline : BrandColors.hairlineDark,
              width: 1.5,
            ),
          ),
          padding: const WidgetStatePropertyAll<EdgeInsets>(
            EdgeInsets.symmetric(horizontal: 24.0, vertical: 15.0),
          ),
          minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 54.0)),
          textStyle: const WidgetStatePropertyAll<TextStyle?>(_BUTTON_TEXT),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll<Color>(
            myColorScheme.onSurface,
          ),
          minimumSize: const WidgetStatePropertyAll<Size>(
            Size(0, MINIMUM_TOUCH_SIZE),
          ),
          textStyle: const WidgetStatePropertyAll<TextStyle?>(_BUTTON_TEXT),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: myColorScheme.primary,
        foregroundColor: myColorScheme.onPrimary,
        elevation: 6.0,
        highlightElevation: 6.0,
        shape: const CircleBorder(),
      ),
      textTheme: textTheme,
      // iOS draws the cursor, selection handles and Cupertino controls in
      // system blue unless told otherwise: ink, as everything else.
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: myColorScheme.primary,
        selectionColor: myColorScheme.primary.withValues(alpha: 0.18),
        selectionHandleColor: myColorScheme.primary,
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        primaryColor: myColorScheme.primary,
        brightness: brightness,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0.0,
        scrolledUnderElevation: 0.0,
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        foregroundColor: myColorScheme.onSurface,
        systemOverlayStyle: lightTheme
            ? SystemUiOverlayStyle.dark
            : SystemUiOverlayStyle.light,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontSize: 17.0,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: myColorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0.0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
          side: BorderSide(
            color: lightTheme ? const Color(0xFFF1F0F5) : hairline,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: lightTheme ? BrandColors.fill : BrandColors.fillDark,
        selectedColor: myColorScheme.primary,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: textTheme.labelLarge,
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(
          color: myColorScheme.onPrimary,
        ),
        checkmarkColor: myColorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 6.0),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodyMedium?.copyWith(
          color: myColorScheme.onSurfaceVariant,
        ),
        iconColor: myColorScheme.onSurface,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: myColorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.0)),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: myColorScheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32.0)),
        ),
        dragHandleColor: lightTheme ? BrandColors.hairline : BrandColors.hairlineDark,
        dragHandleSize: const Size(40.0, 5.0),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: myColorScheme.onSurface,
        linearTrackColor: lightTheme ? BrandColors.hairline : BrandColors.hairlineDark,
        circularTrackColor: lightTheme ? BrandColors.hairline : BrandColors.hairlineDark,
      ),
      dividerTheme: DividerThemeData(color: hairline, space: 1.0),
      dividerColor: hairline,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightTheme ? BrandColors.fill : BrandColors.fillDark,
        hintStyle: textTheme.bodyLarge?.copyWith(
          color: myColorScheme.onSurfaceVariant,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14.0),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 14.0,
        ),
      ),
      iconTheme: IconThemeData(color: myColorScheme.onSurface),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.0)),
        contentTextStyle: _TEXT_THEME.bodyMedium?.copyWith(
          color: lightTheme ? Colors.white : BrandColors.ink,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: lightTheme ? Colors.white : BrandColors.ink,
        backgroundColor: lightTheme ? BrandColors.ink : Colors.white,
      ),
      bannerTheme: MaterialBannerThemeData(
        contentTextStyle: TextStyle(color: myColorScheme.onSecondary),
        backgroundColor: myColorScheme.secondary,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color?>((
          Set<WidgetState> states,
        ) {
          if (states.contains(WidgetState.disabled)) {
            return null;
          }
          if (states.contains(WidgetState.selected)) {
            return lightTheme
                ? smoothExtension.primarySemiDark
                : smoothExtension.primaryNormal;
          }
          return null;
        }),
        side: BorderSide(
          color: lightTheme
              ? smoothExtension.primaryBlack
              : smoothExtension.primarySemiDark,
          width: 2.0,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3.0)),
        checkColor: const WidgetStatePropertyAll<Color>(Colors.white),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color?>((
          Set<WidgetState> states,
        ) {
          if (states.contains(WidgetState.disabled)) {
            return null;
          }
          if (states.contains(WidgetState.selected)) {
            return myColorScheme.primary;
          }
          return null;
        }),
      ),
      // Cal AI's switch (Imperial / Metric): a white knob on an ink track
      // when on, on a light grey track when off.
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll<Color>(Colors.white),
        trackColor: WidgetStateProperty.resolveWith<Color?>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? myColorScheme.primary
              : (lightTheme ? const Color(0xFFE9E9EB) : BrandColors.hairlineDark),
        ),
        trackOutlineColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      ),
    );
    return base;
  }

  static TextTheme getTextTheme(
    ThemeProvider themeProvider,
    TextContrastProvider Function() textContrastProvider,
  ) {
    final Color contrastLevel = themeProvider.currentTheme == THEME_AMOLED
        ? getTextContrastLevel(textContrastProvider().currentContrastLevel)
        : Colors.white;

    return _TEXT_THEME.apply(
      bodyColor: contrastLevel,
      displayColor: contrastLevel,
    );
  }

  /// Apple's SF Pro, as Cal AI uses: on iOS these two names are the system
  /// font itself (SF Pro Text below 20 pt, SF Pro Display from 20 pt).
  /// Elsewhere Inter, the closest open font, takes over.
  static const String TEXT_FONT = 'CupertinoSystemText';
  static const String DISPLAY_FONT = 'CupertinoSystemDisplay';
  static const List<String> FONT_FALLBACK = <String>['Inter'];

  static const TextStyle _BUTTON_TEXT = TextStyle(
    fontFamily: TEXT_FONT,
    fontFamilyFallback: FONT_FALLBACK,
    fontSize: 17.0,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.43,
  );

  /// Apple's text styles (Large Title 34, Title 1 28, Title 2 22, Title 3 20,
  /// Headline/Body 17, Subheadline 15, Footnote 13, Caption 11) in SF Pro,
  /// with Apple's own line heights and tracking (HIG typography table), as
  /// Cal AI uses them.
  static const TextTheme _TEXT_THEME = TextTheme(
    displayLarge: TextStyle(
      fontFamily: DISPLAY_FONT,
      fontFamilyFallback: FONT_FALLBACK,
      fontSize: 34.0,
      height: 1.21,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.37,
    ),
    displayMedium: TextStyle(
      fontFamily: DISPLAY_FONT,
      fontFamilyFallback: FONT_FALLBACK,
      fontSize: 28.0,
      height: 1.21,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.36,
    ),
    displaySmall: TextStyle(
      fontFamily: DISPLAY_FONT,
      fontFamilyFallback: FONT_FALLBACK,
      fontSize: 22.0,
      height: 1.27,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.35,
    ),
    headlineLarge: TextStyle(
      fontFamily: DISPLAY_FONT,
      fontFamilyFallback: FONT_FALLBACK,
      fontSize: 28.0,
      height: 1.21,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.36,
    ),
    headlineMedium: TextStyle(
      fontFamily: DISPLAY_FONT,
      fontFamilyFallback: FONT_FALLBACK,
      fontSize: 22.0,
      height: 1.27,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.35,
    ),
    headlineSmall: TextStyle(
      fontFamily: DISPLAY_FONT,
      fontFamilyFallback: FONT_FALLBACK,
      fontSize: 20.0,
      height: 1.25,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.38,
    ),
    titleLarge: TextStyle(
      fontFamily: DISPLAY_FONT,
      fontFamilyFallback: FONT_FALLBACK,
      fontSize: 20.0,
      height: 1.25,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.38,
    ),
    titleMedium: TextStyle(
      fontFamily: TEXT_FONT,
      fontFamilyFallback: FONT_FALLBACK,
      fontSize: 17.0,
      height: 1.29,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.43,
    ),
    titleSmall: TextStyle(
      fontFamily: TEXT_FONT,
      fontFamilyFallback: FONT_FALLBACK,
      fontSize: 15.0,
      height: 1.33,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.23,
    ),
    bodyLarge: TextStyle(
      fontFamily: TEXT_FONT,
      fontFamilyFallback: FONT_FALLBACK,
      fontSize: 17.0,
      height: 1.29,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.43,
    ),
    bodyMedium: TextStyle(
      fontFamily: TEXT_FONT,
      fontFamilyFallback: FONT_FALLBACK,
      fontSize: 15.0,
      height: 1.33,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.23,
    ),
    bodySmall: TextStyle(
      fontFamily: TEXT_FONT,
      fontFamilyFallback: FONT_FALLBACK,
      fontSize: 13.0,
      height: 1.38,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.08,
    ),
    labelLarge: TextStyle(
      fontFamily: TEXT_FONT,
      fontFamilyFallback: FONT_FALLBACK,
      fontSize: 15.0,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.23,
    ),
    labelMedium: TextStyle(
      fontFamily: TEXT_FONT,
      fontFamilyFallback: FONT_FALLBACK,
      fontSize: 13.0,
      height: 1.2,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.08,
    ),
    labelSmall: TextStyle(
      fontFamily: TEXT_FONT,
      fontFamilyFallback: FONT_FALLBACK,
      fontSize: 11.0,
      height: 1.18,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.07,
    ),
  );

  static MaterialColor getMaterialColorFromColor(Color color) {
    final Map<int, Color> colorShades = <int, Color>{
      50: getShade(color, value: 0.5),
      100: getShade(color, value: 0.4),
      200: getShade(color, value: 0.3),
      300: getShade(color, value: 0.2),
      400: getShade(color, value: 0.1),
      500: color,
      600: getShade(color, value: 0.1, darker: true),
      700: getShade(color, value: 0.15, darker: true),
      800: getShade(color, value: 0.2, darker: true),
      900: getShade(color, value: 0.25, darker: true),
    };
    return MaterialColor(color.intValue, colorShades);
  }

  //From: https://stackoverflow.com/a/58604669/13313941
  static Color getShade(Color color, {bool darker = false, double value = .1}) {
    assert(value >= 0 && value <= 1);

    final HSLColor hsl = HSLColor.fromColor(color);
    final HSLColor hslDark = hsl.withLightness(
      (darker ? (hsl.lightness - value) : (hsl.lightness + value)).clamp(
        0.0,
        1.0,
      ),
    );

    return hslDark.toColor();
  }
}

extension SmoothColorExtension on Color {
  /// ignore: deprecated_member_use
  /// [Color.value] is deprecated, use [Color.intValue] instead
  int get intValue {
    final int a = (this.a * 255).round();
    final int r = (this.r * 255).round();
    final int g = (this.g * 255).round();
    final int b = (this.b * 255).round();

    // Combine the components into a single int using bit shifting
    return (a << 24) | (r << 16) | (g << 8) | b;
  }
}
