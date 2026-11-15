import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

/// One product hit from Open Food Facts' search engine (search-a-licious).
class SearchHit {
  const SearchHit({
    required this.barcode,
    this.name,
    this.brands = const <String>[],
    this.imageUrl,
    this.nutriscoreGrade,
    this.quantity,
    this.countriesTags = const <String>[],
    this.popularity = 0,
  });

  /// Builds a hit from a search-a-licious document. [langs] is the user's
  /// language order, used to pick the best product name.
  factory SearchHit.fromJson(
    final Map<String, dynamic> json, {
    final List<String> langs = const <String>['en'],
  }) {
    String? name;
    for (final String lang in langs) {
      name = _clean(json['product_name_$lang']);
      if (name != null) {
        break;
      }
    }
    name ??= _clean(json['product_name']);
    if (name == null) {
      for (final MapEntry<String, dynamic> e in json.entries) {
        if (e.key.startsWith('product_name_')) {
          name = _clean(e.value);
          if (name != null) {
            break;
          }
        }
      }
    }
    final dynamic rawBrands = json['brands'];
    final Iterable<dynamic> brandValues = switch (rawBrands) {
      final List<dynamic> list => list,
      final String text => text.split(','),
      _ => const <dynamic>[],
    };
    final List<String> brands = brandValues
        .map(_clean)
        .whereType<String>()
        .toList();
    final dynamic grade = json['nutriscore_grade'];
    final dynamic countries = json['countries_tags'];
    final dynamic popularity = json['popularity_key'] ?? json['unique_scans_n'];
    return SearchHit(
      barcode: json['code'].toString(),
      name: name,
      brands: brands,
      imageUrl:
          _clean(json['image_front_small_url']) ??
          _clean(json['image_small_url']),
      nutriscoreGrade:
          grade is String && RegExp(r'^[a-e]$').hasMatch(grade) ? grade : null,
      quantity: _clean(json['quantity']),
      countriesTags: countries is List
          ? countries.whereType<String>().toList()
          : const <String>[],
      popularity: popularity is num ? popularity.toDouble() : 0,
    );
  }

  final String barcode;
  final String? name;
  final List<String> brands;
  final String? imageUrl;

  /// 'a'..'e', or null when unknown.
  final String? nutriscoreGrade;
  final String? quantity;
  final List<String> countriesTags;
  final double popularity;

  String? get firstBrand => brands.isEmpty ? null : brands.first;

  /// Two hits that would look identical in a suggestion list.
  String get displayKey =>
      '${(name ?? '').toLowerCase().trim()}|${(firstBrand ?? '').toLowerCase().trim()}';

  static String? _clean(final dynamic value) {
    if (value is! String) {
      return null;
    }
    final String s = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.isEmpty ? null : s;
  }
}

class SearchHitsPage {
  const SearchHitsPage({required this.hits, required this.count, required this.page, required this.pageCount});

  const SearchHitsPage.empty() : hits = const <SearchHit>[], count = 0, page = 1, pageCount = 0;

  final List<SearchHit> hits;
  final int count;
  final int page;
  final int pageCount;

  bool get hasMore => page < pageCount;
}

/// A food category in the user's language, from OFF's taxonomy
/// autocomplete (e.g. "Kaffe" -> `en:coffees`).
class CategorySuggestion {
  const CategorySuggestion({required this.tag, required this.name});

  final String tag;
  final String name;
}

/// Client for https://search.openfoodfacts.org (search-a-licious, Elasticsearch).
///
/// Chosen over the classic `cgi/search.pl` because it answers in ~0.2 s and
/// finds far more products: "arla mælk" gave 1551 hits here vs 18 on the
/// Danish classic search, which also often returned 503 (measured 6/11 2026).
class ProductSearchService {
  ProductSearchService({
    http.Client? client,
    this.baseUrl = 'https://search.openfoodfacts.org',
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final Duration timeout;

  static const String _baseFields =
      'code,product_name,brands,image_front_small_url,image_small_url,'
      'nutriscore_grade,quantity,countries_tags,popularity_key';

  /// The fields to ask for: the product name in each of [langs].
  static String fieldsFor(final List<String> langs) =>
      <String>[_baseFields, for (final String l in langs) 'product_name_$l'].join(',');

  /// Product-name languages searched when the caller names none.
  static const List<String> typeaheadLangs = <String>['da', 'en', 'sv', 'nb', 'de'];

  /// Characters with a meaning in Lucene query syntax.
  static final RegExp _special = RegExp(r'[+\-&|!(){}\[\]^"~*?:\\/]');

  static String escapeTerm(final String term) =>
      term.replaceAllMapped(_special, (Match m) => '\\${m[0]}');

  /// Splits user input into lower-case words without Lucene syntax.
  static List<String> words(final String text) => text
      .toLowerCase()
      .replaceAll(_special, ' ')
      .split(RegExp(r'\s+'))
      .where((String w) => w.isNotEmpty)
      .toList();

  /// Query for suggestions while typing: complete words are free text, the
  /// last (unfinished) word is a prefix on product names and brands.
  /// "arla mæ" -> `arla (product_name.da:mæ* OR ... OR brands:mæ*)`.
  static String? buildTypeaheadQuery(final String text, {final List<String> langs = typeaheadLangs}) {
    final List<String> w = words(text);
    if (w.isEmpty) {
      return null;
    }
    final String last = w.removeLast();
    if (last.length < 2) {
      return w.isEmpty ? null : w.join(' ');
    }
    final String prefix = '${escapeTerm(last)}*';
    final String group = <String>[
      for (final String lang in langs) 'product_name.$lang:$prefix',
      'brands:$prefix',
    ].join(' OR ');
    return <String>[...w.map(escapeTerm), '($group)'].join(' ');
  }

  /// Query for a submitted search: plain free text, ranked by relevance.
  static String? buildFullQuery(final String text) {
    final List<String> w = words(text);
    return w.isEmpty ? null : w.map(escapeTerm).join(' ');
  }

  static String categoryQuery(final String tag) =>
      'categories_tags:"${tag.replaceAll('"', '')}"';

  Future<SearchHitsPage> search(
    final String query, {
    final int page = 1,
    final int pageSize = 30,
    final List<String> langs = const <String>['en'],
    final String? sortBy,
  }) async {
    final Uri uri = Uri.parse('$baseUrl/search').replace(
      queryParameters: <String, String>{
        'q': query,
        'langs': langs.join(','),
        'page_size': '$pageSize',
        'page': '$page',
        'fields': fieldsFor(langs),
        'sort_by': ?sortBy,
      },
    );
    final http.Response response = await _client.get(uri).timeout(timeout);
    if (response.statusCode != 200) {
      throw http.ClientException('search ${response.statusCode}', uri);
    }
    final Map<String, dynamic> json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final List<dynamic> rawHits = json['hits'] as List<dynamic>? ?? const <dynamic>[];
    return SearchHitsPage(
      hits: rawHits
          .whereType<Map<String, dynamic>>()
          .where((Map<String, dynamic> h) => h['code'] != null)
          .map((Map<String, dynamic> h) => SearchHit.fromJson(h, langs: langs))
          .toList(),
      count: (json['count'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? page,
      pageCount: (json['page_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// Products matching what the user has typed so far, most popular first.
  Future<List<SearchHit>> typeahead(
    final String text, {
    final String? countryTag,
    final int limit = 6,
    final List<String> langs = typeaheadLangs,
  }) async {
    final String? q = buildTypeaheadQuery(text, langs: langs);
    if (q == null) {
      return const <SearchHit>[];
    }
    final SearchHitsPage page = await search(
      q,
      pageSize: 24,
      langs: langs,
      sortBy: '-popularity_key',
    );
    return dedupe(rerank(page.hits, countryTag: countryTag)).take(limit).toList();
  }

  /// English (or [lang]) category names starting with [text].
  Future<List<CategorySuggestion>> categories(
    final String text, {
    final String lang = 'en',
    final int size = 4,
  }) async {
    final String q = text.trim();
    if (q.length < 2) {
      return const <CategorySuggestion>[];
    }
    final Uri uri = Uri.parse('$baseUrl/autocomplete').replace(
      queryParameters: <String, String>{
        'q': q,
        'lang': lang,
        'taxonomy_names': 'category',
        'size': '$size',
      },
    );
    final http.Response response = await _client.get(uri).timeout(timeout);
    if (response.statusCode != 200) {
      return const <CategorySuggestion>[];
    }
    final Map<String, dynamic> json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final List<dynamic> options = json['options'] as List<dynamic>? ?? const <dynamic>[];
    return <CategorySuggestion>[
      for (final dynamic o in options)
        if (o is Map<String, dynamic> && o['id'] is String && o['text'] is String)
          CategorySuggestion(tag: o['id'] as String, name: _capitalize(o['text'] as String)),
    ];
  }

  /// Puts products sold in the user's country first, keeping the engine's
  /// order otherwise (a stable sort, so relevance still counts).
  static List<SearchHit> rerank(final List<SearchHit> hits, {final String? countryTag}) {
    if (countryTag == null) {
      return hits;
    }
    final List<MapEntry<int, SearchHit>> indexed = hits.asMap().entries.toList();
    int rank(final MapEntry<int, SearchHit> e) =>
        e.key - (e.value.countriesTags.contains(countryTag) ? 1000 : 0);
    indexed.sort((MapEntry<int, SearchHit> a, MapEntry<int, SearchHit> b) => rank(a) - rank(b));
    return indexed.map((MapEntry<int, SearchHit> e) => e.value).toList();
  }

  /// Drops hits without a name and repeated name+brand pairs.
  static List<SearchHit> dedupe(final Iterable<SearchHit> hits) {
    final Set<String> seen = <String>{};
    return <SearchHit>[
      for (final SearchHit h in hits)
        if (h.name != null && seen.add(h.displayKey)) h,
    ];
  }

  /// Most frequent brands among [hits] whose name matches the typed prefix.
  static List<String> brandsFrom(final List<SearchHit> hits, final String text, {final int limit = 3}) {
    final List<String> w = words(text);
    if (w.isEmpty) {
      return const <String>[];
    }
    final String last = w.last;
    final Map<String, int> counts = <String, int>{};
    final Map<String, String> display = <String, String>{};
    for (final SearchHit h in hits) {
      for (final String b in h.brands) {
        final String key = b.toLowerCase();
        if (!key.split(RegExp(r'[\s\-]+')).any((String part) => part.startsWith(last)) &&
            !key.startsWith(last)) {
          continue;
        }
        counts[key] = (counts[key] ?? 0) + 1;
        display.putIfAbsent(key, () => b);
      }
    }
    final List<String> keys = counts.keys.toList()
      ..sort((String a, String b) => counts[b]! - counts[a]!);
    return keys.take(math.max(0, limit)).map((String k) => display[k]!).toList();
  }

  static String _capitalize(final String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
