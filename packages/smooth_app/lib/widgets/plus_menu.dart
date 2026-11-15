import 'package:flutter/material.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/smooth_navigation_bar.dart';

class PlusMenuAction {
  const PlusMenuAction({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

/// What Cal AI's + opens: the page dims and white tiles in a 2x2 grid
/// rise above the tab bar, one after the other. A tap outside closes it.
class PlusMenu extends StatelessWidget {
  const PlusMenu({required this.open, required this.onClose, required this.actions, super.key});

  final bool open;
  final VoidCallback onClose;
  final List<PlusMenuAction> actions;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final double bottom =
        MediaQuery.viewPaddingOf(context).bottom + SmoothNavigationBar.reserved + 12.0;
    return IgnorePointer(
      ignoring: !open,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: GestureDetector(
              onTap: onClose,
              child: AnimatedOpacity(
                opacity: open ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: const ColoredBox(color: Color(0x3D000000)),
              ),
            ),
          ),
          Positioned(
            left: 20.0,
            right: 20.0,
            bottom: bottom,
            child: GridView.count(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 12.0,
              crossAxisSpacing: 12.0,
              childAspectRatio: 1.45,
              children: <Widget>[
                for (int i = 0; i < actions.length; i++)
                  AnimatedSlide(
                    offset: open ? Offset.zero : const Offset(0.0, 0.25),
                    duration: Duration(milliseconds: 240 + 40 * i),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: open ? 1.0 : 0.0,
                      duration: Duration(milliseconds: 160 + 40 * i),
                      child: PressScale(
                        onTap: () {
                          onClose();
                          actions[i].onTap();
                        },
                        child: Semantics(
                          button: true,
                          label: actions[i].label,
                          excludeSemantics: true,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: dark ? BrandColors.cardDark : Colors.white,
                              borderRadius: BorderRadius.circular(22.0),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                Icon(actions[i].icon, size: 30.0, color: theme.colorScheme.onSurface),
                                const SizedBox(height: 10.0),
                                Text(actions[i].label, style: theme.textTheme.titleSmall),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
