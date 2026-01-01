import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/helpers/string_extension.dart';
import 'package:smooth_app/pages/product/product_page/overview/ethics_details.dart';
import 'package:smooth_app/pages/product/product_page/overview/owner_section.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/cal_ui.dart';

/// The page behind every moral score (18/11 2026): the score and what it
/// means in one sentence, how bad the record is as one coloured bar, the
/// three categories as filters, then every scandal and crisis on a
/// timeline, newest first. Each case opens its whole story and sources.
///
/// Every place that shows a moral score opens this page, so it reads the
/// same from a scan, a product, a search or a company.
class MoralScorePage extends StatefulWidget {
  const MoralScorePage({
    required this.result,
    this.ownerName,
    this.db,
    this.initialCategory,
    this.currentYear,
    super.key,
  });

  /// Null when the owner is unknown or not researched yet.
  final EthicsScoreResult? result;

  /// The owner as the product data names it, for the "not rated" text.
  final String? ownerName;

  /// For how many companies were researched and when.
  final EthicsDb? db;

  /// Opens filtered on one category (from a category card).
  final EthicsCategory? initialCategory;

  /// For tests; this year when null.
  final int? currentYear;

  static Future<void> open(
    final BuildContext context, {
    required final EthicsScoreResult? result,
    final String? ownerName,
    final EthicsDb? db,
    final EthicsCategory? category,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => MoralScorePage(
        result: result,
        ownerName: ownerName,
        db: db,
        initialCategory: category,
      ),
    ),
  );

  @override
  State<MoralScorePage> createState() => _MoralScorePageState();
}

class _MoralScorePageState extends State<MoralScorePage> {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _casesKey = GlobalKey();
  late EthicsCategory? _filter = widget.initialCategory;
  bool _titleVisible = false;

  int get _now => widget.currentYear ?? DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final bool visible = _scroll.hasClients && _scroll.offset > 120.0;
      if (visible != _titleVisible) {
        setState(() => _titleVisible = visible);
      }
    });
    if (widget.initialCategory != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showCases(animate: false),
      );
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _showCases({final bool animate = true}) {
    final BuildContext? target = _casesKey.currentContext;
    if (target == null || !mounted) {
      return;
    }
    unawaited(
      Scrollable.ensureVisible(
        target,
        duration: animate && !CalMotion.reduced(context)
            ? CalMotion.page * 2
            : Duration.zero,
        curve: Curves.easeInOutCubic,
        alignment: 0.05,
      ),
    );
  }

  void _pick(final EthicsCategory? category) {
    Haptics.select();
    setState(() => _filter = _filter == category ? null : category);
    _showCases();
  }

  String get _name {
    final EthicsScoreResult? r = widget.result;
    if (r != null) {
      return EthicsDb.displayName(
        widget.ownerName ?? r.company.name,
        r.company,
      );
    }
    final String? owner = widget.ownerName;
    return owner == null || owner.trim().isEmpty
        ? 'Unknown company'
        : owner.capFirst();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final EthicsScoreResult? r = widget.result;
    final List<EthicsItem> issues = r == null
        ? const <EthicsItem>[]
        : <EthicsItem>[
            for (final EthicsCategoryScore c in r.categories) ...c.issues,
          ];
    final List<EthicsItem> good = r == null
        ? const <EthicsItem>[]
        : <EthicsItem>[
            for (final EthicsCategoryScore c in r.categories) ...c.good,
          ];
    final List<EthicsItem> notes = r == null
        ? const <EthicsItem>[]
        : <EthicsItem>[
            for (final EthicsCategoryScore c in r.categories) ...c.notes,
          ];
    final List<EthicsItem> shown = issues
        .where((EthicsItem i) => _filter == null || i.category == _filter)
        .toList();

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
                        'Moral score',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 17.0,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 40.0),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              kCalSide,
              0.0,
              kCalSide,
              0.0,
            ),
            sliver: SliverList.list(
              children: <Widget>[
                FadeUpIn(child: _Header(name: _name)),
                const SizedBox(height: 18.0),
                FadeUpIn(
                  index: 1,
                  child: _ScoreHero(result: r, issues: issues, good: good),
                ),
                if (r == null) ...<Widget>[
                  const SizedBox(height: 12.0),
                  FadeUpIn(
                    index: 2,
                    child: CalCard(
                      child: Text(
                        widget.ownerName == null
                            ? 'We do not know who owns this product, so we cannot rate the company behind it.'
                            : 'We have not researched $_name yet. We keep adding companies, starting with '
                                  'the ones behind the most products in the shops.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: 12.0),
                  FadeUpIn(
                    index: 2,
                    child: Row(
                      children: <Widget>[
                        for (
                          int i = 0;
                          i < r.categories.length;
                          i++
                        ) ...<Widget>[
                          if (i > 0) const SizedBox(width: 10.0),
                          Expanded(
                            child: _CategoryFilterCard(
                              category: r.categories[i],
                              selected: _filter == r.categories[i].category,
                              onTap: () => _pick(r.categories[i].category),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 32.0),
                  KeyedSubtree(
                    key: _casesKey,
                    child: const CalSectionTitle('Scandals and crises'),
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    issues.isEmpty
                        ? 'Nothing found in public sources.'
                        : 'Newest first. Tap a case to read the whole story and its sources.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (issues.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 14.0),
                    CalSegmented<EthicsCategory?>(
                      segments: <(EthicsCategory?, String)>[
                        (null, 'All ${issues.length}'),
                        for (final EthicsCategory c in EthicsCategory.values)
                          (c, ethicsCategoryShort(c)),
                      ],
                      selected: _filter,
                      onChanged: (EthicsCategory? c) =>
                          setState(() => _filter = c),
                    ),
                    const SizedBox(height: 18.0),
                    AnimatedSwitcher(
                      duration: CalMotion.page,
                      switchInCurve: CalMotion.curve,
                      layoutBuilder: (Widget? current, List<Widget> previous) =>
                          Stack(
                            alignment: AlignmentDirectional.topStart,
                            children: <Widget>[...previous, ?current],
                          ),
                      child: shown.isEmpty
                          ? _EmptyFilter(
                              key: ValueKey<EthicsCategory?>(_filter),
                              category: _filter!,
                            )
                          : ScandalTimeline(
                              key: ValueKey<EthicsCategory?>(_filter),
                              items: shown,
                              currentYear: _now,
                            ),
                    ),
                  ],
                  if (good.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 28.0),
                    const CalSectionTitle('What it does well'),
                    const SizedBox(height: 12.0),
                    for (final EthicsItem item in good)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(bottom: 10.0),
                        child: ScandalCard(item, currentYear: _now),
                      ),
                  ],
                  if (notes.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 28.0),
                    const CalSectionTitle('Good to know'),
                    const SizedBox(height: 12.0),
                    for (final EthicsItem item in notes)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(bottom: 10.0),
                        child: ScandalCard(item, currentYear: _now),
                      ),
                  ],
                ],
                const SizedBox(height: 28.0),
                CalCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'How we rate companies',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 16.0,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      EthicsMethodNote(widget.db),
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

/// Logo, "Moral score" small and grey, the company big.
class _Header extends StatelessWidget {
  const _Header({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        OwnerAvatar(name: name, size: 52.0),
        const SizedBox(width: 14.0),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Moral score',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 14.0,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2.0),
              Semantics(
                header: true,
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontSize: 28.0,
                    letterSpacing: -0.7,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The big card: "13/100", the band, the ring; then one sentence and the
/// record as one bar, red for very serious, orange for serious, grey for
/// minor, green for good practices.
class _ScoreHero extends StatelessWidget {
  const _ScoreHero({
    required this.result,
    required this.issues,
    required this.good,
  });

  final EthicsScoreResult? result;
  final List<EthicsItem> issues;
  final List<EthicsItem> good;

  static String verdict(
    final List<EthicsItem> issues,
    final List<EthicsItem> good,
  ) {
    String n(final int count, final String one, final String many) =>
        '$count ${count == 1 ? one : many}';
    if (issues.isEmpty && good.isEmpty) {
      return 'No documented problems or good practices in public sources, '
          'so it keeps the starting score of ${EthicsScore.baseline}.';
    }
    final int verySerious = issues
        .where((EthicsItem i) => i.severity >= 3)
        .length;
    final StringBuffer sb = StringBuffer();
    if (issues.isEmpty) {
      sb.write('No documented scandals.');
    } else {
      sb.write(n(issues.length, 'documented case', 'documented cases'));
      if (verySerious > 0) {
        sb.write(
          verySerious == issues.length
              ? ', all very serious'
              : ', $verySerious very serious',
        );
      }
      sb.write('.');
    }
    if (good.isNotEmpty) {
      sb.write(' ${n(good.length, 'good practice', 'good practices')}.');
    }
    return sb.toString();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final EthicsScoreResult? r = result;
    final int? score = r?.score;
    return Semantics(
      label: score == null
          ? 'Moral score: not rated yet'
          : 'Moral score $score out of 100, ${r!.band.label}. ${verdict(issues, good)}',
      child: CalCard(
        radius: 22.0,
        padding: const EdgeInsetsDirectional.fromSTEB(22.0, 20.0, 18.0, 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ExcludeSemantics(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: BigOver(
                            value: score,
                            over: score == null ? null : '/100',
                            size: 48.0,
                          ),
                        ),
                        const SizedBox(height: 12.0),
                        Container(
                          padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: 12.0,
                            vertical: 6.0,
                          ),
                          decoration: BoxDecoration(
                            color: calFill(context),
                            borderRadius: BorderRadius.circular(100.0),
                          ),
                          child: Text(
                            score == null ? 'Not rated yet' : r!.band.label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  CalRing(
                    fraction: score == null ? null : score / 100,
                    size: 104.0,
                    stroke: 9.0,
                    child: Icon(
                      Icons.balance_rounded,
                      size: 24.0,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            if (r != null) ...<Widget>[
              const SizedBox(height: 18.0),
              ExcludeSemantics(
                child: Text(
                  verdict(issues, good),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontSize: 16.0,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
              if (issues.isNotEmpty || good.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14.0),
                ExcludeSemantics(
                  child: RecordBar(issues: issues, good: good),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// The record as one bar, a segment per kind of case, and a legend.
class RecordBar extends StatelessWidget {
  const RecordBar({required this.issues, required this.good, super.key});

  final List<EthicsItem> issues;
  final List<EthicsItem> good;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<(int, String, Color)> parts = <(int, String, Color)>[
      (
        issues.where((EthicsItem i) => i.severity >= 3).length,
        'Very serious',
        BrandColors.accentRed,
      ),
      (
        issues.where((EthicsItem i) => i.severity == 2).length,
        'Serious',
        BrandColors.accentOrange,
      ),
      (
        issues.where((EthicsItem i) => i.severity <= 1).length,
        'Minor',
        BrandColors.faint,
      ),
      (good.length, 'Good', kEthicsGood),
    ].where(((int, String, Color) p) => p.$1 > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(99.0),
          child: SizedBox(
            height: 10.0,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: CalMotion.reduced(context)
                  ? Duration.zero
                  : CalMotion.fill,
              curve: CalMotion.curve,
              builder: (BuildContext context, double t, _) => Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int i = 0; i < parts.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(width: 3.0),
                    Expanded(
                      flex: parts[i].$1 * 100,
                      child: FractionallySizedBox(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: t,
                        child: ColoredBox(color: parts[i].$3),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10.0),
        Wrap(
          spacing: 14.0,
          runSpacing: 6.0,
          children: <Widget>[
            for (final (int count, String label, Color color) in parts)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 8.0,
                    height: 8.0,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6.0),
                  Text(
                    '$count $label',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13.0,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

/// One category as a small card ("40/100 Climate", ring in its colour, the
/// number of cases); tap shows only its cases. Selected gets an ink edge.
class _CategoryFilterCard extends StatelessWidget {
  const _CategoryFilterCard({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final EthicsCategoryScore category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (IconData icon, Color color) = ethicsCategoryStyle(category.category);
    final String label = ethicsCategoryShort(category.category);
    final int cases = category.issues.length;
    return Semantics(
      button: true,
      selected: selected,
      label:
          '$label ${category.score} out of 100, $cases ${cases == 1 ? 'case' : 'cases'}',
      excludeSemantics: true,
      child: PressScale(
        feedback: Haptics.select,
        onTap: onTap,
        child: AnimatedContainer(
          duration: CalMotion.select,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20.0),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.onSurface
                  : Colors.transparent,
              width: 2.0,
            ),
          ),
          child: CalCard(
            radius: 18.0,
            padding: const EdgeInsetsDirectional.fromSTEB(
              12.0,
              14.0,
              12.0,
              12.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: BigOver(
                    value: category.score,
                    over: '/100',
                    size: 18.0,
                  ),
                ),
                const SizedBox(height: 3.0),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textScaler: TextScaler.noScaling,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 13.0,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10.0),
                Center(
                  child: CalRing(
                    fraction: category.score / 100,
                    size: 56.0,
                    stroke: 6.0,
                    color: color,
                    child: Icon(icon, size: 17.0, color: color),
                  ),
                ),
                const SizedBox(height: 8.0),
                Center(
                  child: Text(
                    cases == 0
                        ? 'No cases'
                        : '$cases ${cases == 1 ? 'case' : 'cases'}',
                    maxLines: 1,
                    textScaler: TextScaler.noScaling,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyFilter extends StatelessWidget {
  const _EmptyFilter({required this.category, super.key});

  final EthicsCategory category;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: CalCard(
        child: Text(
          'No documented cases in ${category.label}.',
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
        ),
      ),
    );
  }
}

/// The cases on a timeline: a year, then its cases, newest year first and
/// the worst case first within a year. A thin line joins them.
class ScandalTimeline extends StatelessWidget {
  const ScandalTimeline({required this.items, this.currentYear, super.key});

  final List<EthicsItem> items;
  final int? currentYear;

  static const double _rail = 26.0;

  /// Newest year first (undated last), then the most serious.
  static List<(int?, List<EthicsItem>)> groups(final List<EthicsItem> items) {
    final List<EthicsItem> sorted = items.toList()
      ..sort((EthicsItem a, EthicsItem b) {
        final int byYear = (b.year ?? -1) - (a.year ?? -1);
        return byYear != 0 ? byYear : b.severity - a.severity;
      });
    final List<(int?, List<EthicsItem>)> out = <(int?, List<EthicsItem>)>[];
    for (final EthicsItem i in sorted) {
      if (out.isEmpty || out.last.$1 != i.year) {
        out.add((i.year, <EthicsItem>[]));
      }
      out.last.$2.add(i);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int now = currentYear ?? DateTime.now().year;
    final Color line = calHairline(context);
    final List<(int?, List<EthicsItem>)> years = groups(items);
    int index = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (int g = 0; g < years.length; g++) ...<Widget>[
          // The year, on a ring sitting on the line.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  width: _rail,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      if (g > 0)
                        PositionedDirectional(
                          top: 0.0,
                          bottom: 0.0,
                          child: Container(width: 2.0, color: line),
                        ),
                      Container(
                        width: 12.0,
                        height: 12.0,
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.onSurface,
                            width: 2.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                      vertical: 6.0,
                    ),
                    child: Row(
                      children: <Widget>[
                        Semantics(
                          header: true,
                          child: Text(
                            years[g].$1?.toString() ?? 'Undated',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 17.0,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (years[g].$1 != null &&
                            now - years[g].$1! > 10) ...<Widget>[
                          const SizedBox(width: 8.0),
                          Flexible(
                            child: Text(
                              'Older, counts less',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 13.0,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final EthicsItem item in years[g].$2)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    width: _rail,
                    child: Center(child: Container(width: 2.0, color: line)),
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(
                        top: 6.0,
                        bottom: 8.0,
                      ),
                      child: FadeUpIn(
                        index: index++,
                        child: ScandalCard(item, currentYear: now),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// One scandal, crisis, good practice or note as a card: how serious it is
/// (a coloured pill), the category, what it does to the score, the title,
/// the start of the story and where it comes from. Tap reads it all.
class ScandalCard extends StatelessWidget {
  const ScandalCard(this.item, {this.currentYear, super.key});

  final EthicsItem item;
  final int? currentYear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (IconData icon, Color color) = ethicsItemStyle(item);
    final (IconData catIcon, _) = ethicsCategoryStyle(item.category);
    final int points = EthicsScore.impact(item, currentYear: currentYear);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final String sources = item.sources.isEmpty
        ? ''
        : '${item.sources.length} ${item.sources.length == 1 ? 'source' : 'sources'} · ${item.sources.first.host}';
    return Semantics(
      button: true,
      label:
          '${item.title}. ${item.severityLabel}, ${ethicsCategoryShort(item.category)}'
          '${points == 0 ? '' : ', ${points > 0 ? 'plus' : 'minus'} ${points.abs()} points'}',
      excludeSemantics: true,
      child: PressScale(
        scale: 0.98,
        feedback: Haptics.open,
        onTap: () => showEthicsItemSheet(context, item),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(14.0, 14.0, 14.0, 12.0),
          decoration: BoxDecoration(
            color: calRow(context),
            borderRadius: BorderRadius.circular(18.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Wrap(
                      spacing: 8.0,
                      runSpacing: 6.0,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            8.0,
                            4.0,
                            10.0,
                            4.0,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(99.0),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(icon, size: 12.0, color: color),
                              const SizedBox(width: 4.0),
                              Flexible(
                                child: Text(
                                  item.severityLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textScaler: TextScaler.noScaling,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 12.0,
                                    fontWeight: FontWeight.w700,
                                    color: color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(catIcon, size: 13.0, color: muted),
                            const SizedBox(width: 4.0),
                            Text(
                              ethicsCategoryShort(item.category),
                              maxLines: 1,
                              textScaler: TextScaler.noScaling,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 12.0,
                                color: muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  if (points != 0)
                    Text(
                      '${points > 0 ? '+' : '−'}${points.abs()}',
                      textScaler: TextScaler.noScaling,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 15.0,
                        fontWeight: FontWeight.w800,
                        color: points > 0
                            ? kEthicsGood
                            : theme.colorScheme.onSurface,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  if (points != 0)
                    Text(
                      ' pts',
                      textScaler: TextScaler.noScaling,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12.0,
                        color: muted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10.0),
              Text(
                item.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 16.0,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                  letterSpacing: -0.2,
                ),
              ),
              if (item.text.isNotEmpty) ...<Widget>[
                const SizedBox(height: 5.0),
                Text(
                  item.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 14.0,
                    height: 1.35,
                    color: muted,
                  ),
                ),
              ],
              const SizedBox(height: 10.0),
              Row(
                children: <Widget>[
                  Icon(CupertinoIcons.link, size: 13.0, color: muted),
                  const SizedBox(width: 5.0),
                  Expanded(
                    child: Text(
                      sources.capFirst(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12.5,
                        color: muted,
                      ),
                    ),
                  ),
                  Text(
                    'Read',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2.0),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 13.0,
                    color: theme.colorScheme.onSurface,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
