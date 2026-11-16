import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';

/// A 0-100 score as a ring with the number in the middle. A null score
/// draws an empty grey ring with a dash ("not rated").
class ScoreRing extends StatelessWidget {
  const ScoreRing({required this.score, this.size = 72.0, this.strokeWidth});

  final int? score;
  final double size;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Cal AI's ring: ink on #EBEAF1.
    final Color track = theme.brightness == Brightness.dark ? BrandColors.hairlineDark : BrandColors.hairline;
    final Color color = theme.colorScheme.onSurface;
    final double stroke = strokeWidth ?? size * 0.09;
    return Semantics(
      label: score == null ? 'No score' : 'Score $score out of 100',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        // The arc draws itself in once; no motion when the phone asks for less.
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: (score ?? 0) / 100),
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : CalMotion.fill,
          curve: Curves.easeOutCubic,
          builder: (BuildContext context, double fraction, Widget? child) => CustomPaint(
            painter: _RingPainter(fraction: fraction, color: color, track: track, stroke: stroke),
            child: child,
          ),
          child: Center(
            child: Text(
              score?.toString() ?? '–',
              // Sized to the ring, which does not grow with the text size;
              // screen readers get the label above.
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontFamily: 'CupertinoSystemDisplay',
                fontFamilyFallback: const <String>['Inter'],
                fontSize: size * 0.34,
                fontWeight: FontWeight.w700,
                color: score == null ? theme.colorScheme.outline : theme.colorScheme.onSurface,
                height: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
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
    final Paint base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, base);
    if (fraction <= 0) {
      return;
    }
    final Paint arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * fraction.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.track != track ||
      old.stroke != stroke;
}

/// Thin horizontal bar for a 0-100 sub-score.
class ScoreBar extends StatelessWidget {
  const ScoreBar({required this.score, this.height = 6.0, this.color});

  final int score;
  final double height;

  /// The filled part; ink when null.
  final Color? color;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height),
    child: LinearProgressIndicator(
      value: score / 100,
      minHeight: height,
      color: color ?? Theme.of(context).colorScheme.onSurface,
      backgroundColor: Theme.of(context).brightness == Brightness.dark ? BrandColors.hairlineDark : BrandColors.hairline,
    ),
  );
}
