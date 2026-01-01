import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/database/dao_product_last_access.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/generic_lib/widgets/owned_wordmark.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/helpers/string_extension.dart';
import 'package:smooth_app/pages/companies/avoid_list.dart';
import 'package:smooth_app/pages/history_page.dart';
import 'package:smooth_app/pages/home/home_scanner_card.dart';
import 'package:smooth_app/pages/home/pending_scan_row.dart';
import 'package:smooth_app/pages/navigator/app_navigator.dart';
import 'package:smooth_app/pages/product/product_page/overview/owner_section.dart';
import 'package:smooth_app/services/avoided_owners.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/health_score.dart';
import 'package:smooth_app/services/owner_insights.dart';
import 'package:smooth_app/services/owner_overrides.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/pending_scans.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/cal_ui.dart';
import 'package:smooth_app/widgets/company_logo.dart';
import 'package:smooth_app/widgets/owned_mark.dart';

/// Everything the home page shows, worked out from the scan history.
class HomeSummary {
  HomeSummary({
    required this.products,
    required this.insights,
    required this.lastSeen,
  });

  /// Newest first.
  final List<Product> products;
  final OwnerInsights insights;

  /// Barcode -> when it was last opened.
  final Map<String, DateTime> lastSeen;

  /// The scan history with owners, scores and times (home and History page).
  static Future<HomeSummary> load(final LocalDatabase db) async {
    final List<Product> products = await OwnerInsights.historyProducts(db);
    final OwnershipLocalDb local = await OwnershipLocalDb.load();
    EthicsDb? ethics;
    try {
      ethics = await EthicsDb.load();
    } catch (_) {
      // Owners still show without scores.
    }
    final Map<String, int> seen = await DaoProductLastAccess(db).getAll();
    return HomeSummary(
      products: products,
      insights: OwnerInsights.compute(products, local, ethics: ethics),
      lastSeen: <String, DateTime>{
        for (final MapEntry<String, int> e in seen.entries) e.key: DateTime.fromMillisecondsSinceEpoch(e.value),
      },
    );
  }

  int get total => insights.total;
  int get known => total - insights.unknown.length;

  /// Share of the scanned products made by the three biggest owners.
  int? get topThreeShare {
    if (known == 0) {
      return null;
    }
    final int top = insights.owners.take(3).fold(0, (int sum, OwnerTally t) => sum + t.count);
    return (top * 100 / known).round();
  }

  int get fromAvoided => insights.owners
      .where((OwnerTally t) => AvoidedOwners.instance.isAvoided(<String?>[t.owner, t.company?.name]))
      .fold(0, (int sum, OwnerTally t) => sum + t.count);

  OwnerTally? ownerOf(final Product product) {
    for (final OwnerTally t in insights.owners) {
      if (t.products.any((Product p) => p.barcode == product.barcode)) {
        return t;
      }
    }
    return null;
  }

  /// Health scores (0-100) of the scanned food that has one.
  late final List<int> healthScores = <int>[
    for (final Product p in products)
      if ((p.productType ?? ProductType.food) == ProductType.food)
        if (HealthScore.fromProduct(p).score case final int s) s,
  ];

  int? get averageHealth => healthScores.isEmpty
      ? null
      : (healthScores.fold(0, (int a, int b) => a + b) / healthScores.length).round();

  /// Rated food at 50 or more / 25-49 / under 25 (the score bands).
  int get healthGood => healthScores.where((int s) => s >= 50).length;
  int get healthFair => healthScores.where((int s) => s >= 25 && s < 50).length;
  int get healthPoor => healthScores.where((int s) => s < 25).length;
}

/// The home tab, laid out as Cal AI's and sized from its App Store
/// screenshot (research/ui/CALAI.md, 393 pt wide): wordmark and avoid pill,
/// the scanner card (17/11), the companies strip, swipeable pages of one big
/// ring card over three small ones with dots under them, and the latest
/// scans as photo rows. The camera opens from the scanner card and from the
/// black + button's menu.
class OwnedHomePage extends StatefulWidget {
  const OwnedHomePage({this.load, this.onScan, super.key});

  /// For tests.
  final Future<HomeSummary> Function()? load;

  /// For tests: what the scanner card does (opens the camera when null).
  final VoidCallback? onScan;

  @override
  State<OwnedHomePage> createState() => _OwnedHomePageState();
}

/// Cal AI's home, in points.
class _Spec {
  const _Spec._();

  static const double side = 24.0;
  static const double bigCardHeight = 126.0;
  static const double bigNumber = 40.0;
  static const double bigRing = 96.0;
  static const double bigStroke = 8.0;
  static const double smallCardHeight = 142.0;
  static const double smallNumber = 18.0;
  static const double smallRing = 68.0;
  static const double smallStroke = 6.0;
  static const double gap = 9.0;
  static const double rowHeight = 118.0;
  static const double rowPhoto = 116.0;
}

class _OwnedHomePageState extends State<OwnedHomePage> {
  Future<HomeSummary>? _summary;
  late LocalDatabase _localDatabase;
  final PageController _pages = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    OwnerOverrides.instance.addListener(_reload);
  }

  @override
  void dispose() {
    OwnerOverrides.instance.removeListener(_reload);
    _pages.dispose();
    super.dispose();
  }

  void _reload() => setState(() => _summary = _compute());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.load != null) {
      _summary ??= widget.load!();
      return;
    }
    // A new scan or a cleared history notifies the local database.
    _localDatabase = context.watch<LocalDatabase>();
    _summary = _compute();
  }

  Future<HomeSummary> _compute() async {
    if (widget.load != null) {
      return widget.load!();
    }
    return HomeSummary.load(_localDatabase);
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: DecoratedBox(
        decoration: theme.brightness == Brightness.dark
            ? const BoxDecoration()
            : const BoxDecoration(gradient: BrandColors.hero),
        child: FutureBuilder<HomeSummary>(
          future: _summary,
          builder: (BuildContext context, AsyncSnapshot<HomeSummary> snap) {
            final HomeSummary? s = snap.data;
            const EdgeInsetsDirectional inset = EdgeInsetsDirectional.symmetric(horizontal: _Spec.side);
            const EdgeInsetsDirectional rowPad = EdgeInsetsDirectional.fromSTEB(_Spec.side, 0.0, _Spec.side, 13.0);
            return ListView(
              padding: EdgeInsetsDirectional.fromSTEB(0.0, pad.top + 14.0, 0.0, pad.bottom + 120.0),
              children: <Widget>[
                const FadeUpIn(index: 0, child: Padding(padding: inset, child: _Header())),
                const SizedBox(height: 16.0),
                // 17/11: the scanner first, the app's main action.
                FadeUpIn(index: 1, child: Padding(padding: inset, child: HomeScannerCard(onOpen: widget.onScan))),
                const SizedBox(height: 14.0),
                FadeUpIn(index: 1, child: _CompanyStrip(summary: s)),
                const SizedBox(height: 6.0),
                FadeUpIn(
                  index: 2,
                  child: SizedBox(
                    // Room above and below for the cards' soft shadows.
                    height: 8.0 + _Spec.bigCardHeight + 12.0 + _Spec.smallCardHeight + 16.0,
                    child: PageView(
                      controller: _pages,
                      onPageChanged: (int i) {
                        Haptics.select();
                        setState(() => _page = i);
                      },
                      children: <Widget>[
                        _CardsPage(
                          big: _BigCard(
                            value: s?.insights.averageEthics,
                            label: 'Average moral score',
                            icon: Icons.balance_rounded,
                          ),
                          small: _moralSmall(s),
                        ),
                        _CardsPage(
                          big: _BigCard(
                            value: s?.averageHealth,
                            label: 'Average health score',
                            icon: CupertinoIcons.heart_fill,
                          ),
                          small: _healthSmall(s),
                        ),
                      ],
                    ),
                  ),
                ),
                Center(child: CalPageDots(count: 2, index: _page)),
                const SizedBox(height: 30.0),
                FadeUpIn(
                  index: 3,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: _Spec.side),
                    child: CalSectionTitle(
                      'Recently scanned',
                      action: s != null && s.products.isNotEmpty ? 'See all' : null,
                      onAction: () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(builder: (_) => const HistoryPage()),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10.0),
                ListenableBuilder(
                  listenable: PendingScans.instance,
                  builder: (BuildContext context, _) => Column(
                    children: <Widget>[
                      for (final PendingScan p in PendingScans.instance.scans)
                        Padding(
                          key: ObjectKey(p),
                          padding: rowPad,
                          child: FadeUpIn(child: PendingScanRow(scan: p)),
                        ),
                    ],
                  ),
                ),
                if (s != null && s.products.isEmpty && PendingScans.instance.scans.isEmpty)
                  const FadeUpIn(index: 4, child: Padding(padding: inset, child: _EmptyRow()))
                else if (s != null)
                  for (int i = 0; i < s.products.length && i < 12; i++)
                    Padding(
                      padding: rowPad,
                      child: FadeUpIn(
                        index: 4 + i,
                        child: ScanRow(
                          product: s.products[i],
                          owner: s.ownerOf(s.products[i]),
                          seen: s.lastSeen[s.products[i].barcode],
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<_SmallCard> _moralSmall(final HomeSummary? s) {
    final int total = s?.total ?? 0;
    final int? top = s?.topThreeShare;
    return <_SmallCard>[
      _SmallCard(
        value: s?.known,
        over: '/$total',
        label: 'Owners',
        fraction: total == 0 ? null : s!.known / total,
        icon: CupertinoIcons.search,
        color: BrandColors.accentRed,
      ),
      _SmallCard(
        value: top,
        over: top == null ? null : '%',
        label: 'From top 3',
        fraction: top == null ? null : top / 100,
        icon: CupertinoIcons.building_2_fill,
        color: BrandColors.accentOrange,
      ),
      _SmallCard(
        value: s?.fromAvoided,
        over: '/$total',
        label: 'Avoided',
        fraction: total == 0 ? null : s!.fromAvoided / total,
        icon: CupertinoIcons.nosign,
        color: BrandColors.accentBlue,
      ),
    ];
  }

  List<_SmallCard> _healthSmall(final HomeSummary? s) {
    final int rated = s?.healthScores.length ?? 0;
    double? f(final int? n) => rated == 0 || n == null ? null : n / rated;
    return <_SmallCard>[
      _SmallCard(
        value: s?.healthGood,
        over: '/$rated',
        label: 'Good or better',
        fraction: f(s?.healthGood),
        icon: CupertinoIcons.heart_fill,
        color: BrandColors.accentRed,
      ),
      _SmallCard(
        value: s?.healthFair,
        over: '/$rated',
        label: 'Fair',
        fraction: f(s?.healthFair),
        icon: CupertinoIcons.heart_slash,
        color: BrandColors.accentOrange,
      ),
      _SmallCard(
        value: s?.healthPoor,
        over: '/$rated',
        label: 'Poor',
        fraction: f(s?.healthPoor),
        icon: CupertinoIcons.exclamationmark_triangle,
        color: BrandColors.accentBlue,
      ),
    ];
  }
}

/// One page of the pager: the big card over the three small ones.
class _CardsPage extends StatelessWidget {
  const _CardsPage({required this.big, required this.small});

  final Widget big;
  final List<_SmallCard> small;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(_Spec.side, 8.0, _Spec.side, 16.0),
    child: Column(
      children: <Widget>[
        SizedBox(height: _Spec.bigCardHeight, child: big),
        const SizedBox(height: 12.0),
        SizedBox(
          height: _Spec.smallCardHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (int i = 0; i < small.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: _Spec.gap),
                Expanded(child: small[i]),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

/// Wordmark, and a pill with the companies you avoid (Cal AI has a streak
/// here; a scanning streak means nothing for who owns your food).
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        OwnedWordmark(height: 27.0, color: theme.colorScheme.onSurface, motion: OwnedMarkMotion.intro),
        const Spacer(),
        ListenableBuilder(
          listenable: AvoidedOwners.instance,
          builder: (BuildContext context, _) {
            final int n = AvoidedOwners.instance.names.length;
            return Semantics(
              container: true,
              button: true,
              label: n == 0 ? 'Companies you avoid: none yet' : 'You avoid $n ${n == 1 ? 'company' : 'companies'}',
              excludeSemantics: true,
              child: PressScale(
                onTap: () => AvoidListPage.open(context),
                child: Container(
                  height: 32.0,
                  padding: const EdgeInsetsDirectional.fromSTEB(11.0, 0.0, 13.0, 0.0),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(16.0),
                    boxShadow: theme.brightness == Brightness.dark ? null : BrandColors.cardShadow,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(CupertinoIcons.nosign, size: 16.0, color: theme.colorScheme.onSurface),
                      const SizedBox(width: 5.0),
                      Text(
                        n == 0 ? 'Avoid' : '$n',
                        style: theme.textTheme.titleMedium?.copyWith(fontSize: 16.0, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Where Cal AI shows the week: the companies behind your scans, most
/// first, each logo in a ring that fills with its share. A tap opens the
/// company. Avoided ones carry a small no-entry sign.
class _CompanyStrip extends StatelessWidget {
  const _CompanyStrip({required this.summary});

  final HomeSummary? summary;

  static const double height = 84.0;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final HomeSummary? s = summary;
    if (s == null) {
      return const SizedBox(height: height);
    }
    final List<OwnerTally> owners = s.insights.owners.take(8).toList();
    if (owners.isEmpty) {
      return SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: _Spec.side),
          child: Row(
            children: <Widget>[
              for (int i = 0; i < 4; i++) ...<Widget>[
                SizedBox.square(
                  dimension: 46.0,
                  child: CustomPaint(painter: _DottedRing(color: theme.brightness == Brightness.dark ? BrandColors.mutedDark : BrandColors.faint)),
                ),
                const SizedBox(width: 10.0),
              ],
              Expanded(
                child: Text(
                  'Companies you buy from show up here',
                  maxLines: 2,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 13.0,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final int known = s.known;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: _Spec.side - 4.0),
        itemCount: owners.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4.0),
        itemBuilder: (BuildContext context, int i) => _CompanyDot(tally: owners[i], known: known),
      ),
    );
  }
}

class _CompanyDot extends StatelessWidget {
  const _CompanyDot({required this.tally, required this.known});

  final OwnerTally tally;
  final int known;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool avoided = AvoidedOwners.instance.isAvoided(<String?>[tally.owner, tally.company?.name]);
    final int share = known == 0 ? 0 : (tally.count * 100 / known).round();
    return Semantics(
      button: true,
      label: '${tally.owner}: $share percent of your scans${avoided ? ', avoided' : ''}',
      excludeSemantics: true,
      child: PressScale(
        scale: 0.92,
        onTap: () => openOwnerPage(context, name: tally.owner, company: tally.company),
        child: SizedBox(
          width: 60.0,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                tally.owner.capFirst(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textScaler: TextScaler.noScaling,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12.0,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 5.0),
              SizedBox.square(
                dimension: 50.0,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    CalRing(
                      fraction: known == 0 ? null : tally.count / known,
                      size: 50.0,
                      stroke: 3.0,
                      child: CompanyLogo(
                        names: <String?>[tally.owner, tally.company?.name],
                        size: 38.0,
                        radius: 19.0,
                      ),
                    ),
                    if (avoided)
                      PositionedDirectional(
                        end: -2.0,
                        bottom: -2.0,
                        child: Container(
                          padding: const EdgeInsetsDirectional.all(2.0),
                          decoration: BoxDecoration(color: theme.colorScheme.surface, shape: BoxShape.circle),
                          child: Icon(CupertinoIcons.nosign, size: 14.0, color: theme.colorScheme.onSurface),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DottedRing extends CustomPainter {
  _DottedRing({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final Rect r = (Offset.zero & size).deflate(1.5);
    const int n = 16;
    for (int i = 0; i < n; i++) {
      canvas.drawArc(r, i * 2 * 3.14159265 / n, 0.18, false, p);
    }
  }

  @override
  bool shouldRepaint(_DottedRing old) => old.color != color;
}

/// "44/100 Average moral score" with the ring, as Cal AI's calories card.
class _BigCard extends StatelessWidget {
  const _BigCard({required this.value, required this.label, required this.icon});

  final int? value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      label: value == null ? '$label: not rated yet' : '$label $value out of 100',
      excludeSemantics: true,
      child: CalCard(
        radius: 22.0,
        padding: const EdgeInsetsDirectional.fromSTEB(22.0, 0.0, 16.0, 0.0),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: BigOver(value: value, over: value == null ? null : '/100', size: _Spec.bigNumber),
                  ),
                  const SizedBox(height: 6.0),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14.0,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            CalRing(
              fraction: value == null ? null : value! / 100,
              size: _Spec.bigRing,
              stroke: _Spec.bigStroke,
              child: Icon(icon, size: 20.0, color: theme.colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

/// "6/6 Owners found" over a ring, as Cal AI's protein / carbs / fat.
class _SmallCard extends StatelessWidget {
  const _SmallCard({
    required this.value,
    required this.over,
    required this.label,
    required this.fraction,
    required this.icon,
    this.color,
  });

  final int? value;
  final String? over;
  final String label;
  final double? fraction;
  final IconData icon;

  /// Ring and icon colour (Cal AI's red / orange / blue); ink when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      label: '$label ${value ?? 'none'}${over ?? ''}',
      excludeSemantics: true,
      child: CalCard(
        radius: 18.0,
        padding: const EdgeInsetsDirectional.fromSTEB(12.0, 15.0, 12.0, 11.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: BigOver(value: value, over: value == null ? null : over, size: _Spec.smallNumber),
            ),
            const SizedBox(height: 3.0),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: TextScaler.noScaling,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 13.0,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Center(
              child: CalRing(
                fraction: fraction,
                size: _Spec.smallRing,
                stroke: _Spec.smallStroke,
                color: color,
                child: Icon(icon, size: 18.0, color: color ?? theme.colorScheme.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One scan as Cal AI's "Recently uploaded" row: photo on the left, the
/// product with the time in grey, the owner as the big line, and the two
/// scores under it.
class ScanRow extends StatelessWidget {
  const ScanRow({required this.product, required this.owner, required this.seen});

  final Product product;
  final OwnerTally? owner;
  final DateTime? seen;

  String? get _time {
    final DateTime? t = seen;
    if (t == null) {
      return null;
    }
    final DateTime now = DateTime.now();
    final int h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final String clock = '$h:${t.minute.toString().padLeft(2, '0')}${t.hour < 12 ? 'am' : 'pm'}';
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return clock;
    }
    const List<String> m = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[t.month - 1]} ${t.day}';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final String name = (product.productName?.trim().isNotEmpty ?? false)
        ? product.productName!.trim()
        : (product.brands ?? product.barcode ?? '');
    final String shownName = name.capFirst();
    final int? health = (product.productType ?? ProductType.food) == ProductType.food
        ? HealthScore.fromProduct(product).score
        : null;
    final int? moral = owner?.ethicsScore;
    final String? time = _time;
    final String? url = product.imageFrontSmallUrl ?? product.imageFrontUrl;
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final Widget placeholder = ColoredBox(
      color: dark ? BrandColors.hairlineDark : const Color(0xFFEFEEF4),
      child: Icon(CupertinoIcons.cart, size: 30.0, color: dark ? BrandColors.mutedDark : BrandColors.faint),
    );
    return PressScale(
      scale: 0.97,
      onTap: product.barcode == null
          ? null
          : () => AppNavigator.of(context).push(AppRoutes.PRODUCT(product.barcode!), extra: product),
      child: Container(
        height: _Spec.rowHeight,
        decoration: BoxDecoration(
          color: dark ? BrandColors.fillDark : BrandColors.row,
          borderRadius: BorderRadius.circular(18.0),
          border: Border.all(color: dark ? BrandColors.hairlineDark : const Color(0xFFF1F0F6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: _Spec.rowPhoto,
              child: url == null
                  ? placeholder
                  : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
            ),
            Expanded(
              child: Stack(
                children: <Widget>[
                  if (time != null)
                    PositionedDirectional(
                      top: 14.0,
                      end: 12.0,
                      child: Text(
                        time,
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 13.0, color: muted),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16.0, 0.0, 12.0, 0.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Padding(
                          padding: EdgeInsetsDirectional.only(end: time == null ? 0.0 : 58.0),
                          child: Text(
                            shownName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15.0, letterSpacing: -0.2),
                          ),
                        ),
                        const SizedBox(height: 5.0),
                        Row(
                          children: <Widget>[
                            Icon(CupertinoIcons.building_2_fill, size: 16.0, color: theme.colorScheme.onSurface),
                            const SizedBox(width: 6.0),
                            Expanded(
                              child: Text(
                                owner?.owner.capFirst() ?? 'Owner unknown',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontSize: 18.0,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: -0.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6.0),
                        Row(
                          children: <Widget>[
                            ScoreChip(icon: Icons.balance_rounded, value: moral),
                            const SizedBox(width: 14.0),
                            if (health != null) ScoreChip(icon: CupertinoIcons.heart_fill, value: health),
                          ],
                        ),
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
}

class ScoreChip extends StatelessWidget {
  const ScoreChip({required this.icon, required this.value});

  final IconData icon;
  final int? value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14.0, color: theme.colorScheme.onSurface),
        const SizedBox(width: 4.0),
        Text(
          value == null ? '–' : '$value',
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14.0, color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// No scans yet: a ghost of a scan row over two lines that point at the +,
/// so the first thing to do is obvious.
class _EmptyRow extends StatelessWidget {
  const _EmptyRow();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color bar = dark ? BrandColors.hairlineDark : const Color(0xFFEBEAF1);
    Widget line(final double w, final double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(h / 2)),
    );
    return Container(
      padding: const EdgeInsetsDirectional.all(14.0),
      decoration: BoxDecoration(
        color: dark ? BrandColors.fillDark : BrandColors.row,
        borderRadius: BorderRadius.circular(18.0),
        border: Border.all(color: dark ? BrandColors.hairlineDark : const Color(0xFFF1F0F6)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 72.0,
                height: 72.0,
                decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(14.0)),
                child: Icon(CupertinoIcons.viewfinder, color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 14.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    line(110.0, 10.0),
                    const SizedBox(height: 10.0),
                    line(150.0, 14.0),
                    const SizedBox(height: 10.0),
                    line(80.0, 10.0),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18.0),
          Text("You haven't scanned anything yet", style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 4.0),
          Text(
            'Tap the scanner above to see who really owns a product.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4.0),
        ],
      ),
    );
  }
}
