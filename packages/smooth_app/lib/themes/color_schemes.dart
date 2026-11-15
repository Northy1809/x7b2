import 'package:flutter/material.dart';

const Color seed = Color(0xFF1E1A22);

/// Cal AI's palette (see BrandColors): ink on white, lavender-grey fills.
/// No hue at all, not even for errors.
const ColorScheme lightColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF1E1A22),
  inversePrimary: Color(0xFFFFFFFF),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFF6F5FC),
  onPrimaryContainer: Color(0xFF1E1A22),
  secondary: Color(0xFFF6F5FC),
  onSecondary: Color(0xFF1E1A22),
  tertiary: Color(0xFF3A363D),
  onTertiary: Color(0xFFFFFFFF),
  error: Color(0xFF1E1A22),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFF6F5FC),
  onErrorContainer: Color(0xFF1E1A22),
  surface: Color(0xFFFFFFFF),
  onSurface: Color(0xFF1E1A22),
  onSurfaceVariant: Color(0xFF767676),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF9F8FD),
  surfaceContainer: Color(0xFFF6F5FC),
  surfaceContainerHigh: Color(0xFFF1F0F6),
  surfaceContainerHighest: Color(0xFFEBEAF1),
  outline: Color(0xFFAFAEB3),
  outlineVariant: Color(0xFFEBEAF1),
  surfaceTint: Color(0x00000000),
);

const ColorScheme darkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFF5F5F7),
  inversePrimary: Color(0xFF121212),
  onPrimary: Color(0xFF121212),
  primaryContainer: Color(0xFF2C2C2E),
  onPrimaryContainer: Color(0xFFF5F5F7),
  secondary: Color(0xFF2C2C2E),
  onSecondary: Color(0xFFF5F5F7),
  tertiary: Color(0xFFD1D1D6),
  onTertiary: Color(0xFF121212),
  error: Color(0xFFF5F5F7),
  onError: Color(0xFF1E1A22),
  surface: Color(0xFF1C1C1E),
  onSurface: Color(0xFFF5F5F7),
  onSurfaceVariant: Color(0xFFA1A1A6),
  surfaceContainerLowest: Color(0xFF0E0E0F),
  surfaceContainerLow: Color(0xFF161618),
  surfaceContainer: Color(0xFF1C1C1E),
  surfaceContainerHigh: Color(0xFF242426),
  surfaceContainerHighest: Color(0xFF2C2C2E),
  outline: Color(0xFF636366),
  outlineVariant: Color(0xFF2C2C2E),
);

const ColorScheme trueDarkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: COLOR_DEFAULT,
  inversePrimary: Color(0xFFFFFFFF),
  onPrimary: Color(0xFF000000),
  secondary: COLOR_DEFAULT,
  onSecondary: Color(0xFFE1E1E1),
  error: Color(0xFFE1E1E1),
  onError: Color(0xFFE1E1E1),
  surface: Color(0xFF000000),
  onSurface: Color(0xFFFFFFFF),
);

const String CONTRAST_LOW = 'Low';
const String CONTRAST_MEDIUM = 'Medium';
const String CONTRAST_HIGH = 'High';

// All of the contrast Level passes WCAG 2.1 Results for text Readability.
const Color LOW_CONTRAST_TEXT_COLOR = Color(0xff969696);
const Color MEDIUM_CONTRAST_TEXT_COLOR = Color(0xffcacaca);
const Color HIGH_CONTRAST_TEXT_COLOR = Color(0xffffffff);

const Color Test = Colors.white10;

const String COLOR_DEFAULT_NAME = 'Default';
const Color COLOR_DEFAULT = Color(0xFFE1E1E1);
const Color COLOR_BLUE = Colors.blue;
const Color COLOR_CYAN = Color(0xff0097a7);
const Color COLOR_GREEN = Color(0xff009b52);
const Color COLOR_MAGENTA = Color(0xffff00ff);
const Color COLOR_ORANGE = Colors.deepOrange;
const Color COLOR_PINK = Colors.pink;
const Color COLOR_RED = Color(0xffff0000);
const Color COLOR_RUST = Color(0xffb7410e);
const Color COLOR_TEAL = Colors.teal;

const Map<String, Color> colorNamesValue = <String, Color>{
  'Default': COLOR_DEFAULT,
  'Blue': COLOR_BLUE,
  'Cyan': COLOR_CYAN,
  'Green': COLOR_GREEN,
  'Magenta': COLOR_MAGENTA,
  'Orange': COLOR_ORANGE,
  'Pink': COLOR_PINK,
  'Red': COLOR_RED,
  'Rust': COLOR_RUST,
  'Teal': COLOR_TEAL,
};

/// Get Color from Color Name using colorNamesValue
/// Owned has no accent colours: every name gives the same grey.
Color getColorValue(String colorName) => COLOR_DEFAULT;

Color getTextContrastLevel(String contrastLevel) {
  switch (contrastLevel) {
    case CONTRAST_LOW:
      return LOW_CONTRAST_TEXT_COLOR;

    case CONTRAST_MEDIUM:
      return MEDIUM_CONTRAST_TEXT_COLOR;

    case CONTRAST_HIGH:
      return HIGH_CONTRAST_TEXT_COLOR;

    default:
      return HIGH_CONTRAST_TEXT_COLOR;
  }
}
