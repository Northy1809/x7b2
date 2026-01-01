import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/database/dao_ownership_scan.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/pages/owner/moral_score_page.dart';
import 'package:smooth_app/pages/owner/owner_page.dart';
import 'package:smooth_app/pages/product/product_page/overview/alternatives_section.dart';
import 'package:smooth_app/pages/product/product_page/overview/health_score_page.dart';
import 'package:smooth_app/pages/product/product_page/overview/owner_section.dart';
import 'package:smooth_app/pages/product/product_page/overview/share_card.dart';
import 'package:smooth_app/pages/product/product_page/tabs/ownership/ownership_provider.dart';
import 'package:smooth_app/pages/scan/result/result_sheet_parts.dart';
import 'package:smooth_app/pages/scan/result/scan_sheet_scaffold.dart';
import 'package:smooth_app/query/product_query.dart';
import 'package:smooth_app/services/avoided_owners.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/health_score.dart';
import 'package:smooth_app/services/ownership_service.dart';

/// The product page, as a sheet over the photo: who owns it (logo and
/// name), the moral and health scores as two charts, and a short list of
/// rows. Every explanation (the cases behind the moral score, the nutrition
/// behind the health score, the ownership chain, alternatives, the full
/// Open Food Facts record) waits behind a tap.
class ProductOverview extends StatelessWidget {
  const ProductOverview({
    required this.product,
    required this.onShowDetails,
    this.leading,
    this.ownershipProvider,
    this.ethicsDb,
    this.showAlternatives = true,
    this.photo,
  });

  final Product product;

  /// The camera frame the barcode was read from: shown behind the sheet
  /// instead of the product's own photo.
  final Uint8List? photo;
  final VoidCallback onShowDetails;

  /// Back button of the app bar.
  final Widget? leading;

  /// Off in tests and previews that have no network.
  final bool showAlternatives;

  /// For tests; normally created here.
  final OwnershipProvider? ownershipProvider;
  final Future<EthicsDb> Function()? ethicsDb;

  @override
  Widget build(BuildContext context) {
    final Widget body = _OverviewPage(
      product: product,
      onShowDetails: onShowDetails,
      leading: leading,
      ethicsDb: ethicsDb ?? EthicsDb.load,
      showAlternatives: showAlternatives,
      photo: photo,
    );
    if (ownershipProvider != null) {
      return ChangeNotifierProvider<OwnershipProvider>.value(
        value: ownershipProvider!,
        child: body,
      );
    }
    return ChangeNotifierProvider<OwnershipProvider>(
      create: (BuildContext context) => OwnershipProvider(
        product: product,
        countryCode: ProductQuery.getCountry().offTag,
        service: OwnershipService(),
        scanDao: DaoOwnershipScan(context.read<LocalDatabase>()),
      ),
      child: body,
    );
  }
}

class _OverviewPage extends StatefulWidget {
  const _OverviewPage({
    required this.product,
    required this.onShowDetails,
    required this.leading,
    required this.ethicsDb,
    required this.showAlternatives,
    required this.photo,
  });

  final Product product;
  final VoidCallback onShowDetails;
  final Widget? leading;
  final Future<EthicsDb> Function() ethicsDb;
  final bool showAlternatives;
  final Uint8List? photo;

  @override
  State<_OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<_OverviewPage> {
  late Future<EthicsDb> _ethicsDb;

  bool get _isFood =>
      (widget.product.productType ?? ProductType.food) == ProductType.food;

  /// A health score only makes sense for food (and needs its nutrition data).
  bool get _showHealth =>
      _isFood ||
      (widget.product.productType == ProductType.petFood &&
          widget.product.nutriscore != null);

  bool get _alternativesAllowed => widget.showAlternatives && _isFood;

  @override
  void initState() {
    super.initState();
    _ethicsDb = widget.ethicsDb();
  }

  ImageProvider? get _photo {
    if (widget.photo != null) {
      return MemoryImage(widget.photo!);
    }
    final String? url =
        widget.product.imageFrontUrl ?? widget.product.imageFrontSmallUrl;
    return url == null ? null : NetworkImage(url);
  }

  @override
  Widget build(BuildContext context) {
    final OwnershipProvider ownership = context.watch<OwnershipProvider>();
    final HealthScoreResult health = HealthScore.fromProduct(widget.product);
    final String? owner = ownership.status == OwnershipStatus.resolved
        ? ownership.result?.ownerCompany
        : null;
    final String title =
        productDisplayName(widget.product) ?? 'Unknown product';

    return FutureBuilder<EthicsDb>(
      future: _ethicsDb,
      builder: (BuildContext context, AsyncSnapshot<EthicsDb> snapshot) {
        final EthicsDb? db = snapshot.data;
        final EthicsCompany? company = owner == null || db == null
            ? null
            : db.forOwner(
                owner,
                chain: ownership.result?.ethicsChain ?? const <String>[],
              );
        final EthicsScoreResult? ethics = company == null
            ? null
            : EthicsScore.compute(company);
        final bool ethicsLoading =
            ownership.status == OwnershipStatus.loading ||
            (owner != null && snapshot.connectionState != ConnectionState.done);
        final String? ownerName = owner == null
            ? null
            : EthicsDb.displayName(owner, company);
        final BrandOwnerResult? result = ownership.result;
        final List<String> chain = result == null || ownerName == null
            ? const <String>[]
            : OwnerSection.ownerChain(widget.product, result, ownerName);
        final String subtitle = <String?>[
          title,
          displayBrand(widget.product.brands),
          displayQuantity(widget.product.quantity),
        ].where((String? s) => s != null && s.trim().isNotEmpty).join(' · ');

        void fixOwner() =>
            OwnerSection.correct(context, widget.product, ownership, ownerName);
        void openOwner() => ownerName == null
            ? fixOwner()
            : Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => OwnerPage(
                    name: ownerName,
                    dbName: owner,
                    company: company,
                    controlledBy: result?.controlledBy,
                  ),
                ),
              );

        return ScanSheetScaffold(
          animateIn: widget.photo != null,
          liftPhoto: widget.photo != null,
          photo: ScanPhoto(image: _photo, packshot: widget.photo == null),
          title: ownerName ?? title,
          leading: widget.leading == null
              ? null
              : _GlassLeading(child: widget.leading!),
          actions: <Widget>[
            if (ownerName != null)
              GlassIconButton(
                tooltip: 'Share who owns it',
                icon: Icons.ios_share_rounded,
                onPressed: () => showShareCard(
                  context,
                  ShareCardData(
                    title: title,
                    brand: displayBrand(widget.product.brands),
                    owner: ownerName,
                    health: _showHealth ? health.score : null,
                    ethics: ethics?.score,
                    text: shareText(
                      title,
                      ownerName,
                      ethics?.score,
                      widget.product.barcode,
                    ),
                  ),
                ),
              ),
          ],
          bottomBar: SheetActions(secondary: 'Fix owner', onSecondary: fixOwner),
          slivers: <Widget>[
            SliverPadding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                20.0,
                6.0,
                20.0,
                0.0,
              ),
              sliver: SliverList.list(
                children: <Widget>[
                  ListenableBuilder(
                    listenable: AvoidedOwners.instance,
                    builder: (BuildContext context, _) => OwnerResultHeader(
                      ownerName: ownerName,
                      loading: ownership.status == OwnershipStatus.loading,
                      logoNames: <String?>[
                        ownerName,
                        owner,
                        ...?result?.ethicsChain,
                      ],
                      subtitle: subtitle,
                      corrected: result?.source == BrandOwnerSource.user,
                      avoided:
                          ownerName != null &&
                          AvoidedOwners.instance.isAvoided(<String?>[
                            ownerName,
                            owner,
                            ...?result?.ethicsChain,
                          ]),
                      onTap: openOwner,
                    ),
                  ),
                  const SizedBox(height: 18.0),
                  ScorePair(
                    moral: ethics?.score,
                    moralLoading: ethicsLoading,
                    moralVerdict: ethics == null && !ethicsLoading
                        ? 'Not rated yet'
                        : null,
                    health: _showHealth ? health.score : null,
                    healthVerdict: !_showHealth
                        ? 'Not for this product'
                        : health.score == null
                        ? (health.notApplicable
                              ? 'Not scored'
                              : 'Missing data')
                        : null,
                    onMoralTap: ethicsLoading
                        ? null
                        : () => MoralScorePage.open(
                            context,
                            result: ethics,
                            ownerName: owner,
                            db: db,
                          ),
                    onHealthTap: !_showHealth
                        ? null
                        : () => HealthScorePage.open(
                            context,
                            result: health,
                            productName: title,
                            photo: _photo,
                          ),
                  ),
                  const SizedBox(height: 22.0),
                  MoreRows(
                    rows: <MoreRow>[
                      MoreRow(
                        icon: Icons.account_tree_outlined,
                        title: 'Ownership',
                        detail: chain.length > 1
                            ? chain.join(' → ')
                            : ownerName == null
                            ? 'Help us find the owner'
                            : 'Where the answer comes from',
                        onTap: () => DetailsPage.open(
                          context,
                          'Ownership',
                          ChangeNotifierProvider<OwnershipProvider>.value(
                            value: ownership,
                            child: OwnerSection(
                              product: widget.product,
                              provider: ownership,
                              company: company,
                            ),
                          ),
                        ),
                      ),
                      if (_alternativesAllowed)
                        MoreRow(
                          icon: Icons.swap_horiz_rounded,
                          title: 'Better alternatives',
                          detail: 'Similar products from other owners',
                          onTap: () => DetailsPage.open(
                            context,
                            'Better alternatives',
                            AlternativesSection(
                              product: widget.product,
                              onLoaded: (_) {},
                            ),
                          ),
                        ),
                      MoreRow(
                        icon: Icons.article_outlined,
                        title: 'All product details',
                        detail: 'Ingredients, nutrition, environment',
                        onTap: widget.onShowDetails,
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      12.0,
                      18.0,
                      12.0,
                      0.0,
                    ),
                    child: Text(
                      'Scores are a guide, built on open data from Open Food '
                      'Facts, Wikidata and public sources.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The page's own back button, on the same frosted circle as the others.
class _GlassLeading extends StatelessWidget {
  const _GlassLeading({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.all(4.0),
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
          child: Material(
            color: Colors.black.withValues(alpha: 0.32),
            shape: const CircleBorder(),
            child: SizedBox.square(
              dimension: 48.0,
              child: Center(
                child: IconTheme.merge(
                  data: const IconThemeData(color: Colors.white),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "KitKat is owned by Nestlé (moral score 13/100)." plus a link to the
/// product's open data.
String shareText(
  final String product,
  final String owner,
  final int? ethics,
  final String? barcode,
) {
  final StringBuffer sb = StringBuffer('$product is owned by $owner');
  if (ethics != null) {
    sb.write(' (moral score $ethics/100)');
  }
  sb.write('. Found with Owned.');
  if (barcode != null && barcode.isNotEmpty) {
    sb.write(' https://world.openfoodfacts.org/product/$barcode');
  }
  return sb.toString();
}

/// The first brand on the pack, for display: "carrefour bio" (typed in
/// lower case by a contributor) becomes "Carrefour Bio"; any other casing
/// is kept as the brand writes it.
String? displayBrand(final String? brands) {
  final String? b = brands?.split(',').first.trim();
  if (b == null || b.isEmpty) {
    return null;
  }
  if (b != b.toLowerCase()) {
    return b;
  }
  return b
      .split(' ')
      .map((String w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
      .join(' ');
}

/// "400 g e" or "400 g ℮" -> "400 g": the EU estimated-quantity mark is
/// noise on a screen.
String? displayQuantity(final String? quantity) {
  // A lone "e" after a unit, never the end of a word ("1 pièce").
  final String? q = quantity
      ?.replaceAll(RegExp(r'(?:\s*℮|(?<=\d\s?[a-zA-Z]{1,2})\s+e)\s*$'), '')
      .trim();
  return q == null || q.isEmpty ? null : q;
}

/// Name in the user's language, then the generic name, then any language.
String? productDisplayName(final Product product) {
  final Map<OpenFoodFactsLanguage, String>? names =
      product.productNameInLanguages;
  final String? local = names?[ProductQuery.getLanguage()]?.trim();
  if (local != null && local.isNotEmpty) {
    return local;
  }
  final String? generic = product.productName?.trim();
  if (generic != null && generic.isNotEmpty) {
    return generic;
  }
  for (final String n in names?.values ?? const <String>[]) {
    if (n.trim().isNotEmpty) {
      return n.trim();
    }
  }
  return null;
}
