import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/helpers/haptic_feedback_helper.dart';
import 'package:smooth_app/pages/navigator/app_navigator.dart';
import 'package:smooth_app/pages/product/product_page/overview/ethics_details.dart';
import 'package:smooth_app/pages/product/product_page/overview/overview_card.dart';
import 'package:smooth_app/pages/product/product_page/overview/owner_section.dart';
import 'package:smooth_app/pages/product/product_page/overview/product_overview.dart';
import 'package:smooth_app/pages/product/product_page/overview/share_card.dart';
import 'package:smooth_app/pages/search/search_page.dart';
import 'package:smooth_app/pages/search/search_product_helper.dart';
import 'package:smooth_app/services/avoided_owners.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/owner_insights.dart';
import 'package:smooth_app/services/ownership_local_db.dart';

/// Everything about one company: what it is, its ethics record, the brands
/// it owns, what the user scanned from it, and a switch to avoid it.
class OwnerPage extends StatefulWidget {
  const OwnerPage({
    required this.name,
    this.dbName,
    this.company,
    this.controlledBy,
    this.localDb,
    this.ethicsDb,
    this.loadProducts,
    super.key,
  });

  /// Display name.
  final String name;

  /// The name in the ownership database, when it differs ("Nestlé S.A.").
  final String? dbName;
  final EthicsCompany? company;
  final String? controlledBy;

  /// For tests; default to the bundled data and the scan history.
  final Future<OwnershipLocalDb> Function()? localDb;
  final Future<EthicsDb> Function()? ethicsDb;
  final Future<List<Product>> Function()? loadProducts;

  @override
  State<OwnerPage> createState() => _OwnerPageState();
}

class _OwnerData {
  const _OwnerData({required this.company, required this.brands, required this.scanned, this.ethics});

  final EthicsCompany? company;
  final EthicsDb? ethics;
  final List<String> brands;
  final List<Product> scanned;
}

class _OwnerPageState extends State<OwnerPage> {
  late final Future<_OwnerData> _data = _load();

  Future<List<Product>> _history() async {
    try {
      return await OwnerInsights.historyProducts(context.read<LocalDatabase>());
    } catch (_) {
      return const <Product>[];
    }
  }

  Future<_OwnerData> _load() async {
    unawaited(AvoidedOwners.instance.load());
    final OwnershipLocalDb db = await (widget.localDb ?? OwnershipLocalDb.load)();
    EthicsDb? ethics;
    try {
      ethics = await (widget.ethicsDb ?? EthicsDb.load)();
    } catch (_) {
      // Shown as "not rated yet".
    }
    final EthicsCompany? company = widget.company ?? ethics?.forOwner(widget.dbName ?? widget.name);
    final List<String> names = <String>[widget.name, ?widget.dbName, ?company?.name];
    List<String> brands = const <String>[];
    for (final String n in names) {
      brands = db.topBrandsOf(n);
      if (brands.isNotEmpty) {
        break;
      }
    }
    final List<Product> products = await (widget.loadProducts ?? _history)();
    final OwnerTally? tally = OwnerInsights.compute(products, db, ethics: ethics).tallyFor(names);
    return _OwnerData(
      company: company,
      brands: brands,
      scanned: tally?.products ?? const <Product>[],
      ethics: ethics,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: FutureBuilder<_OwnerData>(
        future: _data,
        builder: (BuildContext context, AsyncSnapshot<_OwnerData> snapshot) {
          final _OwnerData? data = snapshot.data;
          final EthicsCompany? company = data?.company ?? widget.company;
          return CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: _OwnerHero(
                  name: widget.name,
                  about: company?.about,
                  controlledBy: widget.controlledBy,
                  shareCard: data == null
                      ? null
                      : ShareCardData(
                          title: widget.name,
                          brand: data.brands.isEmpty ? null : 'Owns ${data.brands.take(4).join(', ')}',
                          ethics: company == null ? null : EthicsScore.compute(company).score,
                          text: ownerShareText(widget.name, company, data.brands),
                        ),
                ),
              ),
              if (data == null)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsetsDirectional.all(VERY_LARGE_SPACE),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else ...<Widget>[
                if (data.scanned.isNotEmpty)
                  SliverToBoxAdapter(child: _ScannedCard(name: widget.name, products: data.scanned)),
                SliverToBoxAdapter(
                  child: EthicsDetails(
                    result: company == null ? null : EthicsScore.compute(company),
                    ownerName: widget.name,
                    db: data.ethics,
                  ),
                ),
                if (data.brands.isNotEmpty)
                  SliverToBoxAdapter(child: _BrandsCard(name: widget.name, brands: data.brands)),
              ],
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    VERY_LARGE_SPACE,
                    MEDIUM_SPACE,
                    VERY_LARGE_SPACE,
                    VERY_LARGE_SPACE * 2,
                  ),
                  child: Text(
                    'Ownership from Wikidata and researched sources. Companies are bought and sold, '
                    'so data can be out of date.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OwnerHero extends StatelessWidget {
  const _OwnerHero({required this.name, this.about, this.controlledBy, this.shareCard});

  final String name;
  final String? about;
  final String? controlledBy;

  /// What the share button sends; no button while it is unknown.
  final ShareCardData? shareCard;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    // Light and open, like an App Store app page: logo, big name, a short
    // paragraph, one action.
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(SMALL_SPACE, 0, 20.0, 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const BackButton(),
                const Spacer(),
                if (shareCard != null)
                  IconButton(
                    tooltip: 'Share',
                    icon: const Icon(Icons.ios_share_rounded),
                    onPressed: () => showShareCard(context, shareCard!),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 12.0, top: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      OwnerAvatar(name: name, size: 76.0),
                      const SizedBox(width: 16.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              name,
                              style: theme.textTheme.displayMedium,
                            ),
                            if (controlledBy != null)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(top: 4.0),
                                child: Text(
                                  'Controlled by $controlledBy',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: muted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (about != null && about!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: 16.0),
                      child: Text(
                        about!,
                        style: theme.textTheme.bodyLarge?.copyWith(color: muted),
                      ),
                    ),
                  const SizedBox(height: 18.0),
                  AvoidButton(owner: name, onDark: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Avoid this company" / "Avoiding": adds or removes the owner from the
/// user's avoid list.
class AvoidButton extends StatelessWidget {
  const AvoidButton({required this.owner, this.onDark = true, super.key});

  final String owner;

  /// On the dark hero (white outline) or on a light card.
  final bool onDark;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AvoidedOwners.instance,
    builder: (BuildContext context, _) {
      final bool avoided = AvoidedOwners.instance.isAvoided(<String>[owner]);
      final Color fg = onDark ? Colors.white : Theme.of(context).colorScheme.primary;
      if (avoided) {
        return FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            unawaited(SmoothHapticFeedback.click());
            unawaited(AvoidedOwners.instance.remove(owner));
          },
          icon: const Icon(Icons.block_rounded),
          label: const Text('Avoiding · tap to undo', style: TextStyle(fontWeight: FontWeight.w800)),
        );
      }
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          side: BorderSide(color: fg.withValues(alpha: 0.7)),
        ),
        onPressed: () {
          unawaited(SmoothHapticFeedback.confirm());
          unawaited(AvoidedOwners.instance.add(owner));
        },
        icon: const Icon(Icons.block_rounded),
        label: const Text('Avoid this company', style: TextStyle(fontWeight: FontWeight.w700)),
      );
    },
  );
}

class _ScannedCard extends StatelessWidget {
  const _ScannedCard({required this.name, required this.products});

  final String name;
  final List<Product> products;

  @override
  Widget build(BuildContext context) => OverviewCard(
    padding: const EdgeInsetsDirectional.symmetric(vertical: MEDIUM_SPACE),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: LARGE_SPACE),
          child: SectionLabel('You scanned ${products.length} from $name'),
        ),
        for (final Product p in products.take(20))
          ListTile(
            contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: LARGE_SPACE),
            title: Text(
              productDisplayName(p) ?? p.barcode ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: p.brands == null ? null : Text(p.brands!.split(',').first.trim()),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => AppNavigator.of(context).push(AppRoutes.PRODUCT(p.barcode!), extra: p),
          ),
        if (products.length > 20)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: LARGE_SPACE, vertical: SMALL_SPACE),
            child: Text(
              'and ${products.length - 20} more in your history',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    ),
  );
}

class _BrandsCard extends StatelessWidget {
  const _BrandsCard({required this.name, required this.brands});

  final String name;
  final List<String> brands;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return OverviewCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel('Brands it owns'),
          const SizedBox(height: SMALL_SPACE),
          Wrap(
            spacing: SMALL_SPACE,
            runSpacing: SMALL_SPACE,
            children: <Widget>[
              for (final String b in brands)
                ActionChip(
                  avatar: const Icon(Icons.sell_rounded, size: 16.0),
                  label: Text(b),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => SearchPage(SearchProductHelper(), autofocus: false, initialQuery: b),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: SMALL_SPACE),
          Text(
            'The most scanned brands in Europe owned by $name. Tap one to see its products.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// "Nestlé owns Maggi, Nescafé and KitKat (ethics score 13/100). Found with Owned."
String ownerShareText(final String name, final EthicsCompany? company, final List<String> brands) {
  final StringBuffer sb = StringBuffer(name);
  final List<String> top = brands.take(3).toList();
  if (top.isNotEmpty) {
    sb.write(' owns ');
    sb.write(top.length == 1 ? top.first : '${top.sublist(0, top.length - 1).join(', ')} and ${top.last}');
  }
  if (company != null) {
    sb.write(' (ethics score ${EthicsScore.compute(company).score}/100)');
  }
  sb.write('. Found with Owned.');
  return sb.toString();
}
