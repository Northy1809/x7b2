import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:smooth_app/cards/product_cards/smooth_product_image.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/pages/product/product_page/overview/product_overview.dart';
import 'package:smooth_app/pages/product/product_page/overview/score_ring.dart';
import 'package:smooth_app/pages/product/product_page/tabs/ownership/ownership_provider.dart';
import 'package:smooth_app/pages/search/search_hit_tile.dart';
import 'package:smooth_app/services/avoided_owners.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/health_score.dart';
import 'package:smooth_app/services/owner_overrides.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/ownership_service.dart';
import 'package:smooth_app/services/score_types.dart';
import 'package:smooth_app/themes/brand_colors.dart';

/// Compact answer right after a scan: who owns it, and the two scores.
/// Offline data first, so it usually shows instantly; an unknown brand is
/// looked up on Wikidata (shared with the product page's lookup).
class ScanQuickSummary extends StatefulWidget {
  const ScanQuickSummary({required this.product, this.heroTag});

  final Product product;
  final String? heroTag;

  @override
  State<ScanQuickSummary> createState() => _ScanQuickSummaryState();
}

class _ScanQuickSummaryState extends State<ScanQuickSummary> {
  LocalOwnerResult? _owner;
  EthicsCompany? _company;
  bool _ownerLoaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    OwnerOverrides.instance.addListener(_onCorrection);
  }

  @override
  void dispose() {
    OwnerOverrides.instance.removeListener(_onCorrection);
    super.dispose();
  }

  /// The user corrected an owner on the product page: show it here too.
  void _onCorrection() => unawaited(_load());

  Future<void> _load() async {
    LocalOwnerResult? owner;
    EthicsCompany? company;
    try {
      final OwnershipLocalDb db = await OwnershipLocalDb.load();
      final Product p = widget.product;
      owner = db.lookup(
        barcode: p.barcode ?? '',
        brands: p.brands,
        countryTags: p.countriesTags ?? const <String>[],
        embCodeTags: OwnershipProvider.embCodeTags(p.embCodes),
      );
      // Not in the offline data: ask Wikidata for the brand right away, so
      // the card can answer without opening the product page.
      final String? brand = p.getFirstBrand()?.trim();
      if (owner == null && brand != null && brand.isNotEmpty) {
        final BrandOwnerResult? online = await OwnershipService().lookupWikidata(brand);
        if (online != null) {
          owner = LocalOwnerResult(
            owner: online.ownerCompany,
            source: LocalOwnerSource.other,
            chain: online.ownerChain,
          );
        }
      }
      if (owner != null) {
        final EthicsDb ethics = await EthicsDb.load();
        company = ethics.forOwner(owner.owner, chain: owner.ethicsChain);
      }
    } catch (_) {
      // Offline data missing: the card still shows the health score.
    }
    if (mounted) {
      setState(() {
        _owner = owner;
        _company = company;
        _ownerLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Product product = widget.product;
    final HealthScoreResult health = HealthScore.fromProduct(product);
    final int? ethics = _company == null ? null : EthicsScore.compute(_company!).score;
    final String? ownerName = _owner == null ? null : EthicsDb.displayName(_owner!.owner, _company);
    final String sub = <String?>[
      displayBrand(product.brands),
      displayQuantity(product.quantity),
    ].where((String? s) => s != null && s.trim().isNotEmpty).join(' · ');

    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(MEDIUM_SPACE),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ProductPicture.fromProduct(
                product: product,
                imageField: ImageField.FRONT,
                fallbackUrl: product.imageFrontUrl,
                allowAlternativeLanguage: true,
                size: const Size.square(72.0),
                heroTag: widget.heroTag,
                borderRadius: ANGULAR_BORDER_RADIUS,
                noImageBuilder: (_) => const SearchHitImage(null, size: 72.0),
              ),
              const SizedBox(width: MEDIUM_SPACE),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      productDisplayName(product) ?? product.barcode ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, height: 1.2),
                    ),
                    if (sub.isNotEmpty)
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    const SizedBox(height: 6.0),
                    ListenableBuilder(
                      listenable: AvoidedOwners.instance,
                      builder: (BuildContext context, _) {
                        final String? avoided = _owner == null
                            ? null
                            : AvoidedOwners.instance.avoidedName(<String?>[
                                ownerName,
                                _owner!.owner,
                                ..._owner!.ethicsChain,
                              ]);
                        if (avoided != null) {
                          return Row(
                            children: <Widget>[
                              Icon(Icons.block_rounded, size: 16.0, color: theme.colorScheme.error),
                              const SizedBox(width: 6.0),
                              Expanded(
                                child: Text(
                                  'You avoid $avoided',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.error,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }
                        return Row(
                          children: <Widget>[
                            Container(
                              width: 12.0,
                              height: 12.0,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: ownerName == null ? theme.colorScheme.outline : BrandColors.gold,
                              ),
                            ),
                            const SizedBox(width: 6.0),
                            Expanded(
                              child: Text.rich(
                                !_ownerLoaded
                                    ? const TextSpan(text: 'Finding the owner…')
                                    : ownerName == null
                                    ? const TextSpan(text: 'Tap to see who owns it')
                                    : TextSpan(
                                        children: <InlineSpan>[
                                          const TextSpan(text: 'Owned by '),
                                          TextSpan(
                                            text: ownerName,
                                            style: const TextStyle(fontWeight: FontWeight.w800),
                                          ),
                                        ],
                                      ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: MEDIUM_SPACE),
          Row(
            children: <Widget>[
              if ((product.productType ?? ProductType.food) == ProductType.food) ...<Widget>[
                Expanded(
                  child: _MiniScore(title: 'Health', score: health.score, label: health.band?.label ?? 'No score'),
                ),
                const SizedBox(width: SMALL_SPACE),
              ],
              Expanded(
                child: _MiniScore(
                  title: 'Moral',
                  score: ethics,
                  label: ethics != null ? ScoreBand.of(ethics).label : (_ownerLoaded ? 'Not rated yet' : '…'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniScore extends StatelessWidget {
  const _MiniScore({required this.title, required this.score, required this.label});

  final String title;
  final int? score;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color color = score == null ? theme.colorScheme.outline : ScoreBand.of(score!).color;
    return MergeSemantics(child: Container(
      padding: const EdgeInsetsDirectional.all(SMALL_SPACE),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: ANGULAR_BORDER_RADIUS),
      child: Row(
        children: <Widget>[
          ScoreRing(score: score, size: 44.0),
          const SizedBox(width: SMALL_SPACE),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: score == null ? theme.colorScheme.onSurfaceVariant : scoreTextColor(context, score!),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ));
  }
}
