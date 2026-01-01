import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:smooth_app/themes/brand_colors.dart';

/// Owned's logo mark (17/11 2026): the four rounded corners of the scan
/// frame around an open ring with a dot in the middle. The ring is the "O"
/// of Owned and the scores' rings; the gap at the top right and the dot
/// make it an eye looking into the product.
///
/// One geometry, in a 1024 box, shared with tools/brand/make_brand_assets.py
/// (the app icon, launch screen and SVGs). Keep the two in sync.
class OwnedMarkGeometry {
  const OwnedMarkGeometry._();

  /// The scan frame's corners.
  static const double frameMin = 200.0;
  static const double frameMax = 824.0;
  static const double cornerLength = 150.0;
  static const double cornerRadius = 90.0;
  static const double frameStroke = 58.0;

  /// The ring.
  static const double ringRadius = 138.0;
  static const double ringStroke = 78.0;

  /// The gap in the ring, centred at the top right (degrees).
  static const double gapCentre = -45.0;
  static const double gap = 64.0;

  /// The dot in the middle.
  static const double dotRadius = 46.0;
}

/// What the painter draws; every field at rest gives the static logo.
@immutable
class OwnedMarkPose {
  const OwnedMarkPose({
    this.frame = 1.0,
    this.frameOpacity = 1.0,
    this.ring = 1.0,
    this.spin = 0.0,
    this.dot = 1.0,
    this.scan,
    this.scanOpacity = 0.0,
  });

  /// The corners' scale around the centre (1 at rest; above 1 = further out).
  final double frame;
  final double frameOpacity;

  /// How much of the ring is drawn, 0-1.
  final double ring;

  /// The ring turned clockwise, in turns.
  final double spin;

  /// The dot's scale (0 hidden, 1 at rest).
  final double dot;

  /// The scan line between the top and bottom corners, 0-1; null hides it.
  final double? scan;
  final double scanOpacity;

  static const OwnedMarkPose rest = OwnedMarkPose();
}

class OwnedMarkPainter extends CustomPainter {
  OwnedMarkPainter({
    required this.color,
    this.pose = OwnedMarkPose.rest,
    this.zoom = 1.1,
  });

  final Color color;
  final OwnedMarkPose pose;

  /// The mark's scale inside its box: 1.1 fills it (the in-app SVGs),
  /// 0.62 is the launch screen's.
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final double unit = size.shortestSide / 1024.0;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(unit * zoom);
    canvas.translate(-512.0, -512.0);
    _frame(canvas);
    _ring(canvas);
    _dot(canvas);
    _scan(canvas);
    canvas.restore();
  }

  void _frame(final Canvas canvas) {
    if (pose.frameOpacity <= 0.0) {
      return;
    }
    const double a = OwnedMarkGeometry.frameMin;
    const double b = OwnedMarkGeometry.frameMax;
    const double l = OwnedMarkGeometry.cornerLength;
    const double r = OwnedMarkGeometry.cornerRadius;
    final Path p = Path()
      ..moveTo(a, a + l)
      ..lineTo(a, a + r)
      ..quadraticBezierTo(a, a, a + r, a)
      ..lineTo(a + l, a)
      ..moveTo(b - l, a)
      ..lineTo(b - r, a)
      ..quadraticBezierTo(b, a, b, a + r)
      ..lineTo(b, a + l)
      ..moveTo(b, b - l)
      ..lineTo(b, b - r)
      ..quadraticBezierTo(b, b, b - r, b)
      ..lineTo(b - l, b)
      ..moveTo(a + l, b)
      ..lineTo(a + r, b)
      ..quadraticBezierTo(a, b, a, b - r)
      ..lineTo(a, b - l);
    canvas.save();
    canvas.translate(512.0, 512.0);
    canvas.scale(pose.frame);
    canvas.translate(-512.0, -512.0);
    canvas.drawPath(
      p,
      Paint()
        ..color = color.withValues(alpha: color.a * pose.frameOpacity.clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = OwnedMarkGeometry.frameStroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  void _ring(final Canvas canvas) {
    final double f = pose.ring.clamp(0.0, 1.0);
    if (f <= 0.0) {
      return;
    }
    const double deg = math.pi / 180.0;
    const double start = (OwnedMarkGeometry.gapCentre + OwnedMarkGeometry.gap / 2) * deg;
    const double full = (360.0 - OwnedMarkGeometry.gap) * deg;
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(512.0, 512.0), radius: OwnedMarkGeometry.ringRadius),
      start + pose.spin * 2 * math.pi,
      full * f,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = OwnedMarkGeometry.ringStroke
        ..strokeCap = StrokeCap.round,
    );
  }

  void _dot(final Canvas canvas) {
    if (pose.dot <= 0.0) {
      return;
    }
    canvas.drawCircle(
      const Offset(512.0, 512.0),
      OwnedMarkGeometry.dotRadius * pose.dot,
      Paint()..color = color,
    );
  }

  void _scan(final Canvas canvas) {
    final double? s = pose.scan;
    if (s == null || pose.scanOpacity <= 0.0) {
      return;
    }
    const double top = OwnedMarkGeometry.frameMin + 40.0;
    const double bottom = OwnedMarkGeometry.frameMax - 40.0;
    final double y = top + (bottom - top) * s.clamp(0.0, 1.0);
    const double left = OwnedMarkGeometry.frameMin - 10.0;
    const double right = OwnedMarkGeometry.frameMax + 10.0;
    final double o = pose.scanOpacity.clamp(0.0, 1.0);
    final Rect band = Rect.fromLTRB(left, y - 9.0, right, y + 9.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(band, const Radius.circular(9.0)),
      Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            color.withValues(alpha: 0.0),
            color.withValues(alpha: 0.85 * o),
            color.withValues(alpha: 0.85 * o),
            color.withValues(alpha: 0.0),
          ],
          stops: const <double>[0.0, 0.2, 0.8, 1.0],
        ).createShader(band),
    );
  }

  @override
  bool shouldRepaint(OwnedMarkPainter old) => old.color != color || old.pose != pose || old.zoom != zoom;
}

/// How [OwnedMark] moves.
enum OwnedMarkMotion {
  /// The plain logo.
  none,

  /// Once: the corners close in like a camera focusing, the ring draws
  /// itself, the dot pops, a scan line passes. Then it rests.
  intro,

  /// The waiting state: the intro, then the ring keeps turning and a scan
  /// line keeps sweeping, slowly.
  loop,
}

/// The logo mark, still or moving. Reduced motion always shows it still.
class OwnedMark extends StatefulWidget {
  const OwnedMark({
    this.size = 40.0,
    this.color,
    this.motion = OwnedMarkMotion.none,
    this.zoom = 1.1,
    this.skipIntro = false,
    super.key,
  });

  final double size;

  /// Ink (or white in dark mode) when null.
  final Color? color;
  final OwnedMarkMotion motion;
  final double zoom;

  /// [OwnedMarkMotion.loop] starts from the finished logo (the launch screen
  /// shows it already).
  final bool skipIntro;

  /// Intro length.
  static const Duration intro = Duration(milliseconds: 1100);

  /// One loop.
  static const Duration cycle = Duration(milliseconds: 1600);

  /// The pose at [t] ms into the animation. Public for tests.
  static OwnedMarkPose poseAt(final double ms, {final bool loop = false, final bool skipIntro = false}) {
    final double introMs = skipIntro ? 0.0 : intro.inMilliseconds.toDouble();
    if (ms < introMs) {
      final double t = ms / introMs;
      double seg(final double from, final double to) => ((t - from) / (to - from)).clamp(0.0, 1.0);
      final double frameT = Curves.easeOutBack.transform(seg(0.0, 0.42));
      final double ringT = Curves.easeInOutCubic.transform(seg(0.18, 0.7));
      final double dotT = Curves.elasticOut.transform(seg(0.55, 1.0));
      final double scanT = seg(0.62, 1.0);
      return OwnedMarkPose(
        frame: 1.18 - 0.18 * frameT,
        frameOpacity: seg(0.0, 0.2),
        ring: ringT,
        spin: -0.25 * (1.0 - ringT),
        dot: dotT,
        scan: Curves.easeInOutSine.transform(scanT),
        scanOpacity: math.sin(math.pi * scanT),
      );
    }
    if (!loop) {
      return OwnedMarkPose.rest;
    }
    final double c = ((ms - introMs) % cycle.inMilliseconds) / cycle.inMilliseconds;
    final double sweep = Curves.easeInOutSine.transform(c);
    return OwnedMarkPose(
      spin: Curves.easeInOutCubic.transform(c),
      dot: 1.0 + 0.08 * math.sin(2 * math.pi * c),
      scan: sweep,
      scanOpacity: 0.55 * math.sin(math.pi * c),
    );
  }

  @override
  State<OwnedMark> createState() => _OwnedMarkState();
}

class _OwnedMarkState extends State<OwnedMark> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(days: 1));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(OwnedMark old) {
    super.didUpdateWidget(old);
    if (old.motion != widget.motion) {
      _c.value = 0.0;
      _sync();
    }
  }

  void _sync() {
    final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.motion == OwnedMarkMotion.none || still) {
      _c.stop();
      return;
    }
    if (!_c.isAnimating) {
      if (widget.motion == OwnedMarkMotion.intro) {
        _c.animateTo(OwnedMark.intro.inMilliseconds / const Duration(days: 1).inMilliseconds, duration: OwnedMark.intro);
      } else {
        _c.forward();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color =
        widget.color ?? (theme.brightness == Brightness.dark ? Colors.white : BrandColors.ink);
    final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final Widget mark = widget.motion == OwnedMarkMotion.none || still
        ? CustomPaint(painter: OwnedMarkPainter(color: color, zoom: widget.zoom))
        : AnimatedBuilder(
            animation: _c,
            builder: (BuildContext context, _) => CustomPaint(
              painter: OwnedMarkPainter(
                color: color,
                zoom: widget.zoom,
                pose: OwnedMark.poseAt(
                  _c.value * const Duration(days: 1).inMilliseconds,
                  loop: widget.motion == OwnedMarkMotion.loop,
                  skipIntro: widget.skipIntro,
                ),
              ),
            ),
          );
    return SizedBox.square(dimension: widget.size, child: RepaintBoundary(child: mark));
  }
}

/// The waiting screen: the moving logo, and a grey line under it.
class OwnedLoader extends StatelessWidget {
  const OwnedLoader({this.size = 56.0, this.label, this.color, super.key});

  final double size;
  final String? label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget mark = Semantics(
      label: label ?? 'Loading',
      excludeSemantics: true,
      child: OwnedMark(size: size, color: color, motion: OwnedMarkMotion.loop),
    );
    if (label == null) {
      return mark;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        mark,
        const SizedBox(height: 14.0),
        Text(
          label!,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15.0, color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// The launch screen drawn by Flutter while the app starts: the same paper,
/// mark, size and place as the native launch image
/// (ios/Runner/Assets.xcassets/LaunchImage, 288 pt at zoom 0.62), so the
/// hand-over cannot be seen, and then the mark comes alive.
class OwnedSplash extends StatelessWidget {
  const OwnedSplash({super.key});

  /// The native launch screen's paper and ink (tools/brand/make_brand_assets.py).
  static const Color paper = Color(0xFFF4F3F0);
  static const Color ink = Color(0xFF121212);

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: paper,
    child: Center(
      child: OwnedMark(size: 288.0, zoom: 0.62, color: ink, motion: OwnedMarkMotion.loop, skipIntro: true),
    ),
  );
}

/// Lays the app over [OwnedSplash] and fades the splash away once, so the
/// moving logo hands over to the first page softly.
class OwnedSplashHandoff extends StatefulWidget {
  const OwnedSplashHandoff({required this.child, super.key});

  final Widget child;

  @override
  State<OwnedSplashHandoff> createState() => _OwnedSplashHandoffState();
}

class _OwnedSplashHandoffState extends State<OwnedSplashHandoff> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.topLeft,
    fit: StackFit.expand,
    children: <Widget>[
      widget.child,
      AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, Widget? child) => _c.isCompleted
            ? const SizedBox.shrink()
            : IgnorePointer(
                child: Opacity(opacity: 1.0 - Curves.easeOut.transform(_c.value), child: child),
              ),
        child: const OwnedSplash(),
      ),
    ],
  );
}
