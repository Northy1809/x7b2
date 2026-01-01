import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_app/data_models/fetched_product.dart';
import 'package:smooth_app/pages/product/product_loader_page.dart';
import 'package:smooth_app/pages/search/search_hit_tile.dart';
import 'package:smooth_app/services/product_search_service.dart';

/// 17/11: Open Food Facts answers "429 Too Many Requests" after a handful of
/// quick product lookups. A tapped search result used to end on "Could not
/// load the product"; now the hit's own data opens, after one quiet retry.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Future<Product?> run(
    final WidgetTester tester, {
    required final List<FetchedProduct> answers,
    final Product? fallback,
    final List<String>? calls,
  }) async {
    Product? opened;
    int i = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ProductLoaderPage(
          barcode: '3017620422003',
          mode: ProductLoaderMode.viewProduct,
          fallback: fallback,
          fetch: (String barcode) async {
            calls?.add(barcode);
            final int k = i < answers.length ? i : answers.length - 1;
            i++;
            return answers[k];
          },
          onOpen: (Product p) => opened = p,
        ),
      ),
    );
    for (int k = 0; k < 6; k++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    return opened;
  }

  const FetchedProduct tooMany = FetchedProduct.error(
    exceptionString: 'TooManyRequestsException: 429',
    isConnected: true,
  );

  testWidgets('a busy server opens the search hit instead of an error', (WidgetTester tester) async {
    final List<String> calls = <String>[];
    final Product hit = productFromHit(
      const SearchHit(barcode: '3017620422003', name: 'Nutella', brands: <String>['Ferrero'], nutriscoreGrade: 'e'),
    );
    final Product? opened = await run(tester, answers: <FetchedProduct>[tooMany], fallback: hit, calls: calls);
    expect(calls.length, 2, reason: 'one quiet retry first');
    expect(opened, same(hit));
    expect(opened!.productName, 'Nutella');
    expect(opened.brands, 'Ferrero');
    expect(opened.nutriscore, 'e');
    expect(find.text('Could not load the product'), findsNothing);
  });

  testWidgets('the retry opens the full product when the server answers', (WidgetTester tester) async {
    final Product full = Product(barcode: '3017620422003', productName: 'Nutella 400 g');
    final Product? opened = await run(
      tester,
      answers: <FetchedProduct>[tooMany, FetchedProduct.found(full)],
      fallback: Product(barcode: '3017620422003', productName: 'Nutella'),
    );
    expect(opened, same(full));
  });

  testWidgets('not in the database, but a hit: the hit opens', (WidgetTester tester) async {
    final Product hit = Product(barcode: '3017620422003', productName: 'Nutella');
    final List<String> calls = <String>[];
    final Product? opened = await run(
      tester,
      answers: <FetchedProduct>[const FetchedProduct.internetNotFound()],
      fallback: hit,
      calls: calls,
    );
    expect(calls.length, 1, reason: 'no retry for a clear "not found"');
    expect(opened, same(hit));
  });

  testWidgets('nothing known and the server down: the error page, after one retry', (WidgetTester tester) async {
    final List<String> calls = <String>[];
    final Product? opened = await run(tester, answers: <FetchedProduct>[tooMany], calls: calls);
    expect(opened, isNull);
    expect(calls.length, 2);
    expect(find.text('Could not load the product'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
