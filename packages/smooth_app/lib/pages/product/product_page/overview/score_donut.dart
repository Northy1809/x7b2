import 'package:flutter/material.dart';
import 'package:smooth_app/services/score_types.dart';
import 'package:smooth_app/widgets/cal_kit.dart';

/// One score as Cal AI's macro card ("75/150g Protein eaten" over a ring):
/// "13/100" in the top corner, the name and verdict in grey under it, and
/// an ink ring with the score's icon in the middle. The card is the door
/// to the explanation.
class ScoreDonutCard extends StatelessWidget {
  const ScoreDonutCard({
    required this.title,
    required this.score,
    required this.onTap,
    this.verdict,
    this.loading = false,
    this.icon,
    super.key,
  });

  final String title;

  /// 0-100, null when not rated.
  final int? score;

  /// "Good", "Not rated yet"...; the band's label when null.
  final String? verdict;
  final bool loading;
  final VoidCallback? onTap;

  /// Drawn in the middle of the ring.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int? s = score;
    final String word =
        verdict ?? (loading ? 'Checking…' : (s == null ? 'Not rated' : ScoreBand.of(s).label));
    return Semantics(
      button: onTap != null,
      label: s == null ? '$title, $word' : '$title, $s out of 100, $word',
      excludeSemantics: true,
      child: CalCard(
        onTap: onTap,
        padding: const EdgeInsetsDirectional.fromSTEB(16.0, 16.0, 16.0, 18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            BigOver(value: s, over: s == null ? null : '/100', size: 24.0),
            const SizedBox(height: 4.0),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14.0),
            Center(
              child: loading
                  ? SizedBox.square(
                      dimension: 84.0,
                      child: CircularProgressIndicator(
                        strokeWidth: 7.0,
                        strokeCap: StrokeCap.round,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
                      ),
                    )
                  : CalRing(
                      fraction: s == null ? null : s / 100,
                      size: 84.0,
                      stroke: 7.0,
                      child: Icon(icon ?? Icons.circle_outlined, size: 24.0, color: theme.colorScheme.onSurface),
                    ),
            ),
            const SizedBox(height: 12.0),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Flexible(
                    child: Text(
                      word,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (onTap != null)
                    Icon(Icons.chevron_right_rounded, size: 18.0, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The ring with the score in the middle and "/100" under it, for places
/// where the number belongs inside (details pages, the share card).
class ScoreDonut extends StatelessWidget {
  const ScoreDonut({
    required this.score,
    this.size = 104.0,
    this.loading = false,
    super.key,
  });

  final int? score;
  final double size;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int? s = score;
    final double stroke = size * 0.085;
    if (loading) {
      return SizedBox.square(
        dimension: size,
        child: Padding(
          padding: EdgeInsets.all(stroke / 2),
          child: CircularProgressIndicator(
            strokeWidth: stroke,
            strokeCap: StrokeCap.round,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
          ),
        ),
      );
    }
    return CalRing(
      fraction: s == null ? null : s / 100,
      size: size,
      stroke: stroke,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (s == null)
            Text(
              '–',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontFamily: 'CupertinoSystemDisplay',
                fontFamilyFallback: const <String>['Inter'],
                fontSize: size * 0.3,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            CountUp(
              value: s,
              style: TextStyle(
                fontFamily: 'CupertinoSystemDisplay',
                fontFamilyFallback: const <String>['Inter'],
                fontSize: size * 0.3,
                height: 1.0,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: theme.colorScheme.onSurface,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          if (s != null)
            Text(
              '/100',
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontFamily: 'CupertinoSystemText',
                fontFamilyFallback: const <String>['Inter'],
                fontSize: size * 0.11,
                height: 1.3,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
