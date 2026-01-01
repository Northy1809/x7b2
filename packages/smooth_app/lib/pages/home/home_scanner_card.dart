import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/pages/scan/scan_page.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/scan_sweep.dart';

/// The scanner at the top of the home page (17/11 2026): one ink card, the
/// app's primary action, as the black + is in Cal AI. A small viewfinder on
/// the right scans a barcode with the same white line as the camera, so the
/// card shows what it does before it is tapped. A tap opens the camera.
class HomeScannerCard extends StatelessWidget {
  const HomeScannerCard({this.onOpen, super.key});

  /// For tests; opens the camera when null.
  final VoidCallback? onOpen;

  static const double height = 164.0;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    const TextStyle base = TextStyle(
      fontFamily: 'CupertinoSystemText',
      fontFamilyFallback: <String>['Inter'],
      color: Colors.white,
    );
    // The card has a fixed height: large text grows it only so far.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: Semantics(
        button: true,
        label: 'Scan a product. Opens the camera',
        excludeSemantics: true,
        child: PressScale(
          scale: 0.97,
          feedback: Haptics.open,
          onTap: onOpen ?? () => ScanPage.open(context),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24.0),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: dark
                    ? const <Color>[Color(0xFF2A2830), BrandColors.cardDark]
                    : const <Color>[Color(0xFF34303A), BrandColors.ink],
              ),
              border: dark ? Border.all(color: BrandColors.hairlineDark) : null,
              boxShadow: dark
                  ? null
                  : const <BoxShadow>[
                      BoxShadow(color: Color(0x2E1E1A22), blurRadius: 26.0, offset: Offset(0.0, 12.0)),
                      BoxShadow(color: Color(0x141E1A22), blurRadius: 4.0, offset: Offset(0.0, 1.0)),
                    ],
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(20.0, 18.0, 16.0, 18.0),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const _LiveDot(),
                          const SizedBox(width: 7.0),
                          Text(
                            'Scanner',
                            textScaler: TextScaler.noScaling,
                            style: base.copyWith(
                              fontSize: 13.0,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.62),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8.0),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          'Scan a product',
                          maxLines: 1,
                          style: base.copyWith(
                            fontFamily: 'CupertinoSystemDisplay',
                            fontSize: 24.0,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.6,
                            height: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        'See who really owns it.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: base.copyWith(fontSize: 14.0, color: Colors.white.withValues(alpha: 0.72)),
                      ),
                      const Spacer(),
                      Container(
                        height: 36.0,
                        padding: const EdgeInsetsDirectional.fromSTEB(12.0, 0.0, 15.0, 0.0),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18.0)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Icon(CupertinoIcons.viewfinder, size: 17.0, color: BrandColors.ink),
                            const SizedBox(width: 7.0),
                            Flexible(
                              child: Text(
                                'Open camera',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textScaler: TextScaler.noScaling,
                                style: base.copyWith(
                                  fontSize: 15.0,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                  color: BrandColors.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14.0),
                const _Viewfinder(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The little viewfinder: white corners round a barcode, scanned up and
/// down by the line.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 112.0,
    height: 128.0,
    child: Stack(
      fit: StackFit.expand,
      children: <Widget>[
        CustomPaint(painter: ScanCornersPainter(stroke: 3.5, radius: 14.0, corner: 0.26)),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(22.0, 30.0, 22.0, 30.0),
          child: CustomPaint(painter: _BarcodePainter(color: Colors.white.withValues(alpha: 0.5))),
        ),
        const Padding(
          padding: EdgeInsetsDirectional.symmetric(horizontal: 6.0, vertical: 14.0),
          child: ScanSweep(
            pingPong: true,
            period: Duration(milliseconds: 1500),
            thickness: 2.5,
            inset: 4.0,
            trail: 0.3,
            glow: 10.0,
          ),
        ),
      ],
    ),
  );
}

/// Bars of a barcode (a fixed, made-up pattern).
class _BarcodePainter extends CustomPainter {
  _BarcodePainter({required this.color});

  final Color color;

  static const List<int> _bars = <int>[3, 1, 2, 1, 1, 3, 1, 2, 2, 1, 3, 1, 1, 2, 1, 3, 2, 1, 1, 2, 3, 1];

  @override
  void paint(Canvas canvas, Size size) {
    final int units = _bars.fold(0, (int a, int b) => a + b) + _bars.length - 1;
    final double u = size.width / units;
    final Paint p = Paint()..color = color;
    double x = 0.0;
    for (int i = 0; i < _bars.length; i++) {
      final double w = _bars[i] * u;
      if (i.isEven) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, 0.0, w, size.height), Radius.circular(u * 0.4)), p);
      }
      x += w + u;
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter old) => old.color != color;
}

/// A small dot that breathes: the scanner is ready.
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (CalMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: 0.45, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
    child: Container(
      width: 7.0,
      height: 7.0,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
    ),
  );
}
