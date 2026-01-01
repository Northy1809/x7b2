import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/l10n/app_localizations.dart';
import 'package:smooth_app/pages/owner/owner_page.dart';
import 'package:smooth_app/pages/search/live_search_suggestions.dart';
import 'package:smooth_app/pages/search/search_hit_tile.dart';
import 'package:smooth_app/pages/search/search_page.dart';
import 'package:smooth_app/pages/search/search_product_helper.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/product_search_service.dart';
import 'package:smooth_app/widgets/cal_ui.dart';
import 'package:smooth_app/widgets/company_logo.dart';

import '../../tests_utils/local_database_mock.dart';

/// 17/11: every way through the search ends on the right page. Typing,
/// tapping a suggestion, running the search, tapping a result, a recent
/// search and a company: each must open what it shows, with the keyboard
/// out of the way.
Map<String, dynamic> _hit(final String code, final String name, final String brand) => <String, dynamic>{
  'code': code,
  'product_name': name,
  'brands': <String>[brand],
};

ProductSearchService _engine() => ProductSearchService(
  client: MockClient((http.Request request) async {
    if (request.url.path == '/autocomplete') {
      return http.Response('{"options":[]}', 200);
    }
    final List<Map<String, dynamic>> hits = <Map<String, dynamic>>[
      _hit('1', 'nutella', 'Ferrero'),
      _hit('2', 'Nutella Go', 'Ferrero'),
    ];
    return http.Response.bytes(
      utf8.encode(jsonEncode(<String, dynamic>{'hits': hits, 'count': hits.length, 'page': 1, 'page_count': 1})),
      200,
    );
  }),
);

/// The search with its history in memory (the app keeps it in Hive).
class _Helper extends SearchProductHelper {
  _Helper(this.history) : super(service: _engine());

  final List<String> history;

  @override
  List<String> getAllQueries(final LocalDatabase localDatabase) => history.reversed.toList();

  @override
  Future<void> addQuery(final LocalDatabase localDatabase, final String query) async =>
      history
        ..remove(query)
        ..add(query);

  @override
  Future<bool> removeQuery(final LocalDatabase localDatabase, final String query) async => history.remove(query);
}

void main() {
  late MockLocalDatabase db;
  final List<SearchHit> opened = <SearchHit>[];
  late List<String> history;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LogoIndex.instance.online = false;
    LogoIndex.instance.resetForTest();
    db = MockLocalDatabase();
    history = <String>[];
    opened.clear();
    debugOpenSearchHit = opened.add;
  });

  tearDown(() => debugOpenSearchHit = null);

  Future<void> settle(final WidgetTester tester, {final int rounds = 10}) async {
    for (int i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> pumpSearch(final WidgetTester tester) async {
    await tester.runAsync(() async {
      await OwnershipLocalDb.load();
      await EthicsDb.load();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<LocalDatabase>.value(
        value: db,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SearchPage(_Helper(history), autofocus: false, showBackButton: false),
        ),
      ),
    );
    await settle(tester, rounds: 4);
  }

  bool fieldFocused(final WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus;

  testWidgets('a product in the suggestions opens, and the keyboard goes down', (WidgetTester tester) async {
    await pumpSearch(tester);
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'nut');
    await settle(tester);
    expect(fieldFocused(tester), isTrue);
    // The engine's lower-case name shows with a capital.
    expect(find.text('Nutella'), findsOneWidget);
    await tester.tap(find.text('Nutella'));
    await tester.pump();
    expect(opened.map((SearchHit h) => h.barcode), <String>['1']);
    expect(fieldFocused(tester), isFalse);
  });

  testWidgets('"Search for" shows the results with the keyboard down; a result opens', (WidgetTester tester) async {
    await pumpSearch(tester);
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'nutella');
    await settle(tester);
    await tester.tap(find.textContaining('Search for'));
    await settle(tester);
    expect(fieldFocused(tester), isFalse);
    expect(find.text('Nutella Go'), findsOneWidget);
    await tester.tap(find.text('Nutella Go'));
    await tester.pump();
    expect(opened.map((SearchHit h) => h.barcode), <String>['2']);
    expect(history, <String>['nutella']);
  });

  testWidgets("the keyboard's Search key runs the search", (WidgetTester tester) async {
    await pumpSearch(tester);
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'nutella');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    expect(find.text('Nutella Go'), findsOneWidget);
    expect(fieldFocused(tester), isFalse);
    await settle(tester, rounds: 3);
  });

  testWidgets('a recent search runs again with a tap', (WidgetTester tester) async {
    history.add('nutella');
    await pumpSearch(tester);
    await settle(tester);
    // Shown with a capital, as every label.
    expect(find.text('Nutella'), findsWidgets);
    await tester.tap(find.text('Nutella').first);
    await settle(tester);
    expect(find.text('Nutella Go'), findsOneWidget);
    await settle(tester, rounds: 3);
  });

  testWidgets("a brand's owner opens as a full page over the search", (WidgetTester tester) async {
    await pumpSearch(tester);
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'kitkat');
    await settle(tester);
    expect(find.byType(BrandOwnerAnswer), findsOneWidget);
    await tester.tap(find.byType(BrandOwnerAnswer));
    await settle(tester, rounds: 6);
    expect(find.byType(OwnerPage), findsOneWidget);
    // The search is underneath, not around the company page.
    expect(find.byType(CalSearchField), findsNothing);
  });
}
