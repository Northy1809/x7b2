import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_app/pages/companies/companies_page.dart';
import 'package:smooth_app/pages/home/owned_home_page.dart';
import 'package:smooth_app/pages/search/live_search_suggestions.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/owner_insights.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/product_search_service.dart';
import 'package:smooth_app/widgets/company_logo.dart';

/// 15/11: the calendar and the streak are gone from the home page; the
/// companies behind your scans took their place, History became the
/// Companies tab, and the search answers "who owns this brand?" at once.
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
});

List<Product> _scans() => <Product>[
  Product(barcode: '1', productName: 'Nesquik', brands: 'Nesquik'),
  Product(barcode: '2', productName: 'KitKat', brands: 'KitKat'),
  Product(barcode: '3', productName: 'Nutella', brands: 'Nutella'),
];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LogoIndex.instance.online = false;
    LogoIndex.instance.resetForTest();
  });

  Future<void> settle(final WidgetTester tester) async {
    for (int i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  test('knowsBrand: brands and spelling variants only', () {
    final OwnershipLocalDb db = _db();
    expect(db.knowsBrand('kitkat'), isTrue);
    expect(db.knowsBrand('nesquik'), isTrue);
    expect(db.knowsBrand('cornflakes'), isFalse);
    expect(db.knowsBrand(''), isFalse);
  });

  testWidgets('home: no calendar or streak; the companies take their place', (WidgetTester tester) async {
    final List<Product> scans = _scans();
    final HomeSummary summary = HomeSummary(
      products: scans,
      insights: OwnerInsights.compute(scans, _db()),
      lastSeen: <String, DateTime>{for (final Product p in scans) p.barcode!: DateTime.now()},
    );
    await tester.pumpWidget(MaterialApp(home: OwnedHomePage(load: () async => summary)));
    await settle(tester);
    for (final String day in <String>['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']) {
      expect(find.text(day), findsNothing, reason: day);
    }
    expect(find.bySemanticsLabel(RegExp(r'^Nestlé: 67 percent of your scans')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Ferrero SpA: 33 percent')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Companies you avoid: none yet')), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
  });

  testWidgets('Companies tab: count, top 3 share and one row per company', (WidgetTester tester) async {
    // A tall phone: the rows sit under the cards and the scans chart.
    tester.view.physicalSize = const Size(1170, 4200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: CompaniesPage(
          loadProducts: () async => _scans(),
          localDb: () async => _db(),
          ethicsDb: () async => EthicsDb.fromJson(<String, dynamic>{'companies': <dynamic>[], 'updated': ''}),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('behind 3 products'), findsOneWidget);
    expect(find.text('Top 3 make 100 %'), findsOneWidget);
    expect(find.text('All time'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Nestlé, 2 products, 67 percent')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Ferrero SpA, 1 products, 33 percent')), findsOneWidget);
    expect(find.text('Companies you avoid'), findsOneWidget);
  });

  testWidgets('search answers who owns a typed brand', (WidgetTester tester) async {
    final LocalOwnerResult hit = _db().lookup(barcode: '', brands: 'kitkat')!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BrandOwnerAnswer(brand: 'kitkat', result: hit)),
      ),
    );
    await settle(tester);
    expect(find.text('Kitkat is owned by'), findsOneWidget);
    expect(find.text('Nestlé'), findsOneWidget);
  });

  testWidgets('typing a brand in the search shows its owner first (real data)', (WidgetTester tester) async {
    final ProductSearchService offline = ProductSearchService(
      client: MockClient((http.Request r) async => http.Response.bytes(utf8.encode('{"hits":[],"options":[]}'), 200)),
    );
    // Warm the bundled databases outside the fake clock.
    await tester.runAsync(() async {
      await OwnershipLocalDb.load();
      await EthicsDb.load();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveSearchSuggestions(
            text: 'kitkat',
            history: const <String>[],
            onSearch: (_) {},
            onCategory: (_) {},
            service: offline,
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.byType(BrandOwnerAnswer), findsOneWidget);
    expect(find.text('Kitkat is owned by'), findsOneWidget);
    expect(find.text('Nestlé'), findsOneWidget);
  });
}
