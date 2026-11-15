import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smooth_app/services/product_search_service.dart';

Map<String, dynamic> _doc(
  final String code, {
  final String? name,
  final String? nameDa,
  final List<String> brands = const <String>[],
  final List<String> countries = const <String>[],
  final String? grade,
}) => <String, dynamic>{
  'code': code,
  'product_name': ?name,
  'product_name_da': ?nameDa,
  'brands': brands,
  'countries_tags': countries,
  'nutriscore_grade': ?grade,
};

void main() {
  group('query building', () {
    test('typeahead turns the last word into a prefix on names and brands', () {
      final String q = ProductSearchService.buildTypeaheadQuery('Arla mæ')!;
      expect(q, startsWith('arla ('));
      expect(q, contains('product_name.da:mæ*'));
      expect(q, contains('product_name.en:mæ*'));
      expect(q, contains('brands:mæ*'));
      expect(q, endsWith(')'));
    });

    test('typeahead and fields follow the languages asked for', () {
      final String q = ProductSearchService.buildTypeaheadQuery('lait de', langs: <String>['fr', 'en'])!;
      expect(q, contains('product_name.fr:de*'));
      expect(q, isNot(contains('product_name.da')));
      expect(ProductSearchService.fieldsFor(<String>['fr', 'en']), endsWith('product_name_fr,product_name_en'));
    });

    test('a one-letter last word is not used as a prefix', () {
      expect(ProductSearchService.buildTypeaheadQuery('a'), isNull);
      expect(ProductSearchService.buildTypeaheadQuery('arla m'), 'arla');
    });

    test('Lucene syntax typed by the user is stripped', () {
      expect(ProductSearchService.words('coca-cola: (zero)*'), <String>[
        'coca',
        'cola',
        'zero',
      ]);
      expect(ProductSearchService.buildFullQuery('  '), isNull);
      expect(ProductSearchService.buildFullQuery('Nutella  450g'), 'nutella 450g');
    });

    test('category query quotes the tag', () {
      expect(
        ProductSearchService.categoryQuery('en:coffees'),
        'categories_tags:"en:coffees"',
      );
    });
  });

  group('SearchHit.fromJson', () {
    test('prefers the user language name, then the generic name', () {
      final SearchHit hit = SearchHit.fromJson(
        _doc('1', name: 'Milk', nameDa: 'Mælk', brands: <String>['Arla']),
        langs: const <String>['da', 'en'],
      );
      expect(hit.name, 'Mælk');
      expect(hit.firstBrand, 'Arla');
      final SearchHit en = SearchHit.fromJson(_doc('2', name: 'Milk'));
      expect(en.name, 'Milk');
    });

    test('falls back to any localized name and trims brands', () {
      final SearchHit hit = SearchHit.fromJson(<String, dynamic>{
        'code': 3,
        'product_name_fr': ' Lait  entier ',
        'brands': <String>[' Lactel', '', '  '],
      });
      expect(hit.barcode, '3');
      expect(hit.name, 'Lait entier');
      expect(hit.brands, <String>['Lactel']);
    });

    test('accepts brands as a comma separated string', () {
      final SearchHit hit = SearchHit.fromJson(<String, dynamic>{
        'code': '4',
        'brands': 'Oreo, Mondelez',
      });
      expect(hit.brands, <String>['Oreo', 'Mondelez']);
    });

    test('only keeps valid Nutri-Score grades', () {
      expect(SearchHit.fromJson(_doc('5', grade: 'b')).nutriscoreGrade, 'b');
      expect(
        SearchHit.fromJson(_doc('6', grade: 'unknown')).nutriscoreGrade,
        isNull,
      );
    });
  });

  group('ranking', () {
    test('products from the user country come first, order kept otherwise', () {
      final List<SearchHit> hits = <SearchHit>[
        SearchHit.fromJson(_doc('1', name: 'A', countries: <String>['en:france'])),
        SearchHit.fromJson(_doc('2', name: 'B', countries: <String>['en:denmark'])),
        SearchHit.fromJson(_doc('3', name: 'C')),
        SearchHit.fromJson(_doc('4', name: 'D', countries: <String>['en:denmark'])),
      ];
      expect(
        ProductSearchService.rerank(
          hits,
          countryTag: 'en:denmark',
        ).map((SearchHit h) => h.barcode),
        <String>['2', '4', '1', '3'],
      );
      expect(ProductSearchService.rerank(hits), same(hits));
    });

    test('dedupe drops nameless and repeated name+brand hits', () {
      final List<SearchHit> hits = <SearchHit>[
        SearchHit.fromJson(_doc('1', name: 'Nutella', brands: <String>['Ferrero'])),
        SearchHit.fromJson(_doc('2', name: 'nutella ', brands: <String>['ferrero'])),
        SearchHit.fromJson(_doc('3')),
        SearchHit.fromJson(_doc('4', name: 'Nutella', brands: <String>['Nutella'])),
      ];
      expect(
        ProductSearchService.dedupe(hits).map((SearchHit h) => h.barcode),
        <String>['1', '4'],
      );
    });

    test('brand suggestions match the typed prefix, most frequent first', () {
      final List<SearchHit> hits = <SearchHit>[
        SearchHit.fromJson(_doc('1', brands: <String>['Nutella', 'Ferrero'])),
        SearchHit.fromJson(_doc('2', brands: <String>['Ferrero', 'Nutella'])),
        SearchHit.fromJson(_doc('3', brands: <String>['Nutrimuscle'])),
      ];
      expect(ProductSearchService.brandsFrom(hits, 'nut'), <String>[
        'Nutella',
        'Nutrimuscle',
      ]);
      expect(ProductSearchService.brandsFrom(hits, ''), isEmpty);
    });
  });

  group('HTTP', () {
    test('search sends the query and parses hits and paging', () async {
      late Uri seen;
      final ProductSearchService service = ProductSearchService(
        client: MockClient((http.Request request) async {
          seen = request.url;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, dynamic>{
                'hits': <dynamic>[
                  _doc('5711953121234', nameDa: 'Øko mælk', brands: <String>['Arla']),
                  <String, dynamic>{'product_name': 'no code'},
                ],
                'count': 61,
                'page': 1,
                'page_count': 3,
              }),
            ),
            200,
          );
        }),
      );
      final SearchHitsPage page = await service.search(
        'arla mælk',
        sortBy: '-popularity_key',
      );
      expect(seen.path, '/search');
      expect(seen.queryParameters['q'], 'arla mælk');
      expect(seen.queryParameters['sort_by'], '-popularity_key');
      expect(seen.queryParameters['langs'], 'en');
      expect(page.hits.single.name, 'Øko mælk');
      expect(page.count, 61);
      expect(page.hasMore, isTrue);
    });

    test('search without sort leaves sort_by out', () async {
      late Uri seen;
      final ProductSearchService service = ProductSearchService(
        client: MockClient((http.Request request) async {
          seen = request.url;
          return http.Response('{"hits":[],"count":0,"page":1,"page_count":0}', 200);
        }),
      );
      final SearchHitsPage page = await service.search('x');
      expect(seen.queryParameters.containsKey('sort_by'), isFalse);
      expect(page.hasMore, isFalse);
    });

    test('a server error throws so the caller can fall back', () async {
      final ProductSearchService service = ProductSearchService(
        client: MockClient((_) async => http.Response('down', 503)),
      );
      expect(() => service.search('x'), throwsA(isA<http.ClientException>()));
    });

    test('categories are capitalised and errors give an empty list', () async {
      final ProductSearchService ok = ProductSearchService(
        client: MockClient((http.Request request) async {
          expect(request.url.path, '/autocomplete');
          expect(request.url.queryParameters['taxonomy_names'], 'category');
          return http.Response(
            '{"options":[{"id":"en:coffees","text":"kaffe","taxonomy_name":"category"}]}',
            200,
          );
        }),
      );
      final List<CategorySuggestion> c = await ok.categories('kaffe');
      expect(c.single.tag, 'en:coffees');
      expect(c.single.name, 'Kaffe');
      expect(await ok.categories('k'), isEmpty);

      final ProductSearchService down = ProductSearchService(
        client: MockClient((_) async => http.Response('', 500)),
      );
      expect(await down.categories('kaffe'), isEmpty);
    });

    test('typeahead dedupes and limits', () async {
      final ProductSearchService service = ProductSearchService(
        client: MockClient((http.Request request) async {
          expect(request.url.queryParameters['q'], contains('brands:nut*'));
          return http.Response.bytes(
            utf8.encode(
              jsonEncode(<String, dynamic>{
                'hits': <dynamic>[
                  for (int i = 0; i < 10; i++)
                    _doc('$i', name: i.isEven ? 'Nutella' : 'Nut $i', brands: <String>['Ferrero']),
                ],
                'count': 10,
                'page': 1,
                'page_count': 1,
              }),
            ),
            200,
          );
        }),
      );
      final List<SearchHit> hits = await service.typeahead('nut', limit: 4);
      expect(hits.map((SearchHit h) => h.name), <String>['Nutella', 'Nut 1', 'Nut 3', 'Nut 5']);
      expect(await service.typeahead(' '), isEmpty);
    });
  });
}
