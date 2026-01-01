import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/pages/owner/owner_correction_page.dart';
import 'package:smooth_app/pages/owner/owner_page.dart';
import 'package:smooth_app/pages/product/product_page/overview/overview_card.dart';
import 'package:smooth_app/pages/product/product_page/overview/product_overview.dart';
import 'package:smooth_app/pages/product/product_page/tabs/ownership/ownership_provider.dart';
import 'package:smooth_app/pages/product/product_page/tabs/ownership/ownership_result_view.dart';
import 'package:smooth_app/pages/product/product_page/tabs/ownership/product_ownership_tab.dart';
import 'package:smooth_app/pages/search/search_page.dart';
import 'package:smooth_app/pages/search/search_product_helper.dart';
import 'package:smooth_app/services/avoided_owners.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/owner_overrides.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/ownership_service.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_ui.dart';
import 'package:smooth_app/widgets/company_logo.dart';

/// "Who owns it": the owner, a short note on the company, and the trail
/// from the brand on the pack up to the top owner.
class OwnerSection extends StatelessWidget {
  const OwnerSection({
    required this.product,
    required this.provider,
    this.company,
    super.key,
  });

  final Product product;
  final OwnershipProvider provider;

  /// The researched company behind the owner, for a cleaner display name
  /// and a short description.
  final EthicsCompany? company;

  /// The correction page for [product] ("Fix owner" under the sheet).
  static Future<void> correct(
    final BuildContext context,
    final Product product,
    final OwnershipProvider provider,
    final String? current,
  ) => OwnerSection(product: product, provider: provider)._openCorrection(context, current);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    switch (provider.status) {
      case OwnershipStatus.loading:
        return const OverviewCard(
          child: OwnershipLoadingView(label: 'Finding who owns this…'),
        );
      case OwnershipStatus.resolved:
        final BrandOwnerResult r = provider.result!;
        final String ownerName = EthicsDb.displayName(r.ownerCompany, company);
        final List<String> chain = ownerChain(product, r, ownerName);
        return OverviewCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionLabel('Who owns it'),
              AvoidedBanner(names: <String>[ownerName, r.ownerCompany, ...r.ethicsChain]),
              const SizedBox(height: MEDIUM_SPACE),
              InkWell(
                borderRadius: ANGULAR_BORDER_RADIUS,
                onTap: () => openOwnerPage(
                  context,
                  name: ownerName,
                  dbName: r.ownerCompany,
                  company: company,
                  controlledBy: r.controlledBy,
                ),
                child: Row(
                  children: <Widget>[
                    OwnerAvatar(name: ownerName),
                    const SizedBox(width: MEDIUM_SPACE),
                    Expanded(
                      child: Text(
                        ownerName,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
              if (company?.about.isNotEmpty ?? false)
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: MEDIUM_SPACE),
                  child: Text(
                    company!.about,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              if (chain.length > 1 || r.controlledBy != null) ...<Widget>[
                const SizedBox(height: LARGE_SPACE),
                OwnerTrail(chain: chain, controlledBy: r.controlledBy),
              ],
              AlsoOwns(
                owners: <String>[r.ownerCompany, ownerName],
                ownerName: ownerName,
                exclude: chain.first,
              ),
              const SizedBox(height: MEDIUM_SPACE),
              Row(
                children: <Widget>[
                  Expanded(child: OwnershipSourceLine(source: r.source)),
                  TextButton(
                    onPressed: () => _openCorrection(context, ownerName),
                    child: const Text('Not right?'),
                  ),
                ],
              ),
            ],
          ),
        );
      case OwnershipStatus.pendingConfirmation:
      case OwnershipStatus.noBrand:
      case OwnershipStatus.unresolved:
        return OverviewCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionLabel('Who owns it'),
              const SizedBox(height: MEDIUM_SPACE),
              Row(
                children: <Widget>[
                  const OwnerAvatar(name: null),
                  const SizedBox(width: MEDIUM_SPACE),
                  Expanded(
                    child: Text(
                      'Owner not found yet',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: MEDIUM_SPACE),
              Text(
                'We could not match this brand to a company. Type the brand '
                'or snap the back of the pack and we will look again.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: MEDIUM_SPACE),
              FilledButton.icon(
                onPressed: () => _openFinder(context),
                icon: const Icon(Icons.search),
                label: const Text('Help find the owner'),
              ),
              TextButton(
                onPressed: () => _openCorrection(context, null),
                child: const Text('I know who owns it'),
              ),
            ],
          ),
        );
    }
  }

  Future<void> _openCorrection(final BuildContext context, final String? current) async {
    // The provider listens to OwnerOverrides and looks again by itself.
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext routeContext) => OwnerCorrectionPage(
          barcode: product.barcode ?? '',
          brands: product.brands,
          currentOwner: current,
          onLookAgain: () => _openFinder(
            routeContext,
            askUser: true,
            // Saved: close the finder and the correction page, then look again.
            onUseOwner: (String owner) async {
              await OwnerOverrides.instance.set(barcode: product.barcode ?? '', brands: product.brands, owner: owner);
              if (routeContext.mounted) {
                Navigator.of(routeContext)
                  ..pop()
                  ..pop(true);
              }
            },
          ),
        ),
      ),
    );
  }

  void _openFinder(
    final BuildContext context, {
    final bool askUser = false,
    final ValueChanged<String>? onUseOwner,
  }) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (BuildContext routeContext) => Scaffold(
        appBar: const CalTopBar(title: 'Find the owner'),
        body: ProductOwnershipTab(
          product,
          askUser: askUser,
          onUseOwner:
              onUseOwner ??
              (String owner) async {
                await OwnerOverrides.instance.set(barcode: product.barcode ?? '', brands: product.brands, owner: owner);
                if (routeContext.mounted) {
                  Navigator.of(routeContext).pop();
                }
              },
        ),
      ),
    ),
  );

  /// "Brand › … › Owner", starting from the product's own brand.
  static List<String> ownerChain(
    final Product product,
    final BrandOwnerResult r,
    final String ownerName,
  ) {
    final List<String> chain = <String>[...r.ownerChain];
    final String? brand = displayBrand(product.brands);
    if (brand != null &&
        brand.isNotEmpty &&
        (chain.isEmpty || chain.first.toLowerCase() != brand.toLowerCase())) {
      chain.insert(0, brand);
    }
    if (chain.isNotEmpty && chain.last == r.ownerCompany) {
      chain.removeLast();
    }
    chain.add(ownerName);
    final List<String> unique = <String>[];
    for (final String c in chain) {
      if (unique.isEmpty || unique.last.toLowerCase() != c.toLowerCase()) {
        unique.add(c);
      }
    }
    return unique;
  }
}

/// "Nestlé also owns": the owner's most scanned other brands.
class AlsoOwns extends StatelessWidget {
  const AlsoOwns({
    required this.owners,
    required this.ownerName,
    required this.exclude,
    this.localDb,
    super.key,
  });

  /// Names to look the owner up by (database label, display name).
  final List<String> owners;
  final String ownerName;

  /// The brand of this product, left out of the list.
  final String exclude;

  /// For tests; normally the bundled database.
  final Future<OwnershipLocalDb> Function()? localDb;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return FutureBuilder<OwnershipLocalDb>(
      future: (localDb ?? OwnershipLocalDb.load)(),
      builder: (BuildContext context, AsyncSnapshot<OwnershipLocalDb> snapshot) {
        final OwnershipLocalDb? db = snapshot.data;
        if (db == null) {
          return const SizedBox.shrink();
        }
        List<String> brands = const <String>[];
        for (final String o in owners) {
          brands = db.topBrandsOf(o);
          if (brands.isNotEmpty) {
            break;
          }
        }
        final String skip = exclude.toLowerCase();
        brands = brands
            .where((String b) => b.toLowerCase() != skip)
            .take(10)
            .toList();
        if (brands.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsetsDirectional.only(top: LARGE_SPACE),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '$ownerName also owns',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: SMALL_SPACE),
              Wrap(
                spacing: SMALL_SPACE,
                runSpacing: SMALL_SPACE,
                children: <Widget>[
                  for (final String b in brands)
                    Material(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20.0),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20.0),
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => SearchPage(
                              SearchProductHelper(),
                              autofocus: false,
                              initialQuery: b,
                            ),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsetsDirectional.symmetric(
                            horizontal: 12.0,
                            vertical: 6.0,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.sell_rounded,
                                size: 14.0,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                              const SizedBox(width: 6.0),
                              Text(
                                b,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 6.0),
                child: Text(
                  'Most scanned brands in Europe with the same owner (Open Food Facts). Tap one to see its products.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The title of a card: sentence case and bold, as in most of the top 100
/// apps ("Recently uploaded", "Jobs for you"), not small caps.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.headlineSmall);
}

/// The owner's real logo (see [CompanyLogo]); a neutral glyph when unknown.
class OwnerAvatar extends StatelessWidget {
  const OwnerAvatar({required this.name, this.size = 48.0, super.key});

  final String? name;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CompanyLogo(names: <String?>[name], size: size),
  );
}

/// The ownership trail drawn like the logo: the brand is a tag, each
/// company above it a dot, the top owner the gold one.
class OwnerTrail extends StatelessWidget {
  const OwnerTrail({required this.chain, this.controlledBy, super.key});

  final List<String> chain;

  /// Person or family behind the top owner, drawn above it.
  final String? controlledBy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color line = theme.colorScheme.outlineVariant;
    final List<String> rows = <String>[...chain, ?controlledBy];
    return Column(
      children: <Widget>[
        for (int i = 0; i < rows.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  width: 32.0,
                  child: Column(
                    children: <Widget>[
                      Expanded(
                        child: i == 0
                            ? const SizedBox.shrink()
                            : Center(child: Container(width: 2.0, color: line)),
                      ),
                      _node(theme, i),
                      Expanded(
                        child: i == rows.length - 1
                            ? const SizedBox.shrink()
                            : Center(child: Container(width: 2.0, color: line)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: MEDIUM_SPACE),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                      vertical: 6.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          i == 0
                              ? 'Brand on the pack'
                              : i == chain.length
                              ? 'Controlled by'
                              : i == chain.length - 1
                              ? 'Top owner'
                              : 'Owned by',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          rows[i],
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: i == chain.length - 1
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _node(final ThemeData theme, final int i) {
    if (i == chain.length) {
      return Icon(
        controlledBy!.toLowerCase().contains('famil') ? Icons.groups_rounded : Icons.person_rounded,
        size: 20.0,
        color: theme.colorScheme.onSurfaceVariant,
      );
    }
    if (i == 0) {
      return Icon(
        Icons.sell_rounded,
        size: 22.0,
        color: theme.colorScheme.primary,
      );
    }
    final bool top = i == chain.length - 1;
    return Container(
      width: top ? 18.0 : 12.0,
      height: top ? 18.0 : 12.0,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: top ? BrandColors.gold : theme.colorScheme.outline,
      ),
    );
  }
}

/// Opens the company page for an owner.
void openOwnerPage(
  final BuildContext context, {
  required final String name,
  final String? dbName,
  final EthicsCompany? company,
  final String? controlledBy,
}) => unawaited(
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => OwnerPage(name: name, dbName: dbName, company: company, controlledBy: controlledBy),
    ),
  ),
);

/// A warning when the owner is on the user's avoid list.
class AvoidedBanner extends StatelessWidget {
  const AvoidedBanner({required this.names, super.key});

  final List<String> names;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AvoidedOwners.instance,
    builder: (BuildContext context, _) {
      final String? avoided = AvoidedOwners.instance.avoidedName(names);
      if (avoided == null) {
        return const SizedBox.shrink();
      }
      final ThemeData theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsetsDirectional.only(top: SMALL_SPACE),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsetsDirectional.all(MEDIUM_SPACE),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: ANGULAR_BORDER_RADIUS,
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.block_rounded, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: SMALL_SPACE),
              Expanded(
                child: Text(
                  'You avoid $avoided',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
