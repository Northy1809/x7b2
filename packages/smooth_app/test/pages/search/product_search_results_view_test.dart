import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_app/pages/search/product_search_results_view.dart';
import 'package:smooth_app/services/avoided_owners.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/product_search_service.dart';

Map<String, dynamic> _hit(final String code, final String name) => <String, dynamic>{
  'code': code,
  'product_name': name,
  'brands': <String>['Brand $code'],
};

ProductSearchService _service({
  required final List<Map<String, dynamic>> text,
  required final List<Map<String, dynamic>> prefix,
  final int status = 200,
}) => ProductSearchService(
  client: MockClient((http.Request request) async {
    if (status != 200) {
      return http.Response('down', status);
    }
    if (request.url.path == '/autocomplete') {
      return http.Response('{"options":[]}', 200);
    }
    final bool isPrefix = request.url.queryParameters['q']!.contains('*');
    final List<Map<String, dynamic>> hits = isPrefix ? prefix : text;
    return http.Response.bytes(
      utf8.encode(
        jsonEncode(<String, dynamic>{
          'hits': hits,
          'count': hits.length,
          'page': 1,
          'page_count': 1,
        }),
      ),
      200,
    );
  }),
);

Future<void> _pump(final WidgetTester tester, final Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  for (int i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}

void main() {
  testWidgets('shows matches, then only new prefix matches under a title', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      ProductSearchResultsView(
        query: 'nutella',
        service: _service(
          text: <Map<String, dynamic>>[_hit('1', 'Nutella'), _hit('2', 'Nutella Go')],
          prefix: <Map<String, dynamic>>[_hit('2', 'Nutella Go'), _hit('3', 'Nutella Biscuits')],
        ),
      ),
    );
    expect(find.text('2 products match "nutella"'), findsOneWidget);
    expect(find.text('Nutella'), findsOneWidget);
    expect(find.text('Nutella Go'), findsOneWidget);
    expect(find.text('More suggestions'), findsOneWidget);
    expect(find.text('Nutella Biscuits'), findsOneWidget);
  });

  testWidgets('no title for a section with nothing new', (WidgetTester tester) async {
    await _pump(
      tester,
      ProductSearchResultsView(
        query: 'nutella',
        service: _service(
          text: <Map<String, dynamic>>[_hit('1', 'Nutella')],
          prefix: <Map<String, dynamic>>[_hit('1', 'Nutella')],
        ),
      ),
    );
    expect(find.text('Nutella'), findsOneWidget);
    expect(find.text('More suggestions'), findsNothing);
  });

  testWidgets('says so and offers a retry when the engine is down', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      ProductSearchResultsView(
        query: 'nutella',
        service: _service(text: const <Map<String, dynamic>>[], prefix: const <Map<String, dynamic>>[], status: 503),
      ),
    );
    expect(find.text('Search is not answering'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('empty result explains what to do', (WidgetTester tester) async {
    await _pump(
      tester,
      ProductSearchResultsView(
        query: 'xyzzy',
        service: _service(text: const <Map<String, dynamic>>[], prefix: const <Map<String, dynamic>>[]),
      ),
    );
    expect(find.text('No products found for "xyzzy"'), findsOneWidget);
  });

  testWidgets('hiding avoided companies drops their products and empty titles', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    AvoidedOwners.instance.resetForTest();
    await tester.runAsync(() async {
      await AvoidedOwners.instance.add('Ferrero');
      await AvoidedOwners.instance.setHideInSearch(true);
    });
    final OwnershipLocalDb db = OwnershipLocalDb.fromJson(<String, dynamic>{
      'strings': <String>['Ferrero'],
      'brands': <String, dynamic>{
        'brand 1': <dynamic>[0, 'w'],
        'brand 3': <dynamic>[0, 'w'],
      },
      'by_country': <String, dynamic>{},
      'prefix': <String, dynamic>{},
      'emb': <String, dynamic>{},
      'companies': <String, dynamic>{},
    });
    await _pump(
      tester,
      ProductSearchResultsView(
        query: 'nutella',
        localDb: () async => db,
        service: _service(
          text: <Map<String, dynamic>>[_hit('1', 'Nutella')],
          prefix: <Map<String, dynamic>>[_hit('3', 'Nutella Biscuits')],
        ),
      ),
    );
    expect(find.text('Nutella'), findsNothing);
    expect(find.text('More suggestions'), findsNothing);
    expect(find.textContaining('Every product here is from a company you avoid'), findsOneWidget);
    await tester.runAsync(() async {
      await AvoidedOwners.instance.remove('Ferrero');
      await AvoidedOwners.instance.setHideInSearch(false);
    });
    AvoidedOwners.instance.resetForTest();
  });
}
