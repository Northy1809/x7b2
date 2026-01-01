import 'package:flutter/material.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/owned_mark.dart';

/// The logo mark (open ring and dot in the scan frame's corners) next to
/// "Owned.". Ink on light backgrounds by default; pass white for a dark one.
/// [motion] plays the mark's intro (home, launch) or keeps it moving.
class OwnedWordmark extends StatelessWidget {
  const OwnedWordmark({
    this.height = 40.0,
    this.color = BrandColors.ink,
    this.motion = OwnedMarkMotion.none,
    super.key,
  });

  final double height;
  final Color color;
  final OwnedMarkMotion motion;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Owned',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        OwnedMark(size: height * 1.25, color: color, motion: motion),
        SizedBox(width: height * 0.12),
        Text(
          'Owned.',
          style: TextStyle(
            fontFamily: 'CupertinoSystemDisplay',
            fontFamilyFallback: const <String>['Inter'],
            color: color,
            fontSize: height,
            fontWeight: FontWeight.w700,
            letterSpacing: -height * 0.02,
            height: 1.0,
          ),
        ),
      ],
    ),
  );
}
