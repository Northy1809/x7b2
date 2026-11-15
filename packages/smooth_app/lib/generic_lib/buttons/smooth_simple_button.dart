import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/themes/theme_provider.dart';

/// A flat, chunky button with the "3D press" feel used by apps like
/// Duolingo: a solid darker-shade ledge sits under the face, and the face
/// drops onto it on press, instead of a Material drop shadow that blurs and
/// lifts. This is the app's shared button primitive — [SmoothLargeButtonWithIcon]
/// and every other caller of [SmoothSimpleButton] pick this up automatically.
/// Frej asked for the whole app to read this way (2026-10-24); see
/// `projects/ejerskab-app/BRIEF.md`.
class SmoothSimpleButton extends StatefulWidget {
  const SmoothSimpleButton({
    required this.child,
    required this.onPressed,
    this.minWidth = 15.0,
    this.height = 20.0,
    this.borderRadius,
    this.padding = const EdgeInsetsDirectional.all(BALANCED_SPACE),
    this.buttonColor,
    this.elevation,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final double minWidth;

  /// A floor, not a fixed height — multi-line content (e.g.
  /// [SmoothLargeButtonWithIcon]'s up-to-3-line label) still grows past it.
  final double height;
  final BorderRadiusGeometry? borderRadius;
  final EdgeInsetsGeometry padding;
  final Color? buttonColor;

  /// No longer used — the button is flat by design now — but kept so
  /// existing call sites that pass it don't have to change.
  final WidgetStateProperty<double?>? elevation;

  @override
  State<SmoothSimpleButton> createState() => _SmoothSimpleButtonState();
}

class _SmoothSimpleButtonState extends State<SmoothSimpleButton> {
  /// How far the face drops onto the ledge when pressed.
  static const double _ledgeDepth = 4.0;
  static const Duration _pressDuration = Duration(milliseconds: 90);

  bool _pressed = false;

  bool get _enabled => widget.onPressed != null;

  void _setPressed(final bool value) {
    if (_enabled && _pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData themeData = Theme.of(context);
    final bool isAmoled = context.read<ThemeProvider>().isAmoledTheme;
    final BorderRadius radius = (widget.borderRadius ?? ROUNDED_BORDER_RADIUS)
        .resolve(Directionality.of(context));

    final Color faceColor =
        widget.buttonColor ??
        (_enabled ? themeData.colorScheme.primary : Colors.grey);
    // A flat single tone (no visible ledge) is the disabled button's own
    // "inert" cue, and keeps its footprint identical to the enabled state so
    // a button that toggles enabled/disabled (e.g. once text is typed into a
    // field) doesn't jump in height when it does.
    final Color ledgeColor = _enabled
        ? HSLColor.fromColor(faceColor)
              .withLightness(
                (HSLColor.fromColor(faceColor).lightness - 0.16).clamp(
                  0.0,
                  1.0,
                ),
              )
              .toColor()
        : faceColor;

    // `ElevatedButton` used to supply this by default (via the app's global
    // `elevatedButtonTheme`) to any plain `Text`/`Icon` child that didn't set
    // its own color — several callers rely on exactly that (e.g.
    // `smooth_error_card.dart`'s buttons). Replicate it explicitly now that
    // this widget no longer wraps an `ElevatedButton`.
    final Color defaultForeground = _enabled
        ? themeData.colorScheme.onPrimary
        : Colors.white;

    return Semantics(
      button: true,
      enabled: _enabled,
      onTap: widget.onPressed,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: widget.minWidth),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTapDown: _enabled ? (_) => _setPressed(true) : null,
          onTapCancel: _enabled ? () => _setPressed(false) : null,
          onTapUp: _enabled ? (_) => _setPressed(false) : null,
          onTap: _enabled
              ? () {
                  HapticFeedback.selectionClick();
                  widget.onPressed!();
                }
              : null,
          child: DecoratedBox(
            decoration: BoxDecoration(color: ledgeColor, borderRadius: radius),
            child: AnimatedContainer(
              duration: _pressDuration,
              curve: Curves.easeOut,
              margin: EdgeInsetsDirectional.only(
                bottom: _pressed ? 0 : _ledgeDepth,
              ),
              constraints: BoxConstraints(minHeight: widget.height),
              decoration: BoxDecoration(
                color: faceColor,
                borderRadius: radius,
                border: isAmoled
                    ? Border.all(color: Colors.white, width: 2)
                    : null,
              ),
              child: Padding(
                padding: widget.padding,
                child: Center(
                  child: IconTheme.merge(
                    data: IconThemeData(color: defaultForeground),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: defaultForeground),
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
