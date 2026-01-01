import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:smooth_app/helpers/string_extension.dart';
import 'package:smooth_app/pages/scan/result/photo_result_page.dart';
import 'package:smooth_app/services/brand_text_matcher.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/pending_scans.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/scan_sweep.dart';

/// A photo being read, as Cal AI's meal row while it analyses: the photo
/// darkened with a ring and the percentage on it, what is happening, and
/// grey bars where the answer will be. When the answer is in, the row
/// turns into it.
class PendingScanRow extends StatelessWidget {
  const PendingScanRow({required this.scan, super.key});

  final PendingScan scan;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final BrandCandidate? brand = (scan.analysis?.brands.isEmpty ?? true) ? null : scan.analysis!.brands.first;
    return PressScale(
      onTap: scan.done ? () => _open(context) : null,
      child: Container(
        height: 118.0,
        decoration: BoxDecoration(
          color: dark ? BrandColors.fillDark : BrandColors.row,
          borderRadius: BorderRadius.circular(18.0),
          border: Border.all(color: dark ? BrandColors.hairlineDark : const Color(0xFFF1F0F6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: 116.0,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Image.file(
                    File(scan.imagePath),
                    fit: BoxFit.cover,
                    cacheWidth: 336,
                    errorBuilder: (_, _, _) =>
                        ColoredBox(color: dark ? BrandColors.hairlineDark : BrandColors.hairline),
                  ),
                  AnimatedOpacity(
                    opacity: scan.done ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 300),
                    child: ColoredBox(
                      color: const Color(0x73000000),
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          // 17/11: the photo is being read: the scan line
                          // runs over it, under the ring.
                          ScanSweep(
                            active: !scan.done,
                            period: const Duration(milliseconds: 1300),
                            thickness: 2.0,
                            glow: 8.0,
                            trail: 0.45,
                          ),
                          Center(
                            child: CalRing(
                              fraction: scan.progress,
                              size: 60.0,
                              stroke: 5.0,
                              color: Colors.white,
                              child: Text(
                                '${(scan.progress * 100).round()}%',
                                textScaler: TextScaler.noScaling,
                                style: const TextStyle(
                                  fontFamily: 'CupertinoSystemText',
                                  fontFamilyFallback: <String>['Inter'],
                                  color: Colors.white,
                                  fontSize: 14.0,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16.0, 12.0, 12.0, 12.0),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: CalMotion.curve,
                  child: !scan.done
                      ? _Working(step: scan.step, key: const ValueKey<int>(0))
                      : _Answer(scan: scan, brand: brand, key: const ValueKey<int>(1)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(final BuildContext context) async {
    final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
    // A barcode answer lands in the history once opened: no second row.
    if (scan.analysis?.barcode != null) {
      PendingScans.instance.remove(scan);
    }
    await navigator.push<void>(
      PhotoResultPage.route(imagePath: scan.imagePath, analysis: scan.failed ? null : scan.analysis),
    );
  }
}

class _Working extends StatelessWidget {
  const _Working({required this.step, super.key});

  final String step;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color bar = theme.brightness == Brightness.dark ? BrandColors.hairlineDark : BrandColors.hairline;
    Widget line(final double widthFactor, final double height) => FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        height: height,
        decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(height / 2)),
      ),
    );
    return Semantics(
      liveRegion: true,
      label: '$step…',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            '$step…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15.0, letterSpacing: -0.2),
          ),
          const SizedBox(height: 12.0),
          _Pulse(child: line(0.8, 10.0)),
          const SizedBox(height: 8.0),
          _Pulse(child: line(0.55, 10.0)),
        ],
      ),
    );
  }
}

/// Grey bars breathing while the answer is on its way.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.child});

  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: 0.45, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
    child: widget.child,
  );
}

class _Answer extends StatelessWidget {
  const _Answer({required this.scan, required this.brand, super.key});

  final PendingScan scan;
  final BrandCandidate? brand;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final BrandCandidate? b = brand;
    final String title = b?.name ?? (scan.analysis?.barcode != null ? 'Barcode found' : "Couldn't read this one");
    final String line =
        b?.owner.owner ?? (scan.analysis?.barcode != null ? 'Tap to see the owner' : 'Tap to try again');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Text(
                title.capFirst(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15.0, letterSpacing: -0.2),
              ),
            ),
            const SizedBox(width: 8.0),
            Text(
              'Now',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 13.0, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 5.0),
        Row(
          children: <Widget>[
            Icon(
              b == null ? CupertinoIcons.hand_point_right : CupertinoIcons.building_2_fill,
              size: 16.0,
              color: theme.colorScheme.onSurface,
            ),
            const SizedBox(width: 6.0),
            Expanded(
              child: Text(
                line.capFirst(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: b == null
                    ? theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)
                    : theme.textTheme.titleMedium?.copyWith(
                        fontSize: 18.0,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.4,
                      ),
              ),
            ),
          ],
        ),
        if (b != null) ...<Widget>[
          const SizedBox(height: 6.0),
          FutureBuilder<int?>(
            future: _moralOnce(b),
            builder: (BuildContext context, AsyncSnapshot<int?> s) => Row(
              children: <Widget>[
                Icon(Icons.balance_rounded, size: 14.0, color: theme.colorScheme.onSurface),
                const SizedBox(width: 4.0),
                Text(
                  s.data == null ? '–' : '${s.data}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 14.0,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// One lookup per owner: the row rebuilds every few frames while the
  /// ring fills, and a new future each time would blink the score to "–".
  static final Map<String, Future<int?>> _moralCache = <String, Future<int?>>{};

  static Future<int?> _moralOnce(final BrandCandidate b) => _moralCache.putIfAbsent(b.owner.owner, () => _moral(b));

  static Future<int?> _moral(final BrandCandidate b) async {
    try {
      final EthicsCompany? c = (await EthicsDb.load()).forOwner(b.owner.owner, chain: b.owner.ethicsChain);
      return c == null ? null : EthicsScore.compute(c).score;
    } catch (_) {
      return null;
    }
  }
}
