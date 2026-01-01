import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/pages/companies/avoid_list.dart';
import 'package:smooth_app/pages/product/product_page/overview/owner_section.dart';
import 'package:smooth_app/pages/product/product_page/overview/score_ring.dart';
import 'package:smooth_app/services/avoided_owners.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/owner_insights.dart';
import 'package:smooth_app/services/owner_overrides.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/cal_ui.dart';
import 'package:smooth_app/widgets/company_logo.dart';

/// The Companies tab (Owned's answer to Cal AI's "Progress"): how many
/// companies are behind what you scanned, who gets most of it, each with
/// its moral score, and the companies you avoid. Replaces the History tab,
/// which only repeated the home page's list.
class CompaniesPage extends StatefulWidget {
  const CompaniesPage({this.loadProducts, this.localDb, this.ethicsDb, super.key});

  /// For tests.
  final Future<List<Product>> Function()? loadProducts;
  final Future<OwnershipLocalDb> Function()? localDb;
  final Future<EthicsDb> Function()? ethicsDb;

  @override
  State<CompaniesPage> createState() => _CompaniesPageState();
}

class _CompaniesPageState extends State<CompaniesPage> {
  Future<OwnerInsights>? _insights;
  late LocalDatabase _localDatabase;

  @override
  void initState() {
    super.initState();
    OwnerOverrides.instance.addListener(_recount);
  }

  @override
  void dispose() {
    OwnerOverrides.instance.removeListener(_recount);
    super.dispose();
  }

  void _recount() => setState(() => _insights = _compute());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.loadProducts != null) {
      _insights ??= _compute();
      return;
    }
    // A new scan or a cleared history notifies the local database.
    _localDatabase = context.watch<LocalDatabase>();
    _insights = _compute();
  }

  Future<OwnerInsights> _compute() async {
    final List<Product> products = await (widget.loadProducts ?? () => OwnerInsights.historyProducts(_localDatabase))();
    final OwnershipLocalDb db = await (widget.localDb ?? OwnershipLocalDb.load)();
    EthicsDb? ethics;
    try {
      ethics = await (widget.ethicsDb ?? EthicsDb.load)();
    } catch (_) {
      // Owners still show without scores.
    }
    return OwnerInsights.compute(products, db, ethics: ethics);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    final TextStyle? section = theme.textTheme.titleLarge?.copyWith(
      fontSize: 20.0,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.45,
    );
    return Scaffold(
      body: FutureBuilder<OwnerInsights>(
        future: _insights,
        builder: (BuildContext context, AsyncSnapshot<OwnerInsights> snap) {
          final OwnerInsights? i = snap.data;
          final List<OwnerTally> owners = i?.owners ?? const <OwnerTally>[];
          return ListView(
            padding: EdgeInsetsDirectional.fromSTEB(24.0, pad.top + 14.0, 24.0, pad.bottom + 120.0),
            children: <Widget>[
              FadeUpIn(
                child: Text(
                  'Companies',
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontSize: 30.0,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
              const SizedBox(height: 16.0),
              FadeUpIn(index: 1, child: _Summary(insights: i)),
              const SizedBox(height: 28.0),
              FadeUpIn(index: 2, child: Text('Who gets your money', style: section)),
              const SizedBox(height: 12.0),
              if (i == null)
                const Padding(
                  padding: EdgeInsetsDirectional.symmetric(vertical: 24.0),
                  child: Center(child: CalLoader()),
                )
              else if (owners.isEmpty)
                FadeUpIn(
                  index: 3,
                  child: Text(
                    'Scan a few products and see which companies get your money.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              else ...<Widget>[
                for (int k = 0; k < owners.length; k++)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(bottom: 8.0),
                    child: FadeUpIn(
                      index: 3 + k,
                      child: _CompanyRow(tally: owners[k], total: i.total),
                    ),
                  ),
                if (i.unknown.isNotEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 4.0),
                    child: Text(
                      '${i.unknown.length} scanned '
                      '${i.unknown.length == 1 ? 'product has' : 'products have'} no known owner yet.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
              ],
              const SizedBox(height: 28.0),
              Text('Companies you avoid', style: section),
              const SizedBox(height: 12.0),
              const AvoidList(),
            ],
          );
        },
      ),
    );
  }
}

/// "4 companies behind your 6 products", with a ring for the share the
/// three biggest take.
class _Summary extends StatelessWidget {
  const _Summary({required this.insights});

  final OwnerInsights? insights;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final OwnerInsights? i = insights;
    final int known = i == null ? 0 : i.total - i.unknown.length;
    final int? top = known == 0
        ? null
        : (i!.owners.take(3).fold(0, (int s, OwnerTally t) => s + t.count) * 100 / known).round();
    final int total = i?.total ?? 0;
    return Semantics(
      label: '${i?.owners.length ?? 0} companies behind $total products'
          '${top == null ? '' : ', the top 3 make $top percent'}',
      excludeSemantics: true,
      child: CalCard(
        radius: 22.0,
        padding: const EdgeInsetsDirectional.fromSTEB(22.0, 18.0, 16.0, 18.0),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  BigOver(value: i?.owners.length, size: 40.0),
                  const SizedBox(height: 6.0),
                  Text(
                    'Companies behind your $total ${total == 1 ? 'product' : 'products'}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14.0,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (top != null) ...<Widget>[
                    const SizedBox(height: 2.0),
                    Text(
                      'The top 3 make $top %',
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14.0, fontWeight: FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
            CalRing(
              fraction: top == null ? null : top / 100,
              size: 96.0,
              stroke: 8.0,
              child: Icon(CupertinoIcons.building_2_fill, size: 20.0, color: theme.colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

/// One company: logo, name, how many of your products and what share,
/// and its moral score.
class _CompanyRow extends StatelessWidget {
  const _CompanyRow({required this.tally, required this.total});

  final OwnerTally tally;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final int share = total == 0 ? 0 : (tally.count * 100 / total).round();
    final bool avoided = AvoidedOwners.instance.isAvoided(<String?>[tally.owner, tally.company?.name]);
    return Semantics(
      button: true,
      label: '${tally.owner}, ${tally.count} products, $share percent'
          '${tally.ethicsScore == null ? '' : ', moral score ${tally.ethicsScore}'}'
          '${avoided ? ', avoided' : ''}',
      excludeSemantics: true,
      child: PressScale(
        scale: 0.98,
        onTap: () => openOwnerPage(context, name: tally.owner, company: tally.company),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(10.0, 10.0, 12.0, 10.0),
          decoration: BoxDecoration(
            color: dark ? BrandColors.fillDark : BrandColors.row,
            borderRadius: BorderRadius.circular(18.0),
            border: Border.all(color: dark ? BrandColors.hairlineDark : const Color(0xFFF1F0F6)),
          ),
          child: Row(
            children: <Widget>[
              CompanyLogo(names: <String?>[tally.owner, tally.company?.name], size: 48.0, radius: 12.0),
              const SizedBox(width: 12.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        if (avoided) ...<Widget>[
                          Icon(CupertinoIcons.nosign, size: 15.0, color: theme.colorScheme.onSurface),
                          const SizedBox(width: 4.0),
                        ],
                        Flexible(
                          child: Text(
                            tally.owner,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16.0, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      '${tally.count} ${tally.count == 1 ? 'product' : 'products'} · $share %',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 13.0,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6.0),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2.0),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0.0 : tally.count / total,
                        minHeight: 4.0,
                        backgroundColor: dark ? BrandColors.hairlineDark : BrandColors.hairline,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14.0),
              ScoreRing(score: tally.ethicsScore, size: 40.0),
            ],
          ),
        ),
      ),
    );
  }
}
