import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Owned's scan line (17/11 2026): one thin white line with soft ends and a
/// glow, and a faint wash trailing behind it. The same line as the photo
/// being read ([ScanningOverlay] on the answer page), so the home scanner,
/// the camera and a photo row all scan the same way.
///
/// [pingPong] moves it down and back up like a handheld scanner; otherwise
/// it runs top to bottom and fades at the ends. Reduced motion hides it.
class ScanSweep extends StatefulWidget {
  const ScanSweep({
    this.color = Colors.white,
    this.period = const Duration(milliseconds: 1700),
    this.pingPong = false,
    this.thickness = 3.0,
    this.inset = 0.0,
    this.trail = 0.35,
    this.glow = 14.0,
    this.active = true,
    super.key,
  });

  final Color color;

  /// One pass (one way when [pingPong]).
  final Duration period;
  final bool pingPong;
  final double thickness;

  /// Space left and right of the line.
  final double inset;

  /// The wash behind the line, as a share of the height.
  final double trail;

  /// The glow's blur radius.
  final double glow;

  /// False stops and hides the line (a scan finished).
  final bool active;

  @override
  State<ScanSweep> createState() => _ScanSweepState();
}

class _ScanSweepState extends State<ScanSweep> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ScanSweep old) {
    super.didUpdateWidget(old);
    if (old.period != widget.period) {
      _c.duration = widget.period;
    }
    if (old.active != widget.active || old.pingPong != widget.pingPong) {
      _c.stop();
      _sync();
    }
  }

  void _sync() {
    final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!widget.active || still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: widget.pingPong);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!widget.active || still) {
      return const SizedBox.expand();
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (BuildContext context, _) => CustomPaint(
            size: Size.infinite,
            painter: ScanSweepPainter(
              t: _c.value,
              down: !widget.pingPong || _c.status != AnimationStatus.reverse,
              fadeEnds: !widget.pingPong,
              color: widget.color,
              thickness: widget.thickness,
              inset: widget.inset,
              trail: widget.trail,
              glow: widget.glow,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints the line at [t] (0 top, 1 bottom) with its wash behind it.
class ScanSweepPainter extends CustomPainter {
  ScanSweepPainter({
    required this.t,
    required this.down,
    required this.color,
    this.fadeEnds = true,
    this.thickness = 3.0,
    this.inset = 0.0,
    this.trail = 0.35,
    this.glow = 14.0,
  });

  final double t;

  /// Moving down (the wash is above the line) or up (below).
  final bool down;
  final bool fadeEnds;
  final Color color;
  final double thickness;
  final double inset;
  final double trail;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final double eased = Curves.easeInOutSine.transform(t.clamp(0.0, 1.0));
    final double y = thickness / 2 + (size.height - thickness) * eased;
    final double fade = !fadeEnds
        ? 1.0
        : t < 0.08
        ? t / 0.08
        : t > 0.92
        ? (1.0 - t) / 0.08
        : 1.0;
    if (fade <= 0.0) {
      return;
    }
    final double a = color.a;
    final double washH = math.min(size.height * trail, down ? y : size.height - y);
    if (washH > 1.0) {
      final Rect wash = down
          ? Rect.fromLTRB(0.0, y - washH, size.width, y)
          : Rect.fromLTRB(0.0, y, size.width, y + washH);
      // Soft on every side: the vertical fade, then the same soft ends as
      // the line (no hard-edged box over the photo).
      canvas.saveLayer(wash, Paint());
      canvas.drawRect(
        wash,
        Paint()
          ..shader = LinearGradient(
            begin: down ? Alignment.topCenter : Alignment.bottomCenter,
            end: down ? Alignment.bottomCenter : Alignment.topCenter,
            colors: <Color>[color.withValues(alpha: 0.0), color.withValues(alpha: a * 0.16 * fade)],
          ).createShader(wash),
      );
      canvas.drawRect(
        wash,
        Paint()
          ..blendMode = BlendMode.dstIn
          ..shader = const LinearGradient(
            colors: <Color>[Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
            stops: <double>[0.0, 0.25, 0.75, 1.0],
          ).createShader(wash),
      );
      canvas.restore();
    }
    final Rect line = Rect.fromLTRB(inset, y - thickness / 2, size.width - inset, y + thickness / 2);
    final Shader ends = LinearGradient(
      colors: <Color>[
        color.withValues(alpha: 0.0),
        color.withValues(alpha: a * fade),
        color.withValues(alpha: a * fade),
        color.withValues(alpha: 0.0),
      ],
      stops: const <double>[0.0, 0.18, 0.82, 1.0],
    ).createShader(line);
    if (glow > 0.0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(line.inflate(1.0), Radius.circular(thickness)),
        Paint()
          ..shader = ends
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, glow / 2),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(line, Radius.circular(thickness / 2)),
      Paint()..shader = ends,
    );
  }

  @override
  bool shouldRepaint(ScanSweepPainter old) =>
      old.t != t ||
      old.down != down ||
      old.color != color ||
      old.thickness != thickness ||
      old.inset != inset ||
      old.trail != trail ||
      old.glow != glow ||
      old.fadeEnds != fadeEnds;
}

/// Rounded white corner brackets (the camera's frame, small).
class ScanCornersPainter extends CustomPainter {
  ScanCornersPainter({
    this.color = Colors.white,
    this.stroke = 3.0,
    this.radius = 14.0,
    this.corner = 0.28,
  });

  final Color color;
  final double stroke;
  final double radius;

  /// Each corner's arm, as a share of the shorter side.
  final double corner;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect r = (Offset.zero & size).deflate(stroke / 2);
    final double c = size.shortestSide * corner;
    final double rad = math.min(radius, c - 1.0);
    final Path p = Path()
      ..moveTo(r.left, r.top + c)
      ..lineTo(r.left, r.top + rad)
      ..arcToPoint(Offset(r.left + rad, r.top), radius: Radius.circular(rad))
      ..lineTo(r.left + c, r.top)
      ..moveTo(r.right - c, r.top)
      ..lineTo(r.right - rad, r.top)
      ..arcToPoint(Offset(r.right, r.top + rad), radius: Radius.circular(rad))
      ..lineTo(r.right, r.top + c)
      ..moveTo(r.right, r.bottom - c)
      ..lineTo(r.right, r.bottom - rad)
      ..arcToPoint(Offset(r.right - rad, r.bottom), radius: Radius.circular(rad))
      ..lineTo(r.right - c, r.bottom)
      ..moveTo(r.left + c, r.bottom)
      ..lineTo(r.left + rad, r.bottom)
      ..arcToPoint(Offset(r.left, r.bottom - rad), radius: Radius.circular(rad))
      ..lineTo(r.left, r.bottom - c);
    canvas.drawPath(
      p,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(ScanCornersPainter old) =>
      old.color != color || old.stroke != stroke || old.radius != radius || old.corner != corner;
}
