import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';

/// Cal AI's tab bar: a floating white capsule with a soft shadow, the
/// selected tab on a grey pill that slides to the tapped tab, and the
/// black round + button beside it. Sizes measured on Cal AI's App Store
/// screenshot (research/ui/CALAI.md): capsule 62 pt high, 21 pt from the
/// screen edges, + 62 pt, 14 pt apart; SF-style line icons that fill when
/// selected, 11 pt labels. Changing tab ticks ([Haptics.select]).
class SmoothNavigationBar extends StatelessWidget {
  const SmoothNavigationBar({
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    this.onPlus,
    this.plusOpen = false,
    super.key,
  }) : assert(selectedIndex >= 0 && selectedIndex < destinations.length);

  /// Index in [destinations], hidden ones included.
  final int selectedIndex;
  final Iterable<SmoothNavigationDestination> destinations;
  final ValueChanged<int> onDestinationSelected;

  /// The + button; hidden when null.
  final VoidCallback? onPlus;

  /// The + menu is open: the + turns into a ×.
  final bool plusOpen;

  static const double barHeight = 62.0;

  /// Room the bar takes at the bottom of the screen, safe area excluded.
  static const double reserved = barHeight + 14.0;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final List<(int, SmoothNavigationDestination)> shown = <(int, SmoothNavigationDestination)>[
      for (int i = 0; i < destinations.length; i++)
        if (destinations.elementAt(i).visible) (i, destinations.elementAt(i)),
    ];
    final int selectedSlot = math.max(
      0,
      shown.indexWhere(((int, SmoothNavigationDestination) e) => e.$1 == selectedIndex),
    );
    final double bottom = math.max(10.0, MediaQuery.viewPaddingOf(context).bottom - 10.0);
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(21.0, 0.0, 21.0, bottom),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              height: barHeight,
              padding: const EdgeInsetsDirectional.all(5.0),
              decoration: BoxDecoration(
                color: dark ? BrandColors.cardDark : Colors.white,
                borderRadius: BorderRadius.circular(barHeight / 2),
                border: Border.all(color: dark ? BrandColors.hairlineDark : const Color(0xFFF3F2F7)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(color: Color(0x121E1A22), blurRadius: 30.0, offset: Offset(0.0, 10.0)),
                  BoxShadow(color: Color(0x081E1A22), blurRadius: 3.0, offset: Offset(0.0, 1.0)),
                ],
              ),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints c) {
                  final double w = c.maxWidth / shown.length;
                  return Stack(
                    children: <Widget>[
                      AnimatedPositionedDirectional(
                        duration: const Duration(milliseconds: 340),
                        curve: Curves.easeOutBack,
                        start: w * selectedSlot,
                        top: 0.0,
                        bottom: 0.0,
                        width: w,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: dark ? BrandColors.fillDark : BrandColors.tabPill,
                            borderRadius: BorderRadius.circular(barHeight / 2),
                          ),
                        ),
                      ),
                      Row(
                        children: <Widget>[
                          for (int slot = 0; slot < shown.length; slot++)
                            Expanded(
                              child: _Item(
                                destination: shown[slot].$2,
                                selected: slot == selectedSlot,
                                onTap: () {
                                  if (slot != selectedSlot) {
                                    Haptics.select();
                                  }
                                  onDestinationSelected(shown[slot].$1);
                                },
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          if (onPlus != null) ...<Widget>[
            const SizedBox(width: 14.0),
            PlusButton(onTap: onPlus!, open: plusOpen, size: barHeight),
          ],
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.destination, required this.selected, required this.onTap});

  final SmoothNavigationDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color color = selected
        ? theme.colorScheme.onSurface
        : (dark ? BrandColors.mutedDark : const Color(0xFF8E8E93));
    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      excludeSemantics: true,
      child: PressScale(
        onTap: onTap,
        scale: 0.9,
        haptic: false,
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: color),
          duration: const Duration(milliseconds: 200),
          builder: (BuildContext context, Color? c, _) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (Widget child, Animation<double> a) => ScaleTransition(
                  scale: Tween<double>(begin: 0.8, end: 1.0).animate(a),
                  child: FadeTransition(opacity: a, child: child),
                ),
                child: IconTheme(
                  key: ValueKey<bool>(selected),
                  data: IconThemeData(color: c, size: 22.0),
                  child: selected ? (destination.selectedIcon ?? destination.icon) : destination.icon,
                ),
              ),
              const SizedBox(height: 3.0),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontFamily: 'CupertinoSystemText',
                  fontFamilyFallback: const <String>['Inter'],
                  color: c,
                  fontSize: 11.0,
                  letterSpacing: 0.07,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The black round + of Cal AI. Turns 45° into a × while its menu is open.
class PlusButton extends StatelessWidget {
  const PlusButton({required this.onTap, this.open = false, this.size = 62.0, super.key});

  final VoidCallback onTap;
  final bool open;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      button: true,
      label: open ? 'Close' : 'Scan a product',
      excludeSemantics: true,
      child: PressScale(
        onTap: onTap,
        scale: 0.9,
        feedback: open ? Haptics.tap : Haptics.open,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            shape: BoxShape.circle,
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Color(0x2E1E1A22), blurRadius: 20.0, offset: Offset(0.0, 8.0)),
            ],
          ),
          child: AnimatedRotation(
            turns: open ? 0.125 : 0.0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: CustomPaint(
              size: Size.square(size),
              painter: _PlusPainter(color: theme.colorScheme.onPrimary, arm: size * 0.17, stroke: 2.6),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cal AI's thin plus: two round-ended strokes.
class _PlusPainter extends CustomPainter {
  _PlusPainter({required this.color, required this.arm, required this.stroke});

  final Color color;
  final double arm;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c.translate(-arm, 0), c.translate(arm, 0), p);
    canvas.drawLine(c.translate(0, -arm), c.translate(0, arm), p);
  }

  @override
  bool shouldRepaint(_PlusPainter old) => old.color != color || old.arm != arm || old.stroke != stroke;
}

class SmoothNavigationDestination {
  const SmoothNavigationDestination({
    required this.icon,
    required this.label,
    this.selectedIcon,
    this.visible = true,
  });

  final Widget icon;
  final Widget? selectedIcon;
  final String label;
  final bool visible;
}
