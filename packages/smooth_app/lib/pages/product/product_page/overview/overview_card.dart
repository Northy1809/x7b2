import 'package:flutter/material.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/services/score_types.dart';

/// Plain rounded card used by every section of the product overview, so
/// the page reads as one calm list instead of many different widgets.
class OverviewCard extends StatelessWidget {
  const OverviewCard({required this.child, this.padding, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: LARGE_SPACE,
        vertical: SMALL_SPACE,
      ),
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: ROUNDED_BORDER_RADIUS,
          side: BorderSide(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.10),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: padding ?? const EdgeInsetsDirectional.all(LARGE_SPACE),
          child: child,
        ),
      ),
    );
  }
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
                  fontWeight: FontWeight.w800,
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
          iconColor: theme.colorScheme.primary,
          collapsedIconColor: theme.colorScheme.primary,
          title: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
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
