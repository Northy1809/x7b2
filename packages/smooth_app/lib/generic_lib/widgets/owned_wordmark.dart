import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:smooth_app/themes/brand_colors.dart';

/// The logo mark (ring in the scan frame's corners) next to "Owned.".
/// Ink on light backgrounds by default; pass white for a dark one.
class OwnedWordmark extends StatelessWidget {
  const OwnedWordmark({this.height = 40.0, this.color = BrandColors.ink, super.key});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Owned',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SvgPicture.asset(
          color.computeLuminance() > 0.5
              ? 'assets/app/release_icon_dark_transparent_no_border.svg'
              : 'assets/app/release_icon_light_transparent_no_border.svg',
          height: height * 1.25,
        ),
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
