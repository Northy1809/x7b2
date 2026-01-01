import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/database/dao_product_last_access.dart';
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

/// How far back the Companies tab looks (Cal AI's "90 Days | 6 Months |
/// 1 Year | All time").
enum CompaniesRange {
  week('This week', 7),
  month('30 days', 30),
  half('6 months', 182),
  all('All time', null);

  const CompaniesRange(this.label, this.days);

  final String label;
  final int? days;
}

/// Everything the tab needs, loaded once; each range is worked out from it.
class _Data {
  _Data(this.products, this.seen, this.db, this.ethics);

  final List<Product> products;
  final Map<String, DateTime> seen;
  final OwnershipLocalDb db;
  final EthicsDb? ethics;

  List<Product> inRange(final CompaniesRange r, final DateTime now) {
    final int? days = r.days;
    if (days == null) {
      return products;
    }
    final DateTime from = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
    return <Product>[
      for (final Product p in products)
        if (seen[p.barcode] case final DateTime t when !t.isBefore(from)) p,
    ];
  }

  /// Scans per bar for the range: the last 7 days, the last 4 weeks, or
  /// the last 6 months (for 6 months and all time).
  (List<int>, List<String>) bars(final CompaniesRange r, final DateTime now) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    const List<String> months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const List<String> days = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final List<DateTime> times = <DateTime>[
      for (final Product p in products)
        if (seen[p.barcode] case final DateTime t) t,
    ];
    switch (r) {
      case CompaniesRange.week:
        final DateTime start = today.subtract(const Duration(days: 6));
        final List<int> v = List<int>.filled(7, 0);
        for (final DateTime t in times) {
          final int i = DateTime(t.year, t.month, t.day).difference(start).inDays;
          if (i >= 0 && i < 7) {
            v[i]++;
          }
        }
        return (v, <String>[for (int i = 0; i < 7; i++) days[start.add(Duration(days: i)).weekday - 1]]);
      case CompaniesRange.month:
        final DateTime start = today.subtract(const Duration(days: 27));
        final List<int> v = List<int>.filled(4, 0);
        for (final DateTime t in times) {
          final int i = DateTime(t.year, t.month, t.day).difference(start).inDays ~/ 7;
          if (i >= 0 && i < 4) {
            v[i]++;
          }
        }
        return (
          v,
          <String>[
            for (int i = 0; i < 4; i++)
              '${start.add(Duration(days: i * 7)).day} ${months[start.add(Duration(days: i * 7)).month - 1]}',
          ],
        );
      case CompaniesRange.half:
      case CompaniesRange.all:
        final List<int> v = List<int>.filled(6, 0);
        for (final DateTime t in times) {
          final int i = 5 - ((now.year - t.year) * 12 + now.month - t.month);
          if (i >= 0 && i < 6) {
            v[i]++;
          }
        }
        return (v, <String>[for (int i = 0; i < 6; i++) months[(now.month - 6 + i) % 12]]);
    }
  }
}

/// The Companies tab, laid out as Cal AI's "Progress" (16/11): two cards
/// side by side (how many companies, their average moral score), the grey
/// range switch, a bar chart of your scans, then who gets your money and
/// the companies you avoid.
class CompaniesPage extends StatefulWidget {
  const CompaniesPage({this.loadProducts, this.loadSeen, this.localDb, this.ethicsDb, super.key});

  /// For tests.
  final Future<List<Product>> Function()? loadProducts;
  final Future<Map<String, DateTime>> Function()? loadSeen;
  final Future<OwnershipLocalDb> Function()? localDb;
  final Future<EthicsDb> Function()? ethicsDb;

  @override
  State<CompaniesPage> createState() => _CompaniesPageState();
}

class _CompaniesPageState extends State<CompaniesPage> {
  Future<_Data>? _data;
  late LocalDatabase _localDatabase;
  CompaniesRange _range = CompaniesRange.all;

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

  void _recount() => setState(() => _data = _load());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.loadProducts != null) {
      _data ??= _load();
      return;
    }
    // A new scan or a cleared history notifies the local database.
    _localDatabase = context.watch<LocalDatabase>();
    _data = _load();
  }

  Future<_Data> _load() async {
    final List<Product> products = await (widget.loadProducts ?? () => OwnerInsights.historyProducts(_localDatabase))();
    Map<String, DateTime> seen = const <String, DateTime>{};
    if (widget.loadSeen != null) {
      seen = await widget.loadSeen!();
    } else if (widget.loadProducts == null) {
      final Map<String, int> raw = await DaoProductLastAccess(_localDatabase).getAll();
      seen = <String, DateTime>{
        for (final MapEntry<String, int> e in raw.entries) e.key: DateTime.fromMillisecondsSinceEpoch(e.value),
      };
    }
    final OwnershipLocalDb db = await (widget.localDb ?? OwnershipLocalDb.load)();
    EthicsDb? ethics;
    try {
      ethics = await (widget.ethicsDb ?? EthicsDb.load)();
    } catch (_) {
      // Owners still show without scores.
    }
    return _Data(products, seen, db, ethics);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    return Scaffold(
      body: FutureBuilder<_Data>(
        future: _data,
        builder: (BuildContext context, AsyncSnapshot<_Data> snap) {
          final _Data? data = snap.data;
          final DateTime now = DateTime.now();
          final OwnerInsights? i = data == null
              ? null
              : OwnerInsights.compute(data.inRange(_range, now), data.db, ethics: data.ethics);
          final List<OwnerTally> owners = i?.owners ?? const <OwnerTally>[];
          final (List<int>, List<String>)? bars = data?.bars(_range, now);
          return ListView(
            padding: EdgeInsetsDirectional.fromSTEB(24.0, pad.top + 14.0, 24.0, pad.bottom + 120.0),
            children: <Widget>[
              const FadeUpIn(child: CalLargeTitle('Companies')),
              const SizedBox(height: 16.0),
              FadeUpIn(index: 1, child: _TopCards(insights: i)),
              const SizedBox(height: 18.0),
              FadeUpIn(
                index: 2,
                child: CalSegmented<CompaniesRange>(
                  segments: <(CompaniesRange, String)>[for (final CompaniesRange r in CompaniesRange.values) (r, r.label)],
                  selected: _range,
                  onChanged: (CompaniesRange r) => setState(() => _range = r),
                ),
              ),
              const SizedBox(height: 14.0),
              FadeUpIn(
                index: 3,
                child: CalCard(
                  padding: const EdgeInsetsDirectional.fromSTEB(18.0, 16.0, 18.0, 14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'Your scans',
                              style: theme.textTheme.titleMedium?.copyWith(fontSize: 17.0, fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            '${i?.total ?? 0}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 22.0,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                            ),
                          ),
                          Text(
                            ' total',
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 13.0, color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14.0),
                      CalBars(
                        key: ValueKey<CompaniesRange>(_range),
                        values: bars?.$1 ?? const <int>[0, 0, 0, 0, 0, 0],
                        labels: bars?.$2 ?? const <String>['', '', '', '', '', ''],
                        height: 96.0,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28.0),
              const FadeUpIn(index: 4, child: CalSectionTitle('Who gets your money')),
              const SizedBox(height: 12.0),
              if (i == null)
                const Padding(
                  padding: EdgeInsetsDirectional.symmetric(vertical: 24.0),
                  child: Center(child: CalLoader()),
                )
              else if (owners.isEmpty)
                FadeUpIn(
                  index: 5,
                  child: Text(
                    _range == CompaniesRange.all
                        ? 'Scan a few products and see which companies get your money.'
                        : 'No scans in this period yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              else ...<Widget>[
                for (int k = 0; k < owners.length; k++)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(bottom: 8.0),
                    child: FadeUpIn(
                      index: 5 + k,
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
              const CalSectionTitle('Companies you avoid'),
              const SizedBox(height: 12.0),
              const AvoidList(),
            ],
          );
        },
      ),
    );
  }
}

/// Two cards side by side, as Cal AI's "My Weight" and "Day Streak":
/// how many companies are behind your scans (and the top three's share),
/// and their average moral score in a ring.
class _TopCards extends StatelessWidget {
  const _TopCards({required this.insights});

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
    final int? avg = i?.averageEthics;
    final TextStyle? label = theme.textTheme.bodyMedium?.copyWith(fontSize: 14.0, color: theme.colorScheme.onSurfaceVariant);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: Semantics(
              label: '${i?.owners.length ?? 0} companies behind $total products'
                  '${top == null ? '' : ', the top 3 make $top percent'}',
              excludeSemantics: true,
              child: CalCard(
                padding: const EdgeInsetsDirectional.fromSTEB(16.0, 14.0, 14.0, 14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Companies', style: label),
                    const SizedBox(height: 6.0),
                    BigOver(value: i?.owners.length, size: 34.0),
                    const SizedBox(height: 4.0),
                    Text('behind $total ${total == 1 ? 'product' : 'products'}', style: label),
                    const Spacer(),
                    const SizedBox(height: 10.0),
                    Text(
                      top == null ? 'Top 3: –' : 'Top 3 make $top %',
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13.0, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10.0),
          Expanded(
            child: Semantics(
              label: avg == null ? 'No moral score yet' : 'Average moral score $avg of 100',
              excludeSemantics: true,
              child: CalCard(
                padding: const EdgeInsetsDirectional.fromSTEB(16.0, 14.0, 14.0, 14.0),
                child: Column(
                  children: <Widget>[
                    Align(alignment: AlignmentDirectional.centerStart, child: Text('Moral score', style: label)),
                    const SizedBox(height: 10.0),
                    CalRing(
                      fraction: avg == null ? null : avg / 100,
                      size: 78.0,
                      stroke: 7.0,
                      child: avg == null
                          ? Text('–', style: theme.textTheme.titleLarge)
                          : CountUp(
                              value: avg,
                              style: theme.textTheme.titleLarge?.copyWith(fontSize: 22.0, fontWeight: FontWeight.w700),
                            ),
                    ),
                    const SizedBox(height: 8.0),
                    Text('average of your companies', textAlign: TextAlign.center, style: label?.copyWith(fontSize: 12.0)),
                  ],
                ),
              ),
            ),
          ),
        ],
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
