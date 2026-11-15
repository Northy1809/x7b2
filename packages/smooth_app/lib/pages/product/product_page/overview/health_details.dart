import 'package:flutter/material.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/pages/product/product_page/overview/overview_card.dart';
import 'package:smooth_app/pages/product/product_page/overview/score_ring.dart';
import 'package:smooth_app/pages/product/product_page/overview/source_links.dart';
import 'package:smooth_app/services/health_score.dart';
import 'package:smooth_app/services/score_types.dart';

/// The "Health" section: score, good and bad facts, and (folded away) how
/// the score is made up and its sources.
class HealthDetails extends StatelessWidget {
  const HealthDetails({required this.result, super.key});

  final HealthScoreResult result;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int? score = result.score;
    final List<SourceLink> sources = _uniqueSources(<ScoreFactor>[
      ...result.factors,
      ...result.positives,
      ...result.negatives,
    ]);
    return OverviewCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          OverviewHeading(
            title: 'Health',
            subtitle: score == null
                ? 'No score'
                : '${result.band!.label} · $score/100',
            trailing: ScoreRing(score: score, size: 52.0),
          ),
          if (result.missingReason != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: MEDIUM_SPACE),
              child: Text(
                result.missingReason!,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
            ),
          if (result.negatives.isNotEmpty) ...<Widget>[
            const _SubHeading('Watch out'),
            for (final ScoreFactor f in result.negatives)
              FactorRow(title: f.title, detail: f.detail, tone: f.tone),
          ],
          if (result.positives.isNotEmpty) ...<Widget>[
            const _SubHeading('Good'),
            for (final ScoreFactor f in result.positives)
              FactorRow(title: f.title, detail: f.detail, tone: f.tone),
          ],
          if (result.factors.isNotEmpty)
            FoldOut(
              title: 'How the score is made',
              children: <Widget>[
                for (final ScoreFactor f in result.factors)
                  FactorRow(
                    title: f.title,
                    detail: f.detail,
                    tone: f.tone,
                    trailing: f.points == null
                        ? null
                        : '${f.points}/${f.maxPoints}',
                  ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: SMALL_SPACE),
                  child: Text(
                    'Nutrition profile counts 60 %, additives 20 %, '
                    'processing 10 % and organic 10 %. Parts without data '
                    'are left out and the rest is scaled to 100.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          if (sources.isNotEmpty)
            FoldOut(
              title: 'Sources (${sources.length})',
              children: <Widget>[SourceLinks(sources, dense: true)],
            ),
        ],
      ),
    );
  }

  static List<SourceLink> _uniqueSources(final List<ScoreFactor> factors) {
    final Set<String> seen = <String>{};
    return <SourceLink>[
      for (final ScoreFactor f in factors)
        for (final SourceLink s in f.sources)
          if (seen.add(s.url)) s,
    ];
  }
}

class _SubHeading extends StatelessWidget {
  const _SubHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(top: LARGE_SPACE, bottom: 2.0),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
