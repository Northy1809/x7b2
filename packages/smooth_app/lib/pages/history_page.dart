import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/data_models/product_list.dart';
import 'package:smooth_app/database/dao_product_list.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/pages/home/owned_home_page.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/cal_ui.dart';

/// Every scan, newest first, under day headings ("Today", "Yesterday",
/// "Nov 12"), as the same Cal AI photo rows as the home page. Swipe a row
/// left to take it off the list (with Undo). Replaces Open Food Facts'
/// product list page (16/11).
class HistoryPage extends StatefulWidget {
  const HistoryPage({this.load, super.key});

  /// For tests.
  final Future<HomeSummary> Function()? load;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  Future<HomeSummary>? _summary;
  LocalDatabase? _db;

  /// Rows swiped away, hidden at once while the database catches up.
  final Set<String> _removed = <String>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.load != null) {
      _summary ??= widget.load!();
      return;
    }
    _db = context.watch<LocalDatabase>();
    _summary = HomeSummary.load(_db!);
  }

  Future<void> _remove(final Product product) async {
    final String? barcode = product.barcode;
    final LocalDatabase? db = _db;
    if (barcode == null) {
      return;
    }
    Haptics.remove();
    setState(() => _removed.add(barcode));
    if (db != null) {
      await DaoProductList(db).set(ProductList.history(), barcode, false);
      db.notifyListeners();
    }
    if (!mounted) {
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Removed from history'),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            setState(() => _removed.remove(barcode));
            if (db != null) {
              await DaoProductList(db).set(ProductList.history(), barcode, true);
              db.notifyListeners();
            }
          },
        ),
      ),
    );
  }

  static String _day(final DateTime? t) {
    if (t == null) {
      return 'Earlier';
    }
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime day = DateTime(t.year, t.month, t.day);
    final int ago = today.difference(day).inDays;
    if (ago <= 0) {
      return 'Today';
    }
    if (ago == 1) {
      return 'Yesterday';
    }
    const List<String> m = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return t.year == now.year ? '${m[t.month - 1]} ${t.day}' : '${m[t.month - 1]} ${t.day}, ${t.year}';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<HomeSummary>(
    future: _summary,
    builder: (BuildContext context, AsyncSnapshot<HomeSummary> snap) {
      final HomeSummary? s = snap.data;
      const String title = 'History';
      if (s == null) {
        return const CalPage(
          title: title,
          children: <Widget>[
            Padding(padding: EdgeInsetsDirectional.only(top: 80.0), child: Center(child: CalLoader())),
          ],
        );
      }
      final List<Product> products = <Product>[
        for (final Product p in s.products)
          if (!_removed.contains(p.barcode)) p,
      ];
      if (products.isEmpty) {
        return const CalPage(
          title: title,
          children: <Widget>[
            Padding(
              padding: EdgeInsetsDirectional.only(top: 60.0),
              child: CalEmpty(
                icon: CupertinoIcons.viewfinder,
                title: 'No scans yet',
                body: 'Tap + and snap a product to see who really owns it.',
              ),
            ),
          ],
        );
      }
      final List<Widget> children = <Widget>[];
      String? lastDay;
      int i = 0;
      for (final Product p in products) {
        final DateTime? seen = s.lastSeen[p.barcode];
        final String day = _day(seen);
        if (day != lastDay) {
          children.add(
            Padding(
              padding: EdgeInsetsDirectional.only(top: lastDay == null ? 0.0 : 18.0, bottom: 10.0),
              child: CalSectionTitle(day),
            ),
          );
          lastDay = day;
        }
        children.add(
          Padding(
            key: ValueKey<String?>(p.barcode),
            padding: const EdgeInsetsDirectional.only(bottom: 13.0),
            child: FadeUpIn(
              index: i++,
              child: Dismissible(
                key: ValueKey<String>('dismiss-${p.barcode}'),
                direction: DismissDirection.endToStart,
                onDismissed: (_) => unawaited(_remove(p)),
                background: const _SwipeBackground(),
                child: ScanRow(product: p, owner: s.ownerOf(p), seen: seen),
              ),
            ),
          ),
        );
      }
      return CalPage(
        title: title,
        subtitle: '${products.length} ${products.length == 1 ? 'product' : 'products'} · swipe left to remove',
        children: children,
      );
    },
  );
}

/// What shows behind a row while it is swiped: a grey rounded block with a
/// trash can, no red (Owned has no colour outside photos).
class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    return Container(
      alignment: AlignmentDirectional.centerEnd,
      padding: const EdgeInsetsDirectional.only(end: 24.0),
      decoration: BoxDecoration(
        color: dark ? BrandColors.hairlineDark : BrandColors.hairline,
        borderRadius: BorderRadius.circular(18.0),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(CupertinoIcons.trash, color: theme.colorScheme.onSurface),
          const SizedBox(height: 4.0),
          Text('Remove', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
