import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/pages/product/product_page/overview/product_overview.dart';
import 'package:smooth_app/query/product_query.dart';
import 'package:smooth_app/services/avoided_owners.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/product_search_service.dart';
import 'package:smooth_app/services/score_types.dart';

/// `en:denmark`-style tag for the user's country, as used in OFF's
/// `countries_tags` and in the offline ownership database. Null before the
/// app has set a country.
String? userCountryTag() {
  try {
    return countryTag(ProductQuery.getCountry());
  } catch (_) {
    return null;
  }
}

String countryTag(final OpenFoodFactsCountry country) =>
    'en:${country.name.toLowerCase().replaceAll('_', '-')}';

/// Languages products are named in, by country (OFF country code).
const Map<String, List<String>> countryLanguages = <String, List<String>>{
  'dk': <String>['da'], 'se': <String>['sv'], 'no': <String>['nb', 'no'], 'fi': <String>['fi', 'sv'],
  'is': <String>['is'], 'de': <String>['de'], 'at': <String>['de'], 'ch': <String>['de', 'fr', 'it'],
  'fr': <String>['fr'], 'be': <String>['fr', 'nl'], 'lu': <String>['fr', 'de'], 'nl': <String>['nl'],
  'it': <String>['it'], 'es': <String>['es', 'ca'], 'pt': <String>['pt'], 'pl': <String>['pl'],
  'cz': <String>['cs'], 'sk': <String>['sk'], 'hu': <String>['hu'], 'ro': <String>['ro'],
  'bg': <String>['bg'], 'gr': <String>['el'], 'cy': <String>['el'], 'hr': <String>['hr'],
  'si': <String>['sl'], 'ee': <String>['et'], 'lv': <String>['lv'], 'lt': <String>['lt'],
  'mt': <String>['mt', 'en'], 'ie': <String>['en'], 'gb': <String>['en'], 'uk': <String>['en'],
};

/// The languages of the user's country (where they shop), then the app's
/// language, then English: names on the shelf are rarely in English.
List<String> userSearchLangs() {
  String app = 'en';
  String? country;
  try {
    app = ProductQuery.getLanguage().offTag;
  } catch (_) {
    // English.
  }
  try {
    country = ProductQuery.getCountry().offTag;
  } catch (_) {
    // No country chosen yet.
  }
  return <String>{...?countryLanguages[country], app, 'en'}.toList();
}

/// Nutri-Score grades carry no colour in Owned (Cal AI's greys): the letter
/// says it. A and B in ink, C in mid grey, D and E outlined.
Color nutriscoreColor(final String grade) => const Color(0xFF1E1A22);

class NutriscoreBadge extends StatelessWidget {
  const NutriscoreBadge(this.grade, {this.size = 26.0});

  final String grade;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Nutri-Score ${grade.toUpperCase()}',
    excludeSemantics: true,
    child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF6F5FC),
        borderRadius: BorderRadius.circular(size / 4),
      ),
      child: Text(
        grade.toUpperCase(),
        style: TextStyle(
          color: const Color(0xFF1E1A22),
          fontWeight: FontWeight.w800,
          fontSize: size * 0.55,
          height: 1.0,
        ),
      ),
    ),
  );
}

/// Square product thumbnail with a neutral placeholder.
class SearchHitImage extends StatelessWidget {
  const SearchHitImage(this.url, {this.size = 52.0});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color background = Theme.of(context).colorScheme.surfaceContainerHighest;
    final Widget placeholder = Icon(
      Icons.shopping_basket_outlined,
      size: size * 0.5,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return ClipRRect(
      borderRadius: ANGULAR_BORDER_RADIUS,
      child: Container(
        width: size,
        height: size,
        color: background,
        alignment: Alignment.center,
        child: url == null
            ? placeholder
            : Image.network(
                url!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: (size * 3).round(),
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

/// One product in the search suggestions or results.
class SearchHitTile extends StatelessWidget {
  const SearchHitTile({
    required this.hit,
    required this.onTap,
    this.ownerDb,
    this.ethicsDb,
    this.dense = false,
  });

  final SearchHit hit;
  final VoidCallback onTap;

  /// When loaded, the tile shows "Ejet af X" from the offline database.
  final OwnershipLocalDb? ownerDb;

  /// When loaded, the owner's ethics score is shown next to the owner.
  final EthicsDb? ethicsDb;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final OwnerInfo? info = ownerInfo(hit, ownerDb, ethicsDb);
    final String? owner = info?.displayName;
    final int? ethics = info?.ethicsScore;
    final bool avoided = info != null && AvoidedOwners.instance.isAvoided(info.names);
    final Color ownerColor = avoided ? theme.colorScheme.error : theme.colorScheme.primary;
    final String subtitle = <String?>[hit.firstBrand, displayQuantity(hit.quantity)]
        .whereType<String>()
        .join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: LARGE_SPACE,
          vertical: dense ? SMALL_SPACE : BALANCED_SPACE,
        ),
        child: Row(
          children: <Widget>[
            SearchHitImage(hit.imageUrl, size: dense ? 44.0 : 56.0),
            const SizedBox(width: MEDIUM_SPACE),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    hit.name ?? hit.barcode,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (owner != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: 2.0),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            avoided ? Icons.block_rounded : Icons.account_tree_outlined,
                            size: 14.0,
                            color: ownerColor,
                          ),
                          const SizedBox(width: VERY_SMALL_SPACE),
                          Flexible(
                            child: Text(
                              avoided ? 'You avoid $owner' : 'Owned by $owner',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: ownerColor,
                                fontWeight: avoided ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                          ),
                          if (ethics != null) ...<Widget>[
                            const SizedBox(width: SMALL_SPACE),
                            EthicsChip(score: ethics),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Owner from the offline database (hidden when it only repeats the
  /// brand), with the ethics company's display name and score when known.
  static OwnerInfo? ownerInfo(
    final SearchHit hit,
    final OwnershipLocalDb? db,
    final EthicsDb? ethicsDb,
  ) {
    if (db == null) {
      return null;
    }
    try {
      final LocalOwnerResult? r = db.lookup(
        barcode: hit.barcode,
        brands: hit.brands.join(','),
        countryTags: hit.countriesTags,
      );
      if (r == null || r.owner.trim().isEmpty) {
        return null;
      }
      final EthicsCompany? company = ethicsDb?.forOwner(r.owner, chain: r.ethicsChain);
      final String name = EthicsDb.displayName(r.owner.trim(), company);
      final bool repeatsBrand = hit.brands.any(
        (String b) =>
            b.toLowerCase() == name.toLowerCase() ||
            b.toLowerCase() == r.owner.trim().toLowerCase(),
      );
      if (repeatsBrand && company == null) {
        return null;
      }
      return OwnerInfo(
        displayName: name,
        names: <String>[name, r.owner, ...r.ethicsChain],
        ethicsScore: company == null ? null : _scores.putIfAbsent(company.id, () => EthicsScore.compute(company).score),
      );
    } catch (_) {
      return null;
    }
  }

  static final Map<String, int> _scores = <String, int>{};
}

class OwnerInfo {
  const OwnerInfo({required this.displayName, this.ethicsScore, this.names = const <String>[]});

  final String displayName;
  final int? ethicsScore;

  /// Every name the owner goes by (display, database, chain, controller).
  final List<String> names;
}

/// Small "Etik 55" pill in the owner's ethics colour.
class EthicsChip extends StatelessWidget {
  const EthicsChip({required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    final Color color = ScoreBand.of(score).color;
    final Color text = readableOn(color, Theme.of(context).colorScheme.surface);
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 6.0, vertical: 1.0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Text(
        'Moral $score',
        style: TextStyle(
          color: text,
          fontSize: 11.0,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
