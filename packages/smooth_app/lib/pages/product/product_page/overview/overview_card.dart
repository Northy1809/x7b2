import 'package:flutter/material.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/services/score_types.dart';
import 'package:smooth_app/widgets/cal_kit.dart';

/// The card behind every section of the product page, details pages and
/// info pages: Cal AI's white card (20 pt corners, faint border, soft
/// shadow) on the 24 pt page margin (16/11; was a Material card).
class OverviewCard extends StatelessWidget {
  const OverviewCard({required this.child, this.padding, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.symmetric(horizontal: 24.0, vertical: 7.0),
    child: CalCard(
      padding: EdgeInsetsDirectional.zero,
      // Fold-outs and rows inside paint their press on a Material.
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(20.0),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding ?? const EdgeInsetsDirectional.all(18.0), child: child),
      ),
    ),
  );
}

/// Section heading: title, optional subtitle and a trailing widget.
class OverviewHeading extends StatelessWidget {
  const OverviewHeading({required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 20.0,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.45,
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: 2.0),
                  child: Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// A folded-away block ("How the score is made", "Sources"): keeps the
/// card short while every detail stays one tap away.
class FoldOut extends StatelessWidget {
  const FoldOut({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: SMALL_SPACE),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsetsDirectional.zero,
          minTileHeight: 48.0,
          childrenPadding: const EdgeInsetsDirectional.only(bottom: SMALL_SPACE),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          iconColor: theme.colorScheme.onSurfaceVariant,
          collapsedIconColor: theme.colorScheme.onSurfaceVariant,
          title: Text(
            title,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 15.0,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          children: children,
        ),
      ),
    );
  }
}

/// Icon + colour for a good / neutral / bad line.
(IconData, Color) toneStyle(final FactorTone tone) => switch (tone) {
  FactorTone.positive => (Icons.check_circle, ScoreBand.excellent.color),
  FactorTone.neutral => (Icons.remove_circle, ScoreBand.mediocre.color),
  FactorTone.negative => (Icons.cancel, ScoreBand.bad.color),
};

/// One explained line: icon, title, optional detail and points.
class FactorRow extends StatelessWidget {
  const FactorRow({
    required this.title,
    required this.tone,
    this.detail,
    this.trailing,
  });

  final String title;
  final String? detail;
  final FactorTone tone;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (IconData icon, Color color) = toneStyle(tone);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color, size: 22.0),
          const SizedBox(width: MEDIUM_SPACE),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: SMALL_SPACE),
            Text(
              trailing!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
