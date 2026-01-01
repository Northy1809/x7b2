import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/l10n/app_localizations.dart';
import 'package:smooth_app/pages/companies/companies_page.dart';
import 'package:smooth_app/pages/home/owned_home_page.dart';
import 'package:smooth_app/pages/navigator/app_navigator.dart';
import 'package:smooth_app/pages/owner/owner_page.dart';
import 'package:smooth_app/pages/search/search_page.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/owner_insights.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/widgets/cal_ui.dart';
import 'package:smooth_app/widgets/company_logo.dart';

import '../tests_utils/local_database_mock.dart';

/// 18/11: every row that shows a product or a company opens it. The home
/// page's recent scans, its companies, the Companies tab, and a company
/// page's products and brands.
OwnershipLocalDb _db() => OwnershipLocalDb.fromJson(<String, dynamic>{
  'strings': <String>['Nestlé', 'Nesquik', 'Ferrero SpA', 'Nutella', 'KitKat'],
  'brands': <String, dynamic>{
    'nesquik': <dynamic>[0, 'w', <int>[1, 0], ''],
    'nutella': <dynamic>[2, 'w', <int>[3, 2], ''],
    'kitkat': <dynamic>[0, 'w', <int>[4, 0], ''],
  },
  'by_country': <String, dynamic>{},
  'prefix': <String, dynamic>{},
  'emb': <String, dynamic>{},
  'companies': <String, dynamic>{},
  // Nestlé's best-known brands, lower case as in the data.
  'top': <String, dynamic>{
    '0': <String>['nesquik', 'kitkat'],
  },
});

// Lower-case brands, as Open Food Facts often has them.
List<Product> _scans() => <Product>[
  Product(barcode: '1', productName: 'Nesquik', brands: 'nesquik'),
  Product(barcode: '2', productName: 'KitKat', brands: 'kitkat'),
  Product(barcode: '3', productName: 'Nutella', brands: 'nutella'),
];

EthicsDb _noEthics() => EthicsDb.fromJson(<String, dynamic>{'companies': <dynamic>[], 'updated': ''});

void main() {
  final List<(String, Object?)> pushed = <(String, Object?)>[];

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LogoIndex.instance.online = false;
    LogoIndex.instance.resetForTest();
    pushed.clear();
    AppNavigator.debugPush = (String route, Object? extra) => pushed.add((route, extra));
  });

  tearDown(() => AppNavigator.debugPush = null);

  void tallPhone(final WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 5200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(final WidgetTester tester, {final int rounds = 8}) async {
    for (int i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> pump(final WidgetTester tester, final Widget home) async {
    // As in the app: the router, the languages and the local database.
    await tester.pumpWidget(
      AppNavigator(
        child: ChangeNotifierProvider<LocalDatabase>.value(
          value: MockLocalDatabase(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: home,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  OwnerPage nestle() =>
      OwnerPage(name: 'Nestlé', localDb: () async => _db(), ethicsDb: () async => _noEthics(), loadProducts: () async => _scans());

  testWidgets('home: a recent scan opens its product page', (WidgetTester tester) async {
    tallPhone(tester);
    final List<Product> scans = _scans();
    final HomeSummary summary = HomeSummary(
      products: scans,
      insights: OwnerInsights.compute(scans, _db()),
      lastSeen: <String, DateTime>{for (final Product p in scans) p.barcode!: DateTime.now()},
    );
    await pump(tester, OwnedHomePage(load: () async => summary));
    await tester.tap(find.text('KitKat').last);
    await tester.pump();
    expect(pushed, hasLength(1));
    expect(pushed.single.$1, startsWith('/_product/2'));
    expect(pushed.single.$2, same(scans[1]));
  });

  testWidgets('home: a company opens its page', (WidgetTester tester) async {
    tallPhone(tester);
    final List<Product> scans = _scans();
    final HomeSummary summary = HomeSummary(
      products: scans,
      insights: OwnerInsights.compute(scans, _db()),
      lastSeen: <String, DateTime>{for (final Product p in scans) p.barcode!: DateTime.now()},
    );
    await pump(tester, OwnedHomePage(load: () async => summary));
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Nestlé: 67 percent of your scans')));
    await settle(tester);
    expect(find.byType(OwnerPage), findsOneWidget);
  });

  testWidgets('home: the average score cards are buttons', (WidgetTester tester) async {
    tallPhone(tester);
    final List<Product> scans = _scans();
    final HomeSummary summary = HomeSummary(
      products: scans,
      insights: OwnerInsights.compute(scans, _db()),
      lastSeen: <String, DateTime>{for (final Product p in scans) p.barcode!: DateTime.now()},
    );
    await pump(tester, OwnedHomePage(load: () async => summary));
    final Finder moral = find.bySemanticsLabel(RegExp(r'^Average moral score'));
    expect(tester.getSemantics(moral), isSemantics(isButton: true));
    // Outside the tabs there is no Companies tab to switch to: nothing breaks.
    await tester.tap(moral);
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Companies tab: a row opens the company page', (WidgetTester tester) async {
    tallPhone(tester);
    await pump(
      tester,
      CompaniesPage(loadProducts: () async => _scans(), localDb: () async => _db(), ethicsDb: () async => _noEthics()),
    );
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Ferrero SpA, 1 product, 33 percent')));
    await settle(tester);
    expect(find.byType(OwnerPage), findsOneWidget);
    expect(find.text('Ferrero SpA'), findsWidgets);
  });

  testWidgets('company page: a scanned product opens, its brand shows with a capital', (WidgetTester tester) async {
    tallPhone(tester);
    await pump(tester, nestle());
    // The row's brand line: "nesquik" in the data, "Nesquik" on screen.
    expect(find.text('nesquik'), findsNothing);
    final Finder row = find.widgetWithText(CalNavRow, 'KitKat');
    expect(row, findsOneWidget);
    await tester.ensureVisible(row);
    await tester.tap(row);
    await tester.pump();
    expect(pushed, hasLength(1));
    expect(pushed.single.$1, startsWith('/_product/2'));
  });

  testWidgets('company page: a brand opens the search for it',(WidgetTester tester) async {
    tallPhone(tester);
    await pump(tester, nestle());
    final Finder pill = find.widgetWithText(CalPill, 'Nesquik');
    expect(pill, findsOneWidget);
    await tester.ensureVisible(pill);
    await tester.tap(pill);
    await settle(tester, rounds: 4);
    expect(find.byType(SearchPage), findsOneWidget);
    expect(tester.widget<SearchPage>(find.byType(SearchPage)).initialQuery, 'Nesquik');
    await settle(tester, rounds: 4);
  });
}
