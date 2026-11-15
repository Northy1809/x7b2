import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_app/services/external_product_lookup.dart';

http.Response _json(final Object body, [final int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ExternalProductLookup.resetForTest();
  });

  test('UPCitemdb hit becomes a product with name, brand and picture', () async {
    late Uri seen;
    final ExternalProductLookup lookup = ExternalProductLookup(
      client: MockClient((http.Request request) async {
        seen = request.url;
        return _json(<String, dynamic>{
          'code': 'OK',
          'total': 1,
          'items': <dynamic>[
            <String, dynamic>{
              'ean': '4006381333931',
              'title': 'Stabilo Point 88 Fineliner  0.4mm',
              'brand': 'STABILO',
              'category': 'Office Supplies > Pens',
              'images': <String>['http://insecure.example/a.jpg', 'https://img.example/b.jpg'],
            },
          ],
        });
      }),
    );
    final Product? p = await lookup.lookup('4006381333931');
    expect(seen.host, 'api.upcitemdb.com');
    expect(seen.queryParameters['upc'], '4006381333931');
    expect(p, isNotNull);
    expect(p!.productName, 'Stabilo Point 88 Fineliner 0.4mm');
    expect(p.brands, 'STABILO');
    expect(p.imageFrontUrl, 'https://img.example/b.jpg');
    expect(p.productType, ProductType.product);
    expect(ExternalProductLookup.sourceOf(p), ExternalProductSource.upcItemDb);
    // FetchedProduct.isValid needs states.
    expect(p.statesTags, isNotEmpty);
  });

  test('books go to Open Library and the publisher is the brand', () async {
    final ExternalProductLookup lookup = ExternalProductLookup(
      client: MockClient((http.Request request) async {
        expect(request.url.toString(), 'https://openlibrary.org/isbn/9780141036144.json');
        return _json(<String, dynamic>{
          'title': 'Nineteen Eighty-Four',
          'publishers': <String>['Penguin Books'],
          'covers': <int>[-1, 8575708],
        });
      }),
    );
    final Product? p = await lookup.lookup('9780141036144');
    expect(p!.productName, 'Nineteen Eighty-Four');
    expect(p.brands, 'Penguin Books');
    expect(p.imageFrontUrl, 'https://covers.openlibrary.org/b/id/8575708-M.jpg');
    expect(ExternalProductLookup.sourceOf(p), ExternalProductSource.openLibrary);
  });

  test('no hit, errors and in-store codes give null without throwing', () async {
    int calls = 0;
    final ExternalProductLookup lookup = ExternalProductLookup(
      client: MockClient((http.Request request) async {
        calls++;
        if (request.url.queryParameters['upc'] == '5000000000017') {
          return _json(<String, dynamic>{'code': 'TOO_FAST'}, 429);
        }
        return _json(<String, dynamic>{'code': 'OK', 'total': 0, 'items': <dynamic>[]});
      }),
    );
    expect(await lookup.lookup('5000000000000'), isNull);
    expect(await lookup.lookup('5000000000017'), isNull);
    // Weighed fresh food: never sent anywhere.
    expect(await lookup.lookup('2012345678903'), isNull);
    expect(calls, 2);
    // A miss is remembered for the session.
    expect(await lookup.lookup('5000000000000'), isNull);
    expect(calls, 2);
    // A rate limit is not a miss: asked again next time.
    expect(await lookup.lookup('5000000000017'), isNull);
    expect(calls, 3);
  });

  test('answers are remembered between app starts', () async {
    int calls = 0;
    final ExternalProductLookup first = ExternalProductLookup(
      client: MockClient((http.Request request) async {
        calls++;
        return _json(<String, dynamic>{
          'code': 'OK',
          'items': <dynamic>[
            <String, dynamic>{'title': 'Fineliner', 'brand': 'STABILO'},
          ],
        });
      }),
    );
    expect((await first.lookup('4006381333931'))?.brands, 'STABILO');
    ExternalProductLookup.resetForTest(); // a new app start
    final ExternalProductLookup second = ExternalProductLookup(
      client: MockClient((http.Request request) async {
        calls++;
        return _json(<String, dynamic>{}, 500);
      }),
    );
    final Product? again = await second.lookup('4006381333931');
    expect(again?.productName, 'Fineliner');
    expect(ExternalProductLookup.sourceOf(again!), ExternalProductSource.upcItemDb);
    expect(calls, 1);
  });

  test('Open Food Facts products have no external source', () {
    expect(ExternalProductLookup.sourceOf(Product(barcode: '1')), isNull);
  });
}
