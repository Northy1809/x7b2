import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/generic_lib/widgets/owned_wordmark.dart';
import 'package:smooth_app/pages/product/product_page/overview/score_donut.dart';
import 'package:smooth_app/services/score_types.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/company_logo.dart';

/// Where the share sheet points from: required on iPad, ignored on phones.
Rect? shareOrigin(final BuildContext context) {
  final RenderObject? box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) {
    return null;
  }
  return box.localToGlobal(Offset.zero) & box.size;
}

/// What a share card shows.
class ShareCardData {
  const ShareCardData({required this.title, required this.text, this.owner, this.brand, this.health, this.ethics});

  final String title;
  final String? brand;

  /// Null on a company's own card.
  final String? owner;
  final int? health;
  final int? ethics;

  /// Sent with the picture (and alone, for "Share as text").
  final String text;
}

/// A preview of the share card with buttons to share it as a picture or as
/// text. The card is drawn by the app, so the picture looks the same
/// everywhere it is posted.
Future<void> showShareCard(final BuildContext context, final ShareCardData data) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (BuildContext context) => _ShareSheet(data: data),
);

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.data});

  final ShareCardData data;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final GlobalKey _card = GlobalKey();
  bool _busy = false;

  Future<void> _sharePicture() async {
    setState(() => _busy = true);
    final Rect? origin = shareOrigin(context);
    try {
      final RenderRepaintBoundary boundary = _card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) {
        throw StateError('no picture');
      }
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile.fromData(png.buffer.asUint8List(), mimeType: 'image/png', name: 'owned.png')],
          fileNameOverrides: const <String>['owned.png'],
          text: widget.data.text,
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      // The picture failed (rare): share the words instead.
      await _shareText();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _shareText() =>
      SharePlus.instance.share(ShareParams(text: widget.data.text, sharePositionOrigin: shareOrigin(context)));

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(LARGE_SPACE, 0, LARGE_SPACE, LARGE_SPACE),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          RepaintBoundary(
            key: _card,
            child: ShareCard(data: widget.data),
          ),
          const SizedBox(height: LARGE_SPACE),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _sharePicture,
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Share picture'),
            ),
          ),
          TextButton(onPressed: _busy ? null : _shareText, child: const Text('Share as text')),
        ],
      ),
    ),
  );
}

/// The card itself: the brand's ink gradient, the product, its owner with
/// the gold dot, and the two scores.
class ShareCard extends StatelessWidget {
  const ShareCard({required this.data, super.key});

  final ShareCardData data;

  @override
  Widget build(BuildContext context) => MediaQuery.withNoTextScaling(
    child: Container(
      width: 340.0,
      padding: const EdgeInsetsDirectional.all(24.0),
      decoration: BoxDecoration(
        color: BrandColors.paper,
        borderRadius: BorderRadius.circular(28.0),
        border: Border.all(color: BrandColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const OwnedWordmark(height: 22.0),
          const SizedBox(height: 28.0),
          Text(
            data.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'CupertinoSystemDisplay',
              color: BrandColors.ink,
              fontSize: 26.0,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.12,
            ),
          ),
          if (data.brand != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 4.0),
              child: Text(
                data.brand!,
                style: const TextStyle(fontFamily: 'CupertinoSystemText', color: BrandColors.muted, fontSize: 15.0),
              ),
            ),
          if (data.owner != null) ...<Widget>[
            const SizedBox(height: 20.0),
            Row(
              children: <Widget>[
                CompanyLogo(names: <String?>[data.owner], size: 40.0),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        const TextSpan(text: 'Owned by '),
                        TextSpan(
                          text: data.owner,
                          style: const TextStyle(color: BrandColors.ink, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    style: const TextStyle(fontFamily: 'CupertinoSystemText', color: BrandColors.muted, fontSize: 18.0, letterSpacing: -0.25),
                  ),
                ),
              ],
            ),
          ],
          if (data.health != null || data.ethics != null) ...<Widget>[
            const SizedBox(height: 24.0),
            Container(
              padding: const EdgeInsetsDirectional.all(16.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20.0),
                border: Border.all(color: BrandColors.hairline),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  if (data.ethics != null) _Score(title: 'Moral', score: data.ethics!),
                  if (data.health != null) _Score(title: 'Health', score: data.health!),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18.0),
          const Text(
            'Scan anything. See who really owns it.',
            style: TextStyle(
              fontFamily: 'CupertinoSystemText',
              fontFamilyFallback: <String>['Inter'],
              color: BrandColors.muted,
              fontSize: 13.0,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Score extends StatelessWidget {
  const _Score({required this.title, required this.score});

  final String title;
  final int score;

  @override
  Widget build(BuildContext context) => Theme(
    // Always the light look: the scores sit on a white panel in both themes.
    data: Theme.of(context).copyWith(
      colorScheme: Theme.of(context).colorScheme.copyWith(surface: Colors.white, onSurface: BrandColors.ink),
    ),
    child: Builder(
      builder: (BuildContext context) => Column(
        children: <Widget>[
          ScoreDonut(score: score, size: 76.0),
          const SizedBox(height: 6.0),
          Text(
            '$title · ${ScoreBand.of(score).label}',
            style: TextStyle(
              color: readableOn(ScoreBand.of(score).color, Colors.white),
              fontFamily: 'CupertinoSystemText',
              fontWeight: FontWeight.w600,
              fontSize: 14.0,
            ),
          ),
        ],
      ),
    ),
  );
}
