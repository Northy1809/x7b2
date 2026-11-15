import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/themes/brand_colors.dart';

/// Cal AI's building blocks, measured from its screenshots and a 30 fps
/// screen recording (research/ui/CALAI.md):
/// - things shrink a little while pressed, no ripple ([PressScale]);
/// - a choice turns ink in 100 ms ([CalOption]);
/// - new rows fade in and rise, one after the other ([FadeUpIn]);
/// - scores and goals are ink arcs with round ends on a #EBEAF1 track that
///   draw themselves in ([CalRing]);
/// - white cards with a soft shadow ([CalCard]).

/// Durations and curves from the recording.
class CalMotion {
  const CalMotion._();

  /// A choice turning ink, a button turning on.
  static const Duration select = Duration(milliseconds: 100);

  /// A press going down.
  static const Duration pressIn = Duration(milliseconds: 90);

  /// A press coming back.
  static const Duration pressOut = Duration(milliseconds: 160);

  /// One row of a list coming in.
  static const Duration enter = Duration(milliseconds: 320);

  /// Gap between rows coming in.
  static const Duration stagger = Duration(milliseconds: 70);

  /// A page cross-fading to the next.
  static const Duration page = Duration(milliseconds: 220);

  /// A ring or a number filling up.
  static const Duration fill = Duration(milliseconds: 900);

  static const Curve curve = Curves.easeOutCubic;

  static bool reduced(final BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Shrinks its child to [scale] while a finger is down, and springs back.
/// Taps go to [onTap]; a haptic marks the press ([feedback], light by
/// default; see [Haptics]).
class PressScale extends StatefulWidget {
  const PressScale({
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.96,
    this.haptic = true,
    this.feedback,
    this.behavior = HitTestBehavior.opaque,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;

  /// The vibration for a tap; [Haptics.tap] when null.
  final VoidCallback? feedback;
  final HitTestBehavior behavior;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(final bool down) {
    if (_down != down && mounted) {
      setState(() => _down = down);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) {
                (widget.feedback ?? Haptics.tap)();
              }
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              _set(false);
              Haptics.open();
              widget.onLongPress!();
            },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: _down ? CalMotion.pressIn : CalMotion.pressOut,
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// Fades its child in while it rises [offset] points, after [index] times
/// [CalMotion.stagger]: the way Cal AI's lists and choices arrive.
class FadeUpIn extends StatefulWidget {
  const FadeUpIn({
    required this.child,
    this.index = 0,
    this.offset = 14.0,
    super.key,
  });

  final Widget child;
  final int index;
  final double offset;

  @override
  State<FadeUpIn> createState() => _FadeUpInState();
}

class _FadeUpInState extends State<FadeUpIn> with SingleTickerProviderStateMixin {
  // One controller from the first frame: the wait for the row's turn is
  // the start of an Interval, so the timing is exact.
  late final Duration _delay = CalMotion.stagger * widget.index.clamp(0, 12);
  late final AnimationController _c = AnimationController(vsync: this, duration: _delay + CalMotion.enter)
    ..forward();
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(
      _delay.inMicroseconds / (_delay + CalMotion.enter).inMicroseconds,
      1.0,
      curve: CalMotion.curve,
    ),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (CalMotion.reduced(context)) {
      _c.value = 1.0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    builder: (BuildContext context, Widget? child) => Opacity(
      opacity: _t.value,
      child: Transform.translate(offset: Offset(0.0, widget.offset * (1.0 - _t.value)), child: child),
    ),
    child: widget.child,
  );
}

/// White card with Cal AI's soft shadow and 20 pt corners.
class CalCard extends StatelessWidget {
  const CalCard({
    required this.child,
    this.padding = const EdgeInsetsDirectional.all(16.0),
    this.radius = 20.0,
    this.onTap,
    this.color,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? (dark ? BrandColors.cardDark : BrandColors.card),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: dark ? BrandColors.hairlineDark : const Color(0xFFF3F2F7)),
        boxShadow: dark ? null : BrandColors.cardShadow,
      ),
      child: Padding(padding: padding, child: child),
    );
    return onTap == null ? card : PressScale(onTap: onTap, child: card);
  }
}

/// Grey rounded row (Cal AI's "Recently uploaded" rows and onboarding
/// choices). [selected] turns it ink with white text in 100 ms.
class CalOption extends StatelessWidget {
  const CalOption({
    required this.child,
    this.selected = false,
    this.onTap,
    this.padding = const EdgeInsetsDirectional.symmetric(horizontal: 18.0, vertical: 16.0),
    this.radius = 16.0,
    super.key,
  });

  final Widget child;
  final bool selected;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color back = selected
        ? theme.colorScheme.primary
        : (dark ? BrandColors.fillDark : BrandColors.fill);
    final Color fore = selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    return PressScale(
      onTap: onTap,
      feedback: Haptics.select,
      child: AnimatedContainer(
        duration: CalMotion.select,
        curve: Curves.easeOut,
        padding: padding,
        decoration: BoxDecoration(color: back, borderRadius: BorderRadius.circular(radius)),
        child: AnimatedDefaultTextStyle(
          duration: CalMotion.select,
          style: (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(color: fore),
          child: IconTheme.merge(data: IconThemeData(color: fore), child: child),
        ),
      ),
    );
  }
}

/// An ink arc with round ends on a light track, drawn in from 12 o'clock:
/// Cal AI's calorie and macro rings. [fraction] is 0-1; null draws the
/// empty track. [child] sits in the middle.
class CalRing extends StatelessWidget {
  const CalRing({
    required this.fraction,
    this.size = 96.0,
    this.stroke,
    this.child,
    this.color,
    super.key,
  });

  final double? fraction;
  final double size;
  final double? stroke;
  final Widget? child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color track = dark ? BrandColors.hairlineDark : BrandColors.hairline;
    final Color arc = color ?? theme.colorScheme.primary;
    final double w = stroke ?? math.max(5.0, size * 0.075);
    return SizedBox.square(
      dimension: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: (fraction ?? 0.0).clamp(0.0, 1.0)),
        duration: CalMotion.reduced(context) ? Duration.zero : CalMotion.fill,
        curve: CalMotion.curve,
        builder: (BuildContext context, double f, Widget? child) => CustomPaint(
          painter: CalRingPainter(fraction: f, color: arc, track: track, stroke: w),
          child: child,
        ),
        child: child == null ? null : Center(child: child),
      ),
    );
  }
}

class CalRingPainter extends CustomPainter {
  CalRingPainter({
    required this.fraction,
    required this.color,
    required this.track,
    required this.stroke,
  });

  final double fraction;
  final Color color;
  final Color track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    final double f = fraction.clamp(0.0, 1.0);
    if (f <= 0) {
      return;
    }
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * f,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(CalRingPainter old) =>
      old.fraction != fraction || old.color != color || old.track != track || old.stroke != stroke;
}

/// A number that counts up to [value] as its ring fills.
class CountUp extends StatelessWidget {
  const CountUp({required this.value, this.style, super.key});

  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween<double>(begin: 0.0, end: value.toDouble()),
    duration: CalMotion.reduced(context) ? Duration.zero : CalMotion.fill,
    curve: CalMotion.curve,
    builder: (BuildContext context, double v, _) => Text(
      v.round().toString(),
      style: style,
      textScaler: TextScaler.noScaling,
    ),
  );
}

/// "1250/2500": a big ink number with a small grey "/max" after it.
class BigOver extends StatelessWidget {
  const BigOver({
    required this.value,
    this.over,
    this.size = 44.0,
    this.countUp = true,
    super.key,
  });

  /// Null shows a dash.
  final int? value;
  final String? over;
  final double size;
  final bool countUp;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle big = TextStyle(
      fontFamily: 'CupertinoSystemDisplay',
      fontFamilyFallback: const <String>['Inter'],
      fontSize: size,
      height: 1.0,
      fontWeight: FontWeight.w700,
      letterSpacing: size >= 28 ? -0.5 : -0.2,
      color: value == null ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        if (value == null)
          Text('–', style: big, textScaler: TextScaler.noScaling)
        else if (countUp)
          CountUp(value: value!, style: big)
        else
          Text('$value', style: big, textScaler: TextScaler.noScaling),
        if (over != null)
          Text(
            over!,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontFamily: 'CupertinoSystemText',
              fontFamilyFallback: const <String>['Inter'],
              fontSize: math.max(13.0, size * 0.42),
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// Cal AI's page dots under the swipeable cards: the current page is an ink
/// dot, the others hollow; the change takes [CalMotion.select].
class CalPageDots extends StatelessWidget {
  const CalPageDots({required this.count, required this.index, super.key});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    return Semantics(
      label: 'Page ${index + 1} of $count',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < count; i++)
            AnimatedContainer(
              duration: CalMotion.page,
              curve: CalMotion.curve,
              margin: const EdgeInsetsDirectional.symmetric(horizontal: 3.0),
              width: 6.0,
              height: 6.0,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == index ? theme.colorScheme.onSurface : Colors.transparent,
                border: Border.all(
                  color: i == index
                      ? theme.colorScheme.onSurface
                      : (dark ? BrandColors.mutedDark : BrandColors.faint),
                  width: 1.0,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
