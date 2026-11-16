import 'package:flutter/material.dart';

/// The "Owned" look (13/11 2026): Cal AI's own palette, measured pixel by
/// pixel from its App Store screenshots and a screen recording
/// (research/ui/CALAI.md). White pages, a faint lavender-grey for fills,
/// warm near-black for text, rings and buttons, mid grey for labels.
/// No hue anywhere in the interface: only photos and logos have colour.
/// Keep in sync with tools/brand/make_brand_assets.py.
class BrandColors {
  const BrandColors._();

  /// Page background (Cal AI: #FFFFFF).
  static const Color paper = Color(0xFFFFFFFF);

  /// Cards and sheets.
  static const Color card = Color(0xFFFFFFFF);

  /// Text, rings, icons and primary buttons (Cal AI: #1E1A22).
  static const Color ink = Color(0xFF1E1A22);

  /// Secondary text, "Calories eaten". Cal AI uses #808080 (3.95:1 on white);
  /// #767676 is the nearest grey that reads at WCAG AA (4.54:1).
  static const Color muted = Color(0xFF767676);

  /// Tertiary text, placeholders, chevrons, the disabled button
  /// (Cal AI: #AFAEB3).
  static const Color faint = Color(0xFFAFAEB3);

  /// Ring tracks, separators, progress tracks (Cal AI: #EBEAF1).
  static const Color hairline = Color(0xFFEBEAF1);

  /// Option cards, list rows, text fields (Cal AI: #F6F5FC / #F9F8FD).
  static const Color fill = Color(0xFFF6F5FC);

  /// List rows ("Recently uploaded").
  static const Color row = Color(0xFFF9F8FD);

  /// The selected tab's pill (Cal AI: #ECECEC).
  static const Color tabPill = Color(0xFFECECEC);

  /// Cal AI's three accent colours: the protein / carbs / fats rings and
  /// their small icons (calories stay ink). Owned uses them, in this order,
  /// for the three small cards under every big one.
  static const Color accentRed = Color(0xFFE5675E);
  static const Color accentOrange = Color(0xFFE39A5B);
  static const Color accentBlue = Color(0xFF5F8FE2);
  static const List<Color> accents = <Color>[accentRed, accentOrange, accentBlue];

  /// The soft shadow under white cards on white.
  static const List<BoxShadow> cardShadow = <BoxShadow>[
    BoxShadow(color: Color(0x0F1E1A22), blurRadius: 24.0, offset: Offset(0.0, 6.0)),
    BoxShadow(color: Color(0x081E1A22), blurRadius: 4.0, offset: Offset(0.0, 1.0)),
  ];

  // Former brand names, mapped onto the palette so older screens follow.
  static const Color indigo = ink;
  static const Color indigoBright = Color(0xFF2E2A33);
  static const Color inkDeep = Color(0xFF000000);
  static const Color gold = ink;
  static const Color tint = fill;

  /// The faint wash at the top of the home page (Cal AI's, without its hue).
  static const LinearGradient hero = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0xFFF4F3F7), paper],
  );

  // Dark mode: the same idea inverted.
  static const Color paperDark = Color(0xFF0E0D10);
  static const Color cardDark = Color(0xFF1C1B1F);
  static const Color hairlineDark = Color(0xFF2C2B30);
  static const Color fillDark = Color(0xFF232227);
  static const Color mutedDark = Color(0xFF9A999E);
}
