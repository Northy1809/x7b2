import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/helpers/string_extension.dart';
import 'package:smooth_app/pages/navigator/app_navigator.dart';
import 'package:smooth_app/pages/product/product_page/overview/ethics_details.dart';
import 'package:smooth_app/pages/product/product_page/overview/owner_section.dart';
import 'package:smooth_app/pages/product/product_page/overview/product_overview.dart';
import 'package:smooth_app/pages/product/product_page/overview/share_card.dart';
import 'package:smooth_app/pages/search/search_page.dart';
import 'package:smooth_app/pages/search/search_product_helper.dart';
import 'package:smooth_app/services/avoided_owners.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/owner_insights.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/cal_ui.dart';

/// Everything about one company, laid out like a Cal AI detail screen:
/// logo and name, one big score card, three small category cards (Cal AI's
/// red / orange / blue), what you scanned from it, the documented record,
/// the brands it owns, and "Share" / "Avoid company" pinned at the bottom.
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
  final ScrollController _scroll = ScrollController();
  final Map<EthicsCategory, GlobalKey> _categoryKeys = <EthicsCategory, GlobalKey>{
    for (final EthicsCategory c in EthicsCategory.values) c: GlobalKey(),
  };

  /// The small name in the top bar shows once the big one has scrolled away.
  bool _titleVisible = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final bool visible = _scroll.hasClients && _scroll.offset > 150.0;
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

  void _jumpTo(final EthicsCategory category) {
    final BuildContext? target = _categoryKeys[category]?.currentContext;
    if (target == null) {
      return;
    }
    Haptics.select();
    Scrollable.ensureVisible(
      target,
      duration: CalMotion.page * 2,
      curve: Curves.easeInOutCubic,
      alignment: 0.12,
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
          final EthicsScoreResult? result = company == null ? null : EthicsScore.compute(company);
          final ShareCardData? share = data == null
              ? null
              : ShareCardData(
                  title: widget.name,
                  brand: data.brands.isEmpty ? null : 'Owns ${data.brands.take(4).join(', ')}',
                  ethics: result?.score,
                  text: ownerShareText(widget.name, company, data.brands),
                );
          return Stack(
            children: <Widget>[
              CustomScrollView(
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
                                widget.name.capFirst(),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(fontSize: 17.0, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          const SizedBox(width: 40.0),
                        ],
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _Hero(name: widget.name, about: company?.about, controlledBy: widget.controlledBy),
                  ),
                  SliverPadding(
                    padding: const EdgeInsetsDirectional.fromSTEB(kCalSide, 20.0, kCalSide, 0.0),
                    sliver: SliverToBoxAdapter(
                      child: FadeUpIn(
                        index: 1,
                        child: _ScoreCard(result: result, loading: data == null && company == null),
                      ),
                    ),
                  ),
                  if (result != null)
                    SliverPadding(
                      padding: const EdgeInsetsDirectional.fromSTEB(kCalSide, 12.0, kCalSide, 0.0),
                      sliver: SliverToBoxAdapter(
                        child: FadeUpIn(
                          index: 2,
                          child: Row(
                            children: <Widget>[
                              for (int i = 0; i < result.categories.length; i++) ...<Widget>[
                                if (i > 0) const SizedBox(width: 10.0),
                                Expanded(
                                  child: _CategoryCard(
                                    category: result.categories[i],
                                    onTap: () => _jumpTo(result.categories[i].category),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (data == null)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsetsDirectional.all(40.0),
                        child: Center(child: CalLoader()),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsetsDirectional.fromSTEB(kCalSide, 0.0, kCalSide, 0.0),
                      sliver: SliverList.list(
                        children: <Widget>[
                          if (data.scanned.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 32.0),
                            CalSectionTitle(
                              'You scanned ${data.scanned.length} ${data.scanned.length == 1 ? 'product' : 'products'}',
                            ),
                            const SizedBox(height: 12.0),
                            _ScannedGroup(products: data.scanned),
                          ],
                          const SizedBox(height: 32.0),
                          const CalSectionTitle('The record'),
                          const SizedBox(height: 4.0),
                          Text(
                            'Documented cases, each with its sources. Tap one to read it.',
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12.0),
                          if (result == null)
                            CalCard(
                              child: Text(
                                'We have not researched ${widget.name} yet. We keep adding companies, starting '
                                'with the ones behind the most products in the shops.',
                                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                              ),
                            )
                          else if (result.categories.every((EthicsCategoryScore c) => c.isEmpty))
                            CalCard(
                              child: Text(
                                'We found no documented problems or good practices for ${result.company.name} in '
                                'public sources, so it keeps the starting score of ${EthicsScore.baseline}.',
                                style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                              ),
                            )
                          else
                            for (final EthicsCategoryScore c in result.categories)
                              Padding(
                                key: _categoryKeys[c.category],
                                padding: const EdgeInsetsDirectional.only(bottom: 12.0),
                                child: CalCard(
                                  padding: const EdgeInsetsDirectional.fromSTEB(16.0, 18.0, 16.0, 16.0),
                                  child: EthicsCategoryBlock(c, topPadding: 0.0),
                                ),
                              ),
                          const SizedBox(height: 4.0),
                          CalCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'How we rate companies',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 16.0),
                                ),
                                const SizedBox(height: 8.0),
                                EthicsMethodNote(data.ethics),
                              ],
                            ),
                          ),
                          if (data.brands.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 32.0),
                            const CalSectionTitle('Brands it owns'),
                            const SizedBox(height: 12.0),
                            _Brands(name: widget.name, brands: data.brands),
                          ],
                          Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(8.0, 28.0, 8.0, 0.0),
                            child: Text(
                              'Ownership from Wikidata and researched sources. Companies are bought and sold, '
                              'so data can be out of date.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                          SizedBox(height: 120.0 + MediaQuery.paddingOf(context).bottom),
                        ],
                      ),
                    ),
                ],
              ),
              PositionedDirectional(
                start: 0.0,
                end: 0.0,
                bottom: 0.0,
                child: _BottomBar(owner: widget.name, share: share),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Logo, big name, "Controlled by", a short paragraph; centred.
class _Hero extends StatelessWidget {
  const _Hero({required this.name, this.about, this.controlledBy});

  final String name;
  final String? about;
  final String? controlledBy;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return FadeUpIn(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(kCalSide, 4.0, kCalSide, 0.0),
        child: Column(
          children: <Widget>[
            Hero(tag: 'owner-logo-$name', child: OwnerAvatar(name: name, size: 88.0)),
            const SizedBox(height: 16.0),
            Text(
              name.capFirst(),
              textAlign: TextAlign.center,
              style: theme.textTheme.displayMedium?.copyWith(fontSize: 30.0, letterSpacing: -0.8, height: 1.1),
            ),
            if (controlledBy != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 6.0),
                child: Text(
                  'Controlled by $controlledBy',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ),
            if (about != null && about!.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 12.0),
                child: Text(
                  about!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(color: muted, fontSize: 15.0, height: 1.4),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Cal AI's big calories card: "13/100", "Moral score", the band, and a
/// big ink ring with the scales in the middle.
class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.result, required this.loading});

  final EthicsScoreResult? result;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int? score = result?.score;
    return Semantics(
      label: score == null ? 'Moral score: not rated yet' : 'Moral score $score out of 100, ${result!.band.label}',
      excludeSemantics: true,
      child: CalCard(
        radius: 22.0,
        padding: const EdgeInsetsDirectional.fromSTEB(22.0, 20.0, 18.0, 20.0),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: BigOver(value: score, over: score == null ? null : '/100', size: 44.0),
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    'Moral score',
                    style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15.0, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12.0),
                  Container(
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: 12.0, vertical: 6.0),
                    decoration: BoxDecoration(
                      color: theme.brightness == Brightness.dark ? BrandColors.fillDark : BrandColors.fill,
                      borderRadius: BorderRadius.circular(100.0),
                    ),
                    child: Text(
                      score == null ? (loading ? 'Checking…' : 'Not rated yet') : result!.band.label,
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
              child: Icon(Icons.balance_rounded, size: 24.0, color: theme.colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the three small cards under the score: "40/100 Climate" over a
/// ring in the category's colour; tap scrolls to its cases.
class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.onTap});

  final EthicsCategoryScore category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (IconData icon, Color color) = ethicsCategoryStyle(category.category);
    final String label = ethicsCategoryShort(category.category);
    return Semantics(
      button: true,
      label: '$label ${category.score} out of 100',
      excludeSemantics: true,
      child: CalCard(
        radius: 18.0,
        onTap: onTap,
        padding: const EdgeInsetsDirectional.fromSTEB(12.0, 15.0, 12.0, 14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: BigOver(value: category.score, over: '/100', size: 18.0),
            ),
            const SizedBox(height: 3.0),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.noScaling,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 13.0, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12.0),
            Center(
              child: CalRing(
                fraction: category.score / 100,
                size: 64.0,
                stroke: 6.0,
                color: color,
                child: Icon(icon, size: 18.0, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannedGroup extends StatelessWidget {
  const _ScannedGroup({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    final List<Product> shown = products.take(20).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CalCard(
          padding: EdgeInsetsDirectional.zero,
          child: CalGroup(
            children: <Widget>[
              for (final Product p in shown)
                CalNavRow(
                  icon: CupertinoIcons.cart,
                  title: productDisplayName(p) ?? p.barcode ?? '',
                  subtitle: p.brands?.split(',').first.trim(),
                  onTap: () => AppNavigator.of(context).push(AppRoutes.PRODUCT(p.barcode!), extra: p),
                ),
            ],
          ),
        ),
        if (products.length > shown.length)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(4.0, 10.0, 4.0, 0.0),
            child: Text(
              'And ${products.length - shown.length} more in your history',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _Brands extends StatelessWidget {
  const _Brands({required this.name, required this.brands});

  final String name;
  final List<String> brands;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: <Widget>[
            for (final String b in brands)
              CalPill(
                icon: CupertinoIcons.tag,
                label: b,
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => SearchPage(SearchProductHelper(), autofocus: false, initialQuery: b.capFirst()),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10.0),
        Text(
          'The most scanned brands in Europe owned by $name. Tap one to see its products.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// Cal AI's two buttons at the bottom of a detail screen ("Fix Results" /
/// "Done"): here "Share" and "Avoid company".
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.owner, required this.share});

  final String owner;
  final ShareCardData? share;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: calHairline(context))),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 12.0),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(20.0, 12.0, 20.0, 0.0),
          child: Row(
            children: <Widget>[
              if (share != null) ...<Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Haptics.tap();
                      showShareCard(context, share!);
                    },
                    icon: Icon(CupertinoIcons.share, size: 18.0, color: theme.colorScheme.onSurface),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52.0)),
                    label: const Text('Share'),
                  ),
                ),
                const SizedBox(width: 12.0),
              ],
              Expanded(child: AvoidButton(owner: owner)),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Avoid company" (ink) / "Avoiding" (outlined, tap to undo): adds or
/// removes the owner from the user's avoid list, with a firm buzz when it
/// goes on the list.
class AvoidButton extends StatelessWidget {
  const AvoidButton({required this.owner, super.key});

  final String owner;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AvoidedOwners.instance,
    builder: (BuildContext context, _) {
      final bool avoided = AvoidedOwners.instance.isAvoided(<String>[owner]);
      return AnimatedSwitcher(
        duration: CalMotion.page,
        transitionBuilder: (Widget child, Animation<double> a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(scale: Tween<double>(begin: 0.94, end: 1.0).animate(a), child: child),
        ),
        child: avoided
            ? OutlinedButton.icon(
                key: const ValueKey<bool>(true),
                onPressed: () {
                  Haptics.tap();
                  unawaited(AvoidedOwners.instance.remove(owner));
                },
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52.0)),
                icon: Icon(CupertinoIcons.checkmark_alt, size: 18.0, color: Theme.of(context).colorScheme.onSurface),
                label: const Text('Avoiding', maxLines: 1),
              )
            : FilledButton.icon(
                key: const ValueKey<bool>(false),
                onPressed: () {
                  Haptics.warning();
                  unawaited(AvoidedOwners.instance.add(owner));
                },
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52.0)),
                icon: const Icon(CupertinoIcons.nosign, size: 18.0),
                label: const Text('Avoid', maxLines: 1),
              ),
      );
    },
  );
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
