import 'package:flutter/material.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/pages/product/product_page/overview/overview_card.dart';
import 'package:smooth_app/pages/product/product_page/overview/score_ring.dart';
import 'package:smooth_app/pages/product/product_page/overview/source_links.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/score_types.dart';

/// The "Ethics" section: the owner's score, per category, with every case
/// and its sources one tap away.
class EthicsDetails extends StatelessWidget {
  const EthicsDetails({required this.result, required this.ownerName, this.db, super.key});

  /// Null when the owner is unknown or not researched yet.
  final EthicsScoreResult? result;

  /// The owner as resolved by the ownership lookup, if any.
  final String? ownerName;

  /// For how many companies were researched and when.
  final EthicsDb? db;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final EthicsScoreResult? r = result;
    if (r == null) {
      return OverviewCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const OverviewHeading(
              title: 'Moral score',
              subtitle: 'Not rated yet',
              trailing: ScoreRing(score: null, size: 52.0),
            ),
            const SizedBox(height: MEDIUM_SPACE),
            Text(
              ownerName == null
                  ? 'We do not know who owns this product, so we cannot rate '
                        'the company behind it.'
                  : 'We have not researched $ownerName yet. We keep adding '
                        'companies, starting with the ones behind the most '
                        'products in the shops.',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
            FoldOut(title: 'How we rate companies', children: <Widget>[_MethodNote(db)]),
          ],
        ),
      );
    }
    return OverviewCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          OverviewHeading(
            title: 'Moral score',
            subtitle: '${r.band.label} · ${r.score}/100 · ${r.company.name}',
            trailing: ScoreRing(score: r.score, size: 52.0),
          ),
          if (ownerName != null && EthicsDb.splitOwner(ownerName!).length > 1)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: SMALL_SPACE),
              child: Text(
                '${EthicsDb.splitOwner(ownerName!).join(' and ')} are separate companies, and the product '
                'data does not say which one made it. The lower of their scores is shown (${r.company.name}).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
          if (r.categories.every((EthicsCategoryScore c) => c.isEmpty))
            Padding(
              padding: const EdgeInsetsDirectional.only(top: MEDIUM_SPACE),
              child: Text(
                'We found no documented problems or good practices for ${r.company.name} in public sources, '
                'so it keeps the starting score of ${EthicsScore.baseline}.',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
            )
          else
            for (final EthicsCategoryScore c in r.categories) _CategoryBlock(c),
          const SizedBox(height: SMALL_SPACE),
          FoldOut(title: 'How we rate companies', children: <Widget>[_MethodNote(db)]),
        ],
      ),
    );
  }
}

class _CategoryBlock extends StatefulWidget {
  const _CategoryBlock(this.category);

  final EthicsCategoryScore category;

  @override
  State<_CategoryBlock> createState() => _CategoryBlockState();
}

class _CategoryBlockState extends State<_CategoryBlock> {
  /// The worst cases first; the rest one tap away, so the section stays short.
  static const int _shown = 2;
  bool _expanded = false;

  /// "3 more: 2 cases, 1 good practice".
  static String moreLabel(final List<EthicsItem> hidden) {
    final int bad = hidden.where((EthicsItem i) => !i.isGood && !i.isNote).length;
    final int good = hidden.where((EthicsItem i) => i.isGood).length;
    final int notes = hidden.where((EthicsItem i) => i.isNote).length;
    String n(final int count, final String one) => '$count $one${count == 1 ? '' : 's'}';
    return 'Show ${hidden.length} more: ${<String>[
      if (bad > 0) n(bad, 'case'),
      if (good > 0) n(good, 'good practice'),
      if (notes > 0) n(notes, 'note'),
    ].join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final EthicsCategoryScore category = widget.category;
    final ThemeData theme = Theme.of(context);
    final List<EthicsItem> items = <EthicsItem>[
      ...category.issues,
      ...category.good,
      ...category.notes,
    ];
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: LARGE_SPACE),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  category.category.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '${category.score}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scoreTextColor(context, category.score),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          ScoreBar(score: category.score),
          const SizedBox(height: 4.0),
          Text(
            category.category.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: SMALL_SPACE),
              child: Text(
                'No documented cases found.',
                style: theme.textTheme.bodyMedium,
              ),
            )
          else ...<Widget>[
            for (final EthicsItem item in _expanded ? items : items.take(_shown)) EthicsItemTile(item),
            if (items.length > _shown)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsetsDirectional.zero),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                  label: Text(_expanded ? 'Show fewer' : moreLabel(items.sublist(_shown))),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// One case or practice; tap to read the details and open the sources.
class EthicsItemTile extends StatelessWidget {
  const EthicsItemTile(this.item, {super.key});

  final EthicsItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (IconData icon, Color color) = _style(item);
    final String meta = <String>[
      item.severityLabel,
      if (item.year != null && !item.isGood && !item.isNote) '${item.year}',
    ].join(' · ');
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsetsDirectional.zero,
        childrenPadding: const EdgeInsetsDirectional.only(
          start: 34.0,
          bottom: MEDIUM_SPACE,
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        leading: Icon(icon, color: color, size: 22.0),
        minTileHeight: 44.0,
        title: Text(
          item.title,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          meta,
          style: theme.textTheme.bodySmall?.copyWith(color: readableOn(color, theme.colorScheme.surface)),
        ),
        children: <Widget>[
          if (item.text.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: SMALL_SPACE),
              child: Text(
                item.text,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
              ),
            ),
          SourceLinks(item.sources, dense: true),
        ],
      ),
    );
  }

  static (IconData, Color) _style(final EthicsItem item) {
    if (item.isGood) {
      return (Icons.check_circle, ScoreBand.excellent.color);
    }
    if (item.isNote) {
      return (Icons.info_outline, const Color(0xFF767676));
    }
    return switch (item.severity) {
      3 => (Icons.error, ScoreBand.bad.color),
      2 => (Icons.warning_rounded, const Color(0xFF1E1A22)),
      _ => (Icons.report_outlined, ScoreBand.mediocre.color),
    };
  }
}

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "2026-11-08" -> "8 Nov 2026"; anything else as it is.
String formatShortDate(final String iso) {
  final DateTime? d = DateTime.tryParse(iso);
  return d == null ? iso : '${d.day} ${_months[d.month - 1]} ${d.year}';
}

class _MethodNote extends StatelessWidget {
  const _MethodNote(this.db);

  final EthicsDb? db;


  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text(
      'Each category starts at ${EthicsScore.baseline}. Documented problems '
      'subtract points (most for serious and recent cases), and each good '
      'practice adds ${EthicsScore.goodBonus}. Every case has sources. The '
      'score is the average of the three categories and says something '
      'about the company, not about this one product.'
      '${db == null || db!.updated.isEmpty ? '' : '\n\n${db!.companies.length} companies researched. '
                'Last updated ${formatShortDate(db!.updated)}.'}',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.4,
      ),
    );
  }
}
