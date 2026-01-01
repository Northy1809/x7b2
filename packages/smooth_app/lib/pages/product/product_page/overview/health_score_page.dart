import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:smooth_app/pages/product/product_page/overview/ethics_details.dart';
import 'package:smooth_app/pages/product/product_page/overview/source_links.dart';
import 'package:smooth_app/services/health_score.dart';
import 'package:smooth_app/services/score_types.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/cal_ui.dart';

/// The page behind every health score (20/11 2026), built like the moral
/// score page so both read the same: the product, the score with one
/// sentence and its four parts as bars, then each part as a card that
/// opens what it means and its sources, the nutrients worth knowing, and
/// how the score is made.
class HealthScorePage extends StatefulWidget {
  const HealthScorePage({required this.result, this.productName, this.photo, super.key});

  final HealthScoreResult result;
  final String? productName;

  /// The product's front photo, when there is one.
  final ImageProvider? photo;

  static Future<void> open(
    final BuildContext context, {
    required final HealthScoreResult result,
    final String? productName,
    final ImageProvider? photo,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => HealthScorePage(result: result, productName: productName, photo: photo),
    ),
  );

  /// "Nutrition", "Additives", "Processing" or "Organic" for a part of the
  /// score sum.
  static String partName(final ScoreFactor f) {
    if (f.maxPoints == HealthScore.nutritionMax) {
      return 'Nutrition';
    }
    if (f.maxPoints == HealthScore.additivesMax) {
      return 'Additives';
    }
    return f.title.toLowerCase().contains('organic') ? 'Organic' : 'Processing';
  }

  static IconData partIcon(final ScoreFactor f) => switch (partName(f)) {
    'Nutrition' => Icons.restaurant_rounded,
    'Additives' => Icons.science_outlined,
    'Processing' => Icons.factory_outlined,
    _ => Icons.eco_outlined,
  };

  static Color toneColor(final FactorTone tone) => switch (tone) {
    FactorTone.positive => kEthicsGood,
    FactorTone.neutral => BrandColors.accentOrange,
    FactorTone.negative => BrandColors.accentRed,
  };

  static String toneLabel(final FactorTone tone) => switch (tone) {
    FactorTone.positive => 'Good',
    FactorTone.neutral => 'Okay',
    FactorTone.negative => 'Watch out',
  };

  /// One sentence on what holds the score back and what helps it.
  static String verdict(final HealthScoreResult r) {
    if (r.score == null) {
      return r.missingReason ?? 'Not enough data for a score yet.';
    }
    String names(final List<ScoreFactor> fs) {
      final List<String> n = <String>[for (final ScoreFactor f in fs) partName(f).toLowerCase()];
      return n.length == 1 ? n.single : '${n.sublist(0, n.length - 1).join(', ')} and ${n.last}';
    }

    double ratio(final ScoreFactor f) => (f.points ?? 0) / (f.maxPoints ?? 1);
    // A missing organic label is common; it is not what "holds back" a product.
    final List<ScoreFactor> weak = <ScoreFactor>[
      for (final ScoreFactor f in r.factors)
        if (ratio(f) < 0.5 && partName(f) != 'Organic') f,
    ];
    final List<ScoreFactor> strong = <ScoreFactor>[
      for (final ScoreFactor f in r.factors)
        if (ratio(f) >= 0.75) f,
    ];
    final StringBuffer sb = StringBuffer();
    if (weak.isNotEmpty) {
      sb.write('Held back by ${names(weak)}.');
    }
    if (strong.isNotEmpty) {
      if (sb.isNotEmpty) {
        sb.write(' ');
      }
      sb.write('Strong on ${names(strong)}.');
    }
    if (sb.isEmpty) {
      sb.write('Middle of the road on every part.');
    }
    return sb.toString();
  }

  @override
  State<HealthScorePage> createState() => _HealthScorePageState();
}

class _HealthScorePageState extends State<HealthScorePage> {
  final ScrollController _scroll = ScrollController();
  bool _titleVisible = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final bool visible = _scroll.hasClients && _scroll.offset > 120.0;
      if (visible != _titleVisible) {
        setState(() => _titleVisible = visible);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final HealthScoreResult r = widget.result;
    final List<ScoreFactor> nutrients = <ScoreFactor>[...r.negatives, ...r.positives];
    final Set<String> seen = <String>{};
    final List<SourceLink> sources = <SourceLink>[
      for (final ScoreFactor f in <ScoreFactor>[...r.factors, ...nutrients])
        for (final SourceLink s in f.sources)
          if (seen.add(s.url)) s,
    ];
    final String name = (widget.productName?.trim().isNotEmpty ?? false) ? widget.productName!.trim() : 'This product';
    int index = 2;

    return Scaffold(
      body: CustomScrollView(
        controller: _scroll,
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: false,
            toolbarHeight: 60.0,
            backgroundColor: theme.scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            elevation: 0.0,
            scrolledUnderElevation: 0.0,
            titleSpacing: 0.0,
            title: Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 16.0),
              child: Row(
                children: <Widget>[
                  CalRoundButton(
                    icon: CupertinoIcons.arrow_left,
                    tooltip: 'Back',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: AnimatedOpacity(
                      opacity: _titleVisible ? 1.0 : 0.0,
                      duration: CalMotion.page,
                      child: Text(
                        'Health score',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: theme.textTheme.titleMedium?.copyWith(fontSize: 17.0, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 40.0),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: kCalSide),
            sliver: SliverList.list(
              children: <Widget>[
                FadeUpIn(
                  child: _Header(name: name, photo: widget.photo),
                ),
                const SizedBox(height: 18.0),
                FadeUpIn(index: 1, child: _ScoreHero(result: r)),
                if (r.factors.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 32.0),
                  const CalSectionTitle('What goes into it'),
                  const SizedBox(height: 4.0),
                  Text(
                    'Tap a part to see what it means and where it comes from.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14.0),
                  for (final ScoreFactor f in r.factors)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(bottom: 10.0),
                      child: FadeUpIn(index: index++, child: HealthFactorCard(f)),
                    ),
                ],
                if (nutrients.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 22.0),
                  const CalSectionTitle('Nutrients'),
                  const SizedBox(height: 4.0),
                  Text(
                    'From the label, per 100 g. Worth knowing, not part of the sum.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14.0),
                  _NutrientGrid(nutrients),
                ],
                const SizedBox(height: 28.0),
                CalCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'How we score health',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 16.0),
                      ),
                      const SizedBox(height: 8.0),
                      Text(
                        'Nutrition counts ${HealthScore.nutritionMax} %, additives ${HealthScore.additivesMax} %, '
                        'processing ${HealthScore.processingMax} % and organic ${HealthScore.organicMax} %. '
                        'Parts without data are left out and the rest is scaled to 100. '
                        'Everything comes from open data with a source.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      if (sources.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 14.0),
                        Text('Sources', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4.0),
                        SourceLinks(sources, dense: true),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 40.0 + MediaQuery.paddingOf(context).bottom),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The product photo (or a heart), "Health score" small, the product big.
class _Header extends StatelessWidget {
  const _Header({required this.name, this.photo});

  final String name;
  final ImageProvider? photo;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget heart = Icon(CupertinoIcons.heart_fill, size: 24.0, color: theme.colorScheme.onSurface);
    return Row(
      children: <Widget>[
        Container(
          width: 52.0,
          height: 52.0,
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: calFill(context), borderRadius: BorderRadius.circular(14.0)),
          child: photo == null
              ? heart
              : Image(image: photo!, width: 52.0, height: 52.0, fit: BoxFit.cover, errorBuilder: (_, _, _) => heart),
        ),
        const SizedBox(width: 14.0),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Health score',
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14.0, color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2.0),
              Semantics(
                header: true,
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.displayMedium?.copyWith(fontSize: 28.0, letterSpacing: -0.7, height: 1.1),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "35/100", the band, the ring; one sentence; each part as a bar.
class _ScoreHero extends StatelessWidget {
  const _ScoreHero({required this.result});

  final HealthScoreResult result;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int? score = result.score;
    final String sentence = HealthScorePage.verdict(result);
    return Semantics(
      label: score == null
          ? 'Health score: no score. $sentence'
          : 'Health score $score out of 100, ${result.band!.label}. $sentence',
      child: CalCard(
        radius: 22.0,
        padding: const EdgeInsetsDirectional.fromSTEB(22.0, 20.0, 18.0, 20.0),
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: BigOver(value: score, over: score == null ? null : '/100', size: 48.0),
                        ),
                        const SizedBox(height: 12.0),
                        Container(
                          padding: const EdgeInsetsDirectional.symmetric(horizontal: 12.0, vertical: 6.0),
                          decoration: BoxDecoration(
                            color: calFill(context),
                            borderRadius: BorderRadius.circular(100.0),
                          ),
                          child: Text(
                            score == null ? 'No score' : result.band!.label,
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 13.0),
                          ),
                        ),
                      ],
                    ),
                  ),
                  CalRing(
                    fraction: score == null ? null : score / 100,
                    size: 104.0,
                    stroke: 9.0,
                    child: Icon(CupertinoIcons.heart_fill, size: 24.0, color: theme.colorScheme.onSurface),
                  ),
                ],
              ),
              const SizedBox(height: 18.0),
              Text(
                sentence,
                style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16.0, fontWeight: FontWeight.w600, height: 1.35),
              ),
              if (result.factors.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16.0),
                for (final ScoreFactor f in result.factors) _PartBar(f),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "Nutrition   15/60" over a bar in the part's tone.
class _PartBar extends StatelessWidget {
  const _PartBar(this.factor);

  final ScoreFactor factor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int points = factor.points ?? 0;
    final int max = factor.maxPoints ?? 1;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  HealthScorePage.partName(factor),
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14.0, fontWeight: FontWeight.w500),
                ),
              ),
              Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: '$points',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                      text: '/$max',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14.0),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          ClipRRect(
            borderRadius: BorderRadius.circular(99.0),
            child: SizedBox(
              height: 8.0,
              width: double.infinity,
              child: ColoredBox(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: points / max),
                  duration: CalMotion.reduced(context) ? Duration.zero : CalMotion.fill,
                  curve: CalMotion.curve,
                  builder: (BuildContext context, double t, _) => FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: t.clamp(0.0, 1.0),
                    child: ColoredBox(color: HealthScorePage.toneColor(factor.tone)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One part of the score as a card, as a scandal on the moral score page:
/// a tone pill and the part, the points, the title, the start of the
/// explanation, the sources. Tap opens all of it.
class HealthFactorCard extends StatelessWidget {
  const HealthFactorCard(this.factor, {super.key});

  final ScoreFactor factor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final String part = HealthScorePage.partName(factor);
    return Semantics(
      button: true,
      label: '$part: ${factor.title}, ${factor.points ?? 0} of ${factor.maxPoints} points',
      excludeSemantics: true,
      child: PressScale(
        scale: 0.98,
        onTap: () => showHealthFactorSheet(context, factor),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(14.0, 12.0, 14.0, 12.0),
          decoration: BoxDecoration(color: calRow(context), borderRadius: BorderRadius.circular(18.0)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Wrap(
                      spacing: 8.0,
                      runSpacing: 4.0,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        _TonePill(tone: factor.tone),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(HealthScorePage.partIcon(factor), size: 14.0, color: muted),
                            const SizedBox(width: 4.0),
                            Text(part, style: theme.textTheme.bodySmall?.copyWith(fontSize: 13.0, color: muted)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: '${factor.points ?? 0}/${factor.maxPoints}',
                          style: TextStyle(fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
                        ),
                        TextSpan(
                          text: ' pts',
                          style: TextStyle(color: muted),
                        ),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15.0),
                  ),
                ],
              ),
              const SizedBox(height: 10.0),
              Text(
                factor.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 17.0, height: 1.25),
              ),
              if (factor.detail != null) ...<Widget>[
                const SizedBox(height: 4.0),
                Text(
                  factor.detail!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14.0, color: muted, height: 1.35),
                ),
              ],
              const SizedBox(height: 10.0),
              Row(
                children: <Widget>[
                  Icon(CupertinoIcons.link, size: 14.0, color: muted),
                  const SizedBox(width: 6.0),
                  Expanded(
                    child: Text(
                      factor.sources.isEmpty
                          ? 'How it is scored'
                          : '${factor.sources.length} source${factor.sources.length == 1 ? '' : 's'} · ${factor.sources.first.host}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 13.0, color: muted),
                    ),
                  ),
                  Text(
                    'Read',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 14.0),
                  ),
                  Icon(CupertinoIcons.chevron_right, size: 14.0, color: theme.colorScheme.onSurface),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TonePill extends StatelessWidget {
  const _TonePill({required this.tone});

  final FactorTone tone;

  @override
  Widget build(BuildContext context) {
    final Color color = HealthScorePage.toneColor(tone);
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 9.0, vertical: 3.0),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99.0)),
      child: Text(
        HealthScorePage.toneLabel(tone),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: readableOn(color, calRow(context)),
        ),
      ),
    );
  }
}

/// "Gives 15 of the 60 points for nutrition." for the sheet.
String healthImpactLine(final ScoreFactor f) {
  final String part = HealthScorePage.partName(f).toLowerCase();
  final int points = f.points ?? 0;
  final int max = f.maxPoints ?? 0;
  if (points == max) {
    return 'Gives all $max points for $part.';
  }
  if (points == 0) {
    return 'Gives none of the $max points for $part.';
  }
  return 'Gives $points of the $max points for $part.';
}

/// A part of the health score in full: what it is, what it gives, why,
/// and its sources.
Future<void> showHealthFactorSheet(final BuildContext context, final ScoreFactor f) {
  final Color color = HealthScorePage.toneColor(f.tone);
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext context) {
      final ThemeData theme = Theme.of(context);
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SingleChildScrollView(
          padding: EdgeInsetsDirectional.fromSTEB(kCalSide, 0.0, kCalSide, MediaQuery.paddingOf(context).bottom + 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 32.0,
                    height: 32.0,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Icon(HealthScorePage.partIcon(f), size: 16.0, color: color),
                  ),
                  const SizedBox(width: 10.0),
                  Expanded(
                    child: Text(
                      '${HealthScorePage.partName(f)} · ${HealthScorePage.toneLabel(f.tone)}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14.0),
              Text(
                f.title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 24.0,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 14.0),
              Container(
                width: double.infinity,
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 14.0, vertical: 12.0),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14.0),
                ),
                child: Text(
                  healthImpactLine(f),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 14.0,
                    height: 1.35,
                  ),
                ),
              ),
              if (f.detail != null) ...<Widget>[
                const SizedBox(height: 12.0),
                Text(f.detail!, style: theme.textTheme.bodyLarge?.copyWith(height: 1.45, fontSize: 16.0)),
              ],
              if (f.sources.isNotEmpty) ...<Widget>[
                const SizedBox(height: 20.0),
                const CalSectionTitle('Sources'),
                const SizedBox(height: 8.0),
                SourceLinks(f.sources),
              ],
            ],
          ),
        ),
      );
    },
  );
}

/// The nutrient notes ("High in sugar 76 g") two by two.
class _NutrientGrid extends StatelessWidget {
  const _NutrientGrid(this.items);

  final List<ScoreFactor> items;

  @override
  Widget build(BuildContext context) {
    final List<Widget> tiles = <Widget>[for (final ScoreFactor f in items) _NutrientTile(f)];
    return Column(
      children: <Widget>[
        for (int i = 0; i < tiles.length; i += 2)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 10.0),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(child: tiles[i]),
                  const SizedBox(width: 10.0),
                  Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox.shrink()),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _NutrientTile extends StatelessWidget {
  const _NutrientTile(this.factor);

  final ScoreFactor factor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = HealthScorePage.toneColor(factor.tone);
    final bool bad = factor.tone == FactorTone.negative;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12.0, 12.0, 12.0, 12.0),
      decoration: BoxDecoration(color: calRow(context), borderRadius: BorderRadius.circular(16.0)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 28.0,
            height: 28.0,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(bad ? CupertinoIcons.exclamationmark : CupertinoIcons.checkmark, size: 14.0, color: color),
          ),
          const SizedBox(height: 10.0),
          Text(
            factor.title,
            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 15.0, height: 1.25),
          ),
          if (factor.detail != null) ...<Widget>[
            const SizedBox(height: 2.0),
            Text(
              factor.detail!,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 13.0, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
