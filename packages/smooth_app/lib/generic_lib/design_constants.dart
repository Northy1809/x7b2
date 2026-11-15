import 'package:flutter/material.dart';

const String APP_NAME = 'Owned';

const Widget EMPTY_WIDGET = SizedBox.shrink();

const double VERY_SMALL_SPACE = 4.0;
const double SMALL_SPACE = 8.0;
const double BALANCED_SPACE = 10.0;
const double MEDIUM_SPACE = 12.0;
const double LARGE_SPACE = 16.0;
const double VERY_LARGE_SPACE = 20.0;

/// Standard minimum touch/target size, cf. goldens.dart
const double MINIMUM_TOUCH_SIZE = kMinInteractiveDimension;

/// Default icon size, cf. [Icon]
const double DEFAULT_ICON_SIZE = 24.0;

/// Background, e.g SmoothCard
const Radius ROUNDED_RADIUS = Radius.circular(20.0);
//ignore: non_constant_identifier_names
const BorderRadius ROUNDED_BORDER_RADIUS = BorderRadius.all(ROUNDED_RADIUS);

/// Topbar…
const Radius HEADER_ROUNDED_RADIUS = Radius.circular(30.0);
//ignore: non_constant_identifier_names
const BorderRadius HEADER_BORDER_RADIUS = BorderRadius.all(
  HEADER_ROUNDED_RADIUS,
);

/// Full screen button, e.g. KnowledgePanel
const Radius ANGULAR_RADIUS = Radius.circular(8.0);
//ignore: non_constant_identifier_names
const BorderRadius ANGULAR_BORDER_RADIUS = BorderRadius.all(ANGULAR_RADIUS);

/// Buttons & TextFields
const Radius CIRCULAR_RADIUS = Radius.circular(40.0);
//ignore: non_constant_identifier_names
const BorderRadius CIRCULAR_BORDER_RADIUS = BorderRadius.all(CIRCULAR_RADIUS);

const BorderRadius MAX_BORDER_RADIUS = BorderRadius.all(Radius.circular(100.0));

/// Widget Colors. Owned (13/11 2026): no hue anywhere, so the old Open Food
/// Facts colours are mapped onto Cal AI's greys (see BrandColors).
const Color WARNING_COLOR = Color(0xFF1E1A22);
const Color PRIMARY_BLUE_COLOR = Color(0xFF1E1A22);
const Color PRIMARY_GREY_COLOR = Color(0xFF4F4F4F);
const Color FAIR_GREY_COLOR = Color(0xFF767676);
const Color GREY_COLOR = Color(0xFFF6F5FC);
const Color WHITE_COLOR = Color(0xFFFFFFFF);
const Color DARK_GREEN_COLOR = Color(0xFF1E1A22);
const Color LIGHT_GREEN_COLOR = Color(0xFF3A363D);
const Color LIGHT_YELLOW_COLOR = Color(0xFFAFAEB3);
const Color LIGHT_GREY_COLOR = Color(0xFFBFBFBF);
const Color DARK_YELLOW_COLOR = Color(0xFF767676);
const Color LIGHT_ORANGE_COLOR = Color(0xFF767676);
const Color DARK_ORANGE_COLOR = Color(0xFF3A363D);
const Color RED_COLOR = Color(0xFF1E1A22);
const Color LIGHT_RED_COLOR = Color(0xFFEBEAF1);
const Color DARK_RED_COLOR = Color(0xFF1E1A22);
const Color DARK_BROWN_COLOR = Color(0xFF1E1A22);

/// Widget Background Colors
const Color RED_BACKGROUND_COLOR = Color(0xFFF6F5FC);
const Color ORANGE_BACKGROUND_COLOR = Color(0xFFF6F5FC);
const Color YELLOW_BACKGROUND_COLOR = Color(0xFFF6F5FC);
const Color LIGHT_GREEN_BACKGROUND_COLOR = Color(0xFFF6F5FC);
const Color DARK_GREEN_BACKGROUND_COLOR = Color(0xFFF6F5FC);
