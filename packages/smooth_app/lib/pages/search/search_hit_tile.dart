import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:smooth_app/pages/product/product_page/overview/product_overview.dart';
import 'package:smooth_app/query/product_query.dart';
import 'package:smooth_app/services/avoided_owners.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/product_search_service.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/cal_ui.dart';

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

/// Product photo with Cal AI's light grey placeholder (a cart, no colour).
class SearchHitImage extends StatelessWidget {
  const SearchHitImage(this.url, {this.size = 52.0, this.radius = 14.0});

  final String? url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Widget placeholder = Icon(
      CupertinoIcons.cart,
      size: size * 0.36,
      color: dark ? BrandColors.mutedDark : BrandColors.faint,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: size,
        color: dark ? BrandColors.hairlineDark : const Color(0xFFEFEEF4),
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

/// One product in the search suggestions or results, as a Cal AI row: the
/// photo flush on the left, the name and brand, and the owner as the big
/// line with its moral score.
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

  /// When loaded, the tile shows the owner from the offline database.
  final OwnershipLocalDb? ownerDb;

  /// When loaded, the owner's moral score is shown next to the owner.
  final EthicsDb? ethicsDb;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final OwnerInfo? info = ownerInfo(hit, ownerDb, ethicsDb);
    final String? owner = info?.displayName;
    final int? ethics = info?.ethicsScore;
    final bool avoided = info != null && AvoidedOwners.instance.isAvoided(info.names);
    final String subtitle = <String?>[hit.firstBrand, displayQuantity(hit.quantity)]
        .whereType<String>()
        .join(' · ');
    final double height = dense ? 76.0 : 92.0;
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(kCalSide, 0.0, kCalSide, dense ? 8.0 : 10.0),
      child: PressScale(
        scale: 0.98,
        onTap: onTap,
        child: Container(
          height: height,
          decoration: calRowDecoration(context),
          clipBehavior: Clip.antiAlias,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SearchHitImage(hit.imageUrl, size: height, radius: 0.0),
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(14.0, 0.0, 12.0, 0.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        hit.name ?? hit.barcode,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15.0, letterSpacing: -0.2),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 13.0, color: muted),
                        ),
                      if (owner != null) ...<Widget>[
                        const SizedBox(height: 4.0),
                        Row(
                          children: <Widget>[
                            Icon(
                              avoided ? CupertinoIcons.nosign : CupertinoIcons.building_2_fill,
                              size: 15.0,
                              color: theme.colorScheme.onSurface,
                            ),
                            const SizedBox(width: 6.0),
                            Flexible(
                              child: Text(
                                avoided ? 'You avoid $owner' : owner,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontSize: dense ? 15.0 : 16.0,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            if (ethics != null) ...<Widget>[
                              const SizedBox(width: 10.0),
                              Icon(Icons.balance_rounded, size: 13.0, color: theme.colorScheme.onSurface),
                              const SizedBox(width: 3.0),
                              Text(
                                '$ethics',
                                style: theme.textTheme.bodySmall?.copyWith(fontSize: 13.0, color: muted),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
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
