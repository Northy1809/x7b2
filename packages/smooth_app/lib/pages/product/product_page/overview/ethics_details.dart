import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/pages/product/product_page/overview/overview_card.dart';
import 'package:smooth_app/pages/product/product_page/overview/score_ring.dart';
import 'package:smooth_app/pages/product/product_page/overview/source_links.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/cal_ui.dart';

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
            FoldOut(title: 'How we rate companies', children: <Widget>[EthicsMethodNote(db)]),
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
            for (final EthicsCategoryScore c in r.categories) EthicsCategoryBlock(c),
          const SizedBox(height: SMALL_SPACE),
          FoldOut(title: 'How we rate companies', children: <Widget>[EthicsMethodNote(db)]),
        ],
      ),
    );
  }
}

/// Icon and Cal AI accent for each category, like Cal AI's protein (red),
/// carbs (orange) and fats (blue).
(IconData, Color) ethicsCategoryStyle(final EthicsCategory category) => switch (category) {
  EthicsCategory.climate => (CupertinoIcons.globe, BrandColors.accentBlue),
  EthicsCategory.people => (CupertinoIcons.person_2_fill, BrandColors.accentRed),
  EthicsCategory.conduct => (CupertinoIcons.checkmark_shield_fill, BrandColors.accentOrange),
};

/// The short name for small cards: "Climate", "People", "Honesty".
String ethicsCategoryShort(final EthicsCategory category) => switch (category) {
  EthicsCategory.climate => 'Climate',
  EthicsCategory.people => 'People',
  EthicsCategory.conduct => 'Honesty',
};

/// One category: its icon, name and score over a coloured bar, then the
/// worst cases as grey Cal rows (the rest one tap away).
class EthicsCategoryBlock extends StatefulWidget {
  const EthicsCategoryBlock(this.category, {this.topPadding = LARGE_SPACE, super.key});

  final EthicsCategoryScore category;
  final double topPadding;

  @override
  State<EthicsCategoryBlock> createState() => _EthicsCategoryBlockState();
}

class _EthicsCategoryBlockState extends State<EthicsCategoryBlock> {
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
    final (IconData icon, Color color) = ethicsCategoryStyle(category.category);
    final List<EthicsItem> items = <EthicsItem>[
      ...category.issues,
      ...category.good,
      ...category.notes,
    ];
    return Padding(
      padding: EdgeInsetsDirectional.only(top: widget.topPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 18.0, color: color),
              const SizedBox(width: 8.0),
              Expanded(
                child: Text(
                  category.category.label,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 16.0),
                ),
              ),
              Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(text: '${category.score}'),
                    TextSpan(
                      text: '/100',
                      style: TextStyle(fontSize: 12.0, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10.0),
          ScoreBar(score: category.score, color: color),
          const SizedBox(height: 8.0),
          Text(
            category.category.description,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 13.0),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 10.0),
              child: Text('No documented cases found.', style: theme.textTheme.bodyMedium),
            )
          else ...<Widget>[
            const SizedBox(height: 4.0),
            AnimatedSize(
              duration: CalMotion.page,
              curve: CalMotion.curve,
              alignment: AlignmentDirectional.topStart,
              child: Column(
                children: <Widget>[
                  for (final EthicsItem item in _expanded ? items : items.take(_shown)) EthicsItemTile(item),
                ],
              ),
            ),
            if (items.length > _shown)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 8.0),
                child: Semantics(
                  button: true,
                  child: PressScale(
                    scale: 0.98,
                    feedback: Haptics.select,
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Container(
                      height: 46.0,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(color: calHairline(context)),
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              _expanded ? 'Show fewer' : moreLabel(items.sublist(_shown)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 14.0),
                            ),
                          ),
                          const SizedBox(width: 6.0),
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0.0,
                            duration: CalMotion.page,
                            child: const Icon(CupertinoIcons.chevron_down, size: 14.0),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// One case or practice as a grey Cal row; tap opens a sheet with the
/// whole story and its sources.
class EthicsItemTile extends StatelessWidget {
  const EthicsItemTile(this.item, {super.key});

  final EthicsItem item;

  String get _meta => <String>[
    item.severityLabel,
    if (item.year != null && !item.isGood && !item.isNote) '${item.year}',
  ].join(' · ');

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final (IconData icon, Color color) = _style(item);
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 8.0),
      child: Semantics(
        button: true,
        label: '${item.title}, $_meta',
        excludeSemantics: true,
        child: PressScale(
          scale: 0.98,
          feedback: Haptics.open,
          onTap: () => showEthicsItemSheet(context, item),
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(12.0, 12.0, 12.0, 12.0),
            decoration: BoxDecoration(
              color: dark ? BrandColors.fillDark : BrandColors.row,
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 36.0,
                  height: 36.0,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(icon, size: 18.0, color: color),
                ),
                const SizedBox(width: 12.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 15.0, height: 1.25),
                      ),
                      const SizedBox(height: 3.0),
                      Text(
                        _meta,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 13.0,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8.0),
                Icon(CupertinoIcons.chevron_right, size: 16.0, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static (IconData, Color) _style(final EthicsItem item) {
    if (item.isGood) {
      return (CupertinoIcons.checkmark_alt, const Color(0xFF34A853));
    }
    if (item.isNote) {
      return (CupertinoIcons.info, const Color(0xFF767676));
    }
    return switch (item.severity) {
      3 => (CupertinoIcons.exclamationmark, BrandColors.accentRed),
      2 => (CupertinoIcons.exclamationmark_triangle_fill, BrandColors.accentOrange),
      _ => (CupertinoIcons.minus, const Color(0xFF767676)),
    };
  }
}

/// The whole case in a white sheet: icon and meta, the title big, the
/// story, then its sources.
Future<void> showEthicsItemSheet(final BuildContext context, final EthicsItem item) {
  final (IconData icon, Color color) = EthicsItemTile._style(item);
  final String meta = EthicsItemTile(item)._meta;
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
          padding: EdgeInsetsDirectional.fromSTEB(
            kCalSide,
            0.0,
            kCalSide,
            MediaQuery.paddingOf(context).bottom + 24.0,
          ),
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
                    child: Icon(icon, size: 16.0, color: color),
                  ),
                  const SizedBox(width: 10.0),
                  Text(
                    meta,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 14.0),
              Text(
                item.title,
                style: theme.textTheme.titleLarge?.copyWith(fontSize: 24.0, fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1.2),
              ),
              if (item.text.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12.0),
                Text(item.text, style: theme.textTheme.bodyLarge?.copyWith(height: 1.45, fontSize: 16.0)),
              ],
              if (item.sources.isNotEmpty) ...<Widget>[
                const SizedBox(height: 20.0),
                const CalSectionTitle('Sources'),
                const SizedBox(height: 8.0),
                SourceLinks(item.sources),
              ],
            ],
          ),
        ),
      );
    },
  );
}

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "2026-11-08" -> "8 Nov 2026"; anything else as it is.
String formatShortDate(final String iso) {
  final DateTime? d = DateTime.tryParse(iso);
  return d == null ? iso : '${d.day} ${_months[d.month - 1]} ${d.year}';
}

class EthicsMethodNote extends StatelessWidget {
  const EthicsMethodNote(this.db);

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
