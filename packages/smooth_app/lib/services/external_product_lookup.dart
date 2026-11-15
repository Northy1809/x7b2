import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_app/helpers/gs1_code.dart';

/// Where a product found outside Open Food Facts came from.
enum ExternalProductSource {
  upcItemDb('UPCitemdb', 'https://www.upcitemdb.com/upc/'),
  openLibrary('Open Library', 'https://openlibrary.org/isbn/');

  const ExternalProductSource(this.label, this.pageUrl);

  final String label;
  final String pageUrl;
}

/// Second opinion for barcodes Open Food Facts (all its databases: food,
/// beauty, pet food and other products) does not know. It only needs a name
/// and a brand: the brand is what the ownership lookup runs on.
///
/// * Books (ISBN, 978/979): Open Library, free and open (openlibrary.org/developers/api).
/// * Everything else: UPCitemdb's free trial endpoint, no key, 100 lookups
///   a day per device (upcitemdb.com/api/explorer). Strong on non-food
///   goods (electronics, household, office, toys).
class ExternalProductLookup {
  ExternalProductLookup({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration timeout = Duration(seconds: 6);

  /// Marker stored in [Product.creator] so the app can tell these apart.
  static const String creatorPrefix = 'owned-external:';

  /// Answers so far, so the same code isn't asked twice (the free
  /// UPCitemdb quota is small). Kept on the phone between app starts:
  /// hits for good, misses for [missTtl] (the databases grow).
  static final Map<String, DateTime> _misses = <String, DateTime>{};
  static final Map<String, Product> _hits = <String, Product>{};
  static Future<void>? _restoring;

  static const Duration missTtl = Duration(days: 14);
  static const String _prefsKey = 'owned_external_lookups';
  static const int _maxSaved = 400;

  static Future<void> _restore() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_prefsKey);
      if (raw == null) {
        return;
      }
      final Map<String, dynamic> saved = jsonDecode(raw) as Map<String, dynamic>;
      for (final MapEntry<String, dynamic> e in saved.entries) {
        final Map<String, dynamic> v = e.value as Map<String, dynamic>;
        final Map<String, dynamic>? product = v['p'] as Map<String, dynamic>?;
        if (product != null) {
          _hits.putIfAbsent(e.key, () => _fromSaved(product));
        } else {
          _misses.putIfAbsent(e.key, () => DateTime.fromMillisecondsSinceEpoch(v['t'] as int));
        }
      }
    } catch (_) {
      // No storage (tests) or an old format: start empty.
    }
  }

  static Future<void> _persist() async {
    try {
      final Map<String, dynamic> out = <String, dynamic>{
        for (final MapEntry<String, Product> e in _hits.entries.toList().reversed.take(_maxSaved))
          e.key: <String, dynamic>{'p': _toSaved(e.value)},
        for (final MapEntry<String, DateTime> e in _misses.entries.toList().reversed.take(_maxSaved))
          e.key: <String, dynamic>{'t': e.value.millisecondsSinceEpoch},
      };
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(out));
    } catch (_) {
      // Kept for this session only.
    }
  }

  /// Only the fields [_build] sets, so a saved product rebuilds identically.
  static Map<String, dynamic> _toSaved(final Product p) => <String, dynamic>{
    'code': p.barcode,
    'name': p.productName,
    'brand': p.brands,
    'quantity': p.quantity,
    'category': p.categories,
    'image': p.imageFrontUrl,
    'source': sourceOf(p)?.name,
  };

  static Product _fromSaved(final Map<String, dynamic> j) => _build(
    barcode: j['code'] as String,
    name: j['name'] as String,
    brand: j['brand'] as String?,
    quantity: j['quantity'] as String?,
    category: j['category'] as String?,
    imageUrl: j['image'] as String?,
    source: ExternalProductSource.values.firstWhere(
      (ExternalProductSource s) => s.name == j['source'],
      orElse: () => ExternalProductSource.upcItemDb,
    ),
  );

  @visibleForTesting
  static void resetForTest() {
    _hits.clear();
    _misses.clear();
    _restoring = null;
  }

  /// The source of a product built by this class, or null for OFF products.
  static ExternalProductSource? sourceOf(final Product product) {
    final String? creator = product.creator;
    if (creator == null || !creator.startsWith(creatorPrefix)) {
      return null;
    }
    final String name = creator.substring(creatorPrefix.length);
    for (final ExternalProductSource s in ExternalProductSource.values) {
      if (s.name == name) {
        return s;
      }
    }
    return null;
  }

  Future<Product?> lookup(final String barcode) async {
    if (Gs1Code.isInStoreCode(barcode)) {
      return null;
    }
    await (_restoring ??= _restore());
    final DateTime? missed = _misses[barcode];
    if (missed != null && DateTime.now().difference(missed) < missTtl) {
      return null;
    }
    if (_hits.containsKey(barcode)) {
      return _hits[barcode];
    }
    Product? product;
    try {
      product = Gs1Code.isBook(barcode)
          ? await _openLibrary(barcode)
          : await _upcItemDb(barcode);
    } catch (_) {
      // Offline, rate limited or a changed API: same as not found.
      return null;
    }
    if (product == null) {
      _misses[barcode] = DateTime.now();
    } else {
      _misses.remove(barcode);
      _hits[barcode] = product;
    }
    await _persist();
    return product;
  }

  Future<Product?> _upcItemDb(final String barcode) async {
    final Uri uri = Uri.parse(
      'https://api.upcitemdb.com/prod/trial/lookup',
    ).replace(queryParameters: <String, String>{'upc': barcode});
    final http.Response response = await _client.get(uri).timeout(timeout);
    _checkStatus(response);
    if (response.statusCode != 200) {
      return null;
    }
    final Map<String, dynamic> json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final List<dynamic> items = json['items'] as List<dynamic>? ?? const <dynamic>[];
    if (items.isEmpty || items.first is! Map<String, dynamic>) {
      return null;
    }
    final Map<String, dynamic> item = items.first as Map<String, dynamic>;
    final String? title = _clean(item['title']);
    if (title == null) {
      return null;
    }
    final List<dynamic> images = item['images'] as List<dynamic>? ?? const <dynamic>[];
    return _build(
      barcode: barcode,
      name: title,
      brand: _clean(item['brand']),
      imageUrl: images.whereType<String>().where((String u) => u.startsWith('https://')).firstOrNull,
      category: _clean(item['category']),
      quantity: _clean(item['size']),
      source: ExternalProductSource.upcItemDb,
    );
  }

  Future<Product?> _openLibrary(final String isbn) async {
    final Uri uri = Uri.parse('https://openlibrary.org/isbn/$isbn.json');
    final http.Response response = await _client.get(uri).timeout(timeout);
    _checkStatus(response);
    if (response.statusCode != 200) {
      return null;
    }
    final Map<String, dynamic> json =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final String? title = _clean(json['title']);
    if (title == null) {
      return null;
    }
    final List<dynamic> publishers = json['publishers'] as List<dynamic>? ?? const <dynamic>[];
    final List<dynamic> covers = json['covers'] as List<dynamic>? ?? const <dynamic>[];
    final int? cover = covers.whereType<int>().where((int c) => c > 0).firstOrNull;
    return _build(
      barcode: isbn,
      name: title,
      brand: publishers.whereType<String>().map(_clean).nonNulls.firstOrNull,
      imageUrl: cover == null ? null : 'https://covers.openlibrary.org/b/id/$cover-M.jpg',
      category: 'Books',
      source: ExternalProductSource.openLibrary,
    );
  }

  /// Rate limits and server errors are not "not found": they must not be
  /// remembered as misses.
  static void _checkStatus(final http.Response response) {
    if (response.statusCode == 429 || response.statusCode >= 500) {
      throw http.ClientException('HTTP ${response.statusCode}', response.request?.url);
    }
  }

  static Product _build({
    required final String barcode,
    required final String name,
    required final String? brand,
    required final ExternalProductSource source,
    final String? imageUrl,
    final String? category,
    final String? quantity,
  }) => Product(
    barcode: barcode,
    productName: name,
    brands: brand,
    quantity: quantity,
    categories: category,
  )
    // Not food: no Nutri-Score refresh, no OFF knowledge panels to fetch.
    ..productType = ProductType.product
    ..imageFrontUrl = imageUrl
    ..creator = '$creatorPrefix${source.name}'
    ..website = '${source.pageUrl}$barcode'
    ..statesTags = const <String>['en:owned-external-source'];

  static String? _clean(final dynamic value) {
    if (value is! String) {
      return null;
    }
    final String s = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s.isEmpty ? null : s;
  }
}
