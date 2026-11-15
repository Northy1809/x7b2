import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:smooth_app/pages/product/product_page/overview/alternatives_section.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/product_search_service.dart';

SearchHit _hit(
  final String code,
  final String? grade, {
  final String? name,
  final List<String> countries = const <String>[],
}) => SearchHit.fromJson(<String, dynamic>{
  'code': code,
  'product_name': name ?? 'Product $code',
  'brands': <String>['Brand $code'],
  'nutriscore_grade': ?grade,
  'countries_tags': countries,
});

void main() {
  test('most specific categories first, max three', () {
    expect(
      AlternativesFinder.candidateCategories(<String>[
        'en:spreads',
        'en:sweet-spreads',
        'fr:pates-a-tartiner',
        'en:Produits à tartiner',
        'en:hazelnut-spreads',
        'en:cocoa-and-hazelnuts-spreads',
      ]),
      <String>['en:cocoa-and-hazelnuts-spreads', 'en:hazelnut-spreads', 'en:sweet-spreads'],
    );
    expect(AlternativesFinder.candidateCategories(null), isEmpty);
  });

  test('only better grades, best first, local before foreign', () {
    final AlternativesFinder f = AlternativesFinder(service: ProductSearchService());
    final List<SearchHit> picked = f.pick(
      <SearchHit>[
        _hit('1', 'e'),
        _hit('2', 'c'),
        _hit('3', 'b'),
        _hit('4', 'b', countries: <String>['en:denmark']),
        _hit('5', null),
        _hit('self', 'a'),
        _hit('6', 'd'),
      ],
      barcode: 'self',
      currentGrade: AlternativesFinder.grades.indexOf('d'),
      countryTag: 'en:denmark',
    );
    expect(picked.map((SearchHit h) => h.barcode), <String>['4', '3', '2']);
  });

  test('unknown current grade suggests only A and B', () {
    final AlternativesFinder f = AlternativesFinder(service: ProductSearchService());
    final List<SearchHit> picked = f.pick(
      <SearchHit>[_hit('1', 'a'), _hit('2', 'c'), _hit('3', 'b')],
      barcode: 'x',
      currentGrade: -1,
    );
    expect(picked.map((SearchHit h) => h.barcode), <String>['1', '3']);
  });

  test('never the same owner; a better-rated company counts even at the same grade', () {
    final AlternativesFinder f = AlternativesFinder(
      service: ProductSearchService(),
      ownerDb: OwnershipLocalDb.fromJson(<String, dynamic>{
        'strings': <String>['BadCo', 'GoodCo', 'OkCo'],
        'brands': <String, dynamic>{
          'brand 1': <dynamic>[
            0,
            'w',
            <int>[0],
            '',
          ],
          'brand 2': <dynamic>[
            1,
            'w',
            <int>[1],
            '',
          ],
          'brand 3': <dynamic>[
            2,
            'w',
            <int>[2],
            '',
          ],
        },
        'by_country': <String, dynamic>{},
        'prefix': <String, dynamic>{},
        'emb': <String, dynamic>{},
        'companies': <String, dynamic>{},
      }),
      ethicsDb: EthicsDb.fromJson(<String, dynamic>{
        'companies': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'bad',
            'name': 'BadCo',
            'issues': <Map<String, dynamic>>[
              <String, dynamic>{
                'cat': 'people',
                'sev': 3,
                'year': 2025,
                'title': 'x',
                'sources': <Map<String, String>>[
                  <String, String>{'title': 's', 'url': 'https://example.org'},
                ],
              },
              <String, dynamic>{
                'cat': 'climate',
                'sev': 3,
                'year': 2025,
                'title': 'y',
                'sources': <Map<String, String>>[
                  <String, String>{'title': 's', 'url': 'https://example.org'},
                ],
              },
            ],
          },
          <String, dynamic>{'id': 'good', 'name': 'GoodCo'},
          <String, dynamic>{
            'id': 'ok',
            'name': 'OkCo',
            'issues': <Map<String, dynamic>>[
              <String, dynamic>{
                'cat': 'people',
                'sev': 3,
                'year': 2025,
                'title': 'x',
                'sources': <Map<String, String>>[
                  <String, String>{'title': 's', 'url': 'https://example.org'},
                ],
              },
            ],
          },
        ],
      }),
    );
    List<String> pick({bool Function(List<String>)? avoided}) => f
        .pick(
          <SearchHit>[_hit('1', 'd'), _hit('2', 'd'), _hit('3', 'd')],
          barcode: 'x',
          currentGrade: AlternativesFinder.grades.indexOf('d'),
          currentOwnerNames: const <String>['BadCo'],
          currentEthics: 45,
          isAvoided: avoided,
        )
        .map((SearchHit h) => h.barcode)
        .toList();
    // 1 is BadCo itself; 3 (OkCo, 55) is not clearly better than 45; 2 (GoodCo, 70) is.
    expect(pick(), <String>['2']);
    expect(pick(avoided: (List<String> names) => names.contains('GoodCo')), isEmpty);
  });

  test('falls back to a broader category when too few results', () async {
    final List<String> queried = <String>[];
    final AlternativesFinder f = AlternativesFinder(
      service: ProductSearchService(
        client: MockClient((http.Request r) async {
          final String q = r.url.queryParameters['q']!;
          queried.add(q);
          final List<Map<String, dynamic>> hits = q.contains('en:hazelnut-spreads')
              ? <Map<String, dynamic>>[
                  <String, dynamic>{'code': '1', 'product_name': 'Spread A', 'nutriscore_grade': 'a'},
                  <String, dynamic>{'code': '2', 'product_name': 'Spread B', 'nutriscore_grade': 'b'},
                ]
              : <Map<String, dynamic>>[
                  <String, dynamic>{'code': '9', 'product_name': 'Nutella clone', 'nutriscore_grade': 'e'},
                ];
          return http.Response.bytes(
            utf8.encode(jsonEncode(<String, dynamic>{'hits': hits, 'count': hits.length, 'page': 1, 'page_count': 1})),
            200,
          );
        }),
      ),
    );
    final Product nutella = Product(
      barcode: '3017620422003',
      nutriscore: 'e',
      categoriesTags: const <String>['en:spreads', 'en:hazelnut-spreads', 'en:cocoa-and-hazelnuts-spreads'],
    );
    final List<SearchHit> hits = await f.find(nutella);
    expect(queried.first, contains('en:cocoa-and-hazelnuts-spreads'));
    expect(hits.map((SearchHit h) => h.name), <String>['Spread A', 'Spread B']);
  });
}
