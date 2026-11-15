import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:smooth_app/services/ownership_service_config.dart';

/// Where a `brand_owner` row came from, in order of trust.
/// [user] is a correction made on this phone and never leaves it.
enum BrandOwnerSource { wikidata, aiFallback, manualCurated, offlineDb, label, user }

class BrandOwnerResult {
  BrandOwnerResult({
    required this.ownerCompany,
    required this.ownerChain,
    required this.source,
    this.controlledBy,
  });

  final String ownerCompany;

  /// Full chain from brand to ultimate parent, e.g. `['Oreo', 'Nabisco',
  /// 'Mondelez International']`.
  final List<String> ownerChain;
  final BrandOwnerSource source;

  /// Person or family that controls [ownerCompany], when known.
  final String? controlledBy;

  /// Names to match against the ethics data after the owner itself.
  List<String> get ethicsChain => <String>[?controlledBy, ...ownerChain];
}

class EthicsRating {
  EthicsRating({required this.category, required this.rationale, this.sourceUrl});

  final String category;
  final String rationale;
  final String? sourceUrl;
}

/// Result of step 2 in the fallback chain (BRIEF.md): a vision guess at the
/// brand printed on a photographed package, with the model's own confidence.
class BrandGuess {
  BrandGuess({required this.brandName, required this.confidence});

  final String brandName;

  /// 0.0-1.0, as self-reported by the model. Show this to the user as "I
  /// think it's X — correct?" rather than trusting it blindly.
  final double confidence;
}

class _WikidataOwner {
  _WikidataOwner({required this.qid, required this.label});

  final String qid;
  final String label;
}

class _WikidataHit {
  _WikidataHit({required this.qid, required this.label, required this.isCompany});

  final String qid;
  final String? label;

  /// The description says it is a company, not only a brand.
  final bool isCompany;
}

/// Looks up who actually owns a brand, plus a curated ethics rating.
///
/// Read path always hits the central cache first (Supabase/PostgREST) so a
/// confirmed lookup is shared across every user instead of re-running the
/// Wikidata/AI fallback per device. See `projects/ejerskab-app/BRIEF.md` for
/// the full fallback chain and why the cache is central, not local-only.
class OwnershipService {
  OwnershipService({
    this.supabaseUrl = OwnershipServiceConfig.supabaseUrl,
    this.supabaseAnonKey = OwnershipServiceConfig.supabaseAnonKey,
    this.anthropicApiKey = OwnershipServiceConfig.anthropicApiKey,
    this.wikidataContact = OwnershipServiceConfig.wikidataContact,
    final http.Client? client,
  }) : client = client ?? http.Client(),
       _sharedCache = client == null;

  /// Wikidata answers of this app session by brand, shared by all instances
  /// that use the real network (the scan card and the product page ask for
  /// the same brand within seconds). Tests inject a client and skip it.
  static final Map<String, Future<BrandOwnerResult?>> _wikidataCache = <String, Future<BrandOwnerResult?>>{};
  final bool _sharedCache;

  final String supabaseUrl;
  final String supabaseAnonKey;
  final String anthropicApiKey;
  final String wikidataContact;

  /// Injectable so tests can swap in `http.testing.MockClient` instead of
  /// hitting the real network.
  final http.Client client;

  static const String _anthropicUrl = 'https://api.anthropic.com/v1/messages';
  static const String _model = 'claude-opus-5-5';
  static const String _wikidataSearchUrl =
      'https://www.wikidata.org/w/api.php';
  static const String _wikidataSparqlUrl = 'https://query.wikidata.org/sparql';

  /// Safety limit on how many parent-company hops to walk (cycle guard
  /// handles the normal case; this bounds pathological data).
  static const int _maxOwnershipDepth = 5;

  /// Wikidata's query service can stall; the next fallback is better than a spinner.
  static const Duration _wikidataTimeout = Duration(seconds: 8);

  /// The shared cache is a shortcut; a slow one must not hold up the answer.
  static const Duration _cacheTimeout = Duration(seconds: 5);

  /// The AI lookup is the slowest step; past this the user types the brand.
  static const Duration _aiTimeout = Duration(seconds: 30);

  Map<String, String> get _supabaseHeaders => <String, String>{
    'apikey': supabaseAnonKey,
    'Authorization': 'Bearer $supabaseAnonKey',
    'Content-Type': 'application/json',
  };

  Map<String, String> get _wikidataHeaders => <String, String>{
    'User-Agent': 'owned-app/0.1 (contact: $wikidataContact)',
    'Accept': 'application/json',
  };

  Map<String, String> get _anthropicHeaders => <String, String>{
    'content-type': 'application/json',
    'x-api-key': anthropicApiKey,
    'anthropic-version': '2023-06-01',
    // Re-routes a policy-declined request to a fallback model server-side
    // instead of surfacing a refusal — see claude-api skill, Opus 5.5.
    'anthropic-beta': 'server-side-fallback-2026-07-01',
  };

  // ---------------------------------------------------------------------
  // Step 1: central cache (fast path, shared across all users).
  // ---------------------------------------------------------------------

  /// A row with a matching [countryCode] wins over the global
  /// (`country_code IS NULL`) row.
  Future<BrandOwnerResult?> getCachedOwner(
    final String brandName, {
    final String? countryCode,
  }) async {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      return null;
    }
    final Uri uri = Uri.parse(
      '$supabaseUrl/rest/v1/brand_owner'
      '?brand_name=eq.${Uri.encodeComponent(brandName)}'
      '&order=country_code.desc.nullslast'
      '&limit=1',
    );
    try {
      final http.Response response = await client.get(uri, headers: _supabaseHeaders).timeout(_cacheTimeout);
      if (response.statusCode != 200) {
        return null;
      }
      final List<dynamic> rows = jsonDecode(response.body) as List<dynamic>;
      if (rows.isEmpty) {
        return null;
      }
      final Map<String, dynamic> row = rows.first as Map<String, dynamic>;
      return BrandOwnerResult(
        ownerCompany: row['owner_company'] as String,
        // `owner_chain` is a Postgres jsonb column — PostgREST already hands
        // it back as a decoded JSON array, not a string to re-decode.
        ownerChain: (row['owner_chain'] as List<dynamic>).cast<String>(),
        source: BrandOwnerSource.values.byName(row['source'] as String),
      );
    } catch (_) {
      // Offline or a bad row: the next step of the chain answers instead.
      return null;
    }
  }

  /// Writes a confirmed result back to the central cache so the next user
  /// who scans the same brand hits step 1 instead of re-running Wikidata or
  /// the AI fallback. RLS only accepts `wikidata`/`aiFallback` rows from the
  /// client — `manualCurated` is set by Frej directly, never from here.
  Future<void> pushToCentralCache(
    final String brandName,
    final BrandOwnerResult result, {
    final String? countryCode,
  }) async {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      return;
    }
    final Uri uri = Uri.parse('$supabaseUrl/rest/v1/brand_owner');
    try {
      await client
          .post(
            uri,
            headers: <String, String>{
              ..._supabaseHeaders,
              'Prefer': 'resolution=merge-duplicates',
            },
            body: jsonEncode(<String, Object?>{
              'brand_name': brandName,
              'country_code': countryCode,
              'owner_company': result.ownerCompany,
              // Pass the list as-is — it's a jsonb column, PostgREST serializes
              // this into a real JSON array in the request body.
              'owner_chain': result.ownerChain,
              'source': result.source.name,
            }),
          )
          .timeout(_cacheTimeout);
    } catch (_) {
      // Sharing the answer is a bonus; the user already has it.
    }
  }

  /// Ethics rating is curated by hand only (see `ethics_rating` table) —
  /// this service never writes one. Read-only on purpose.
  Future<EthicsRating?> getEthicsRating(final String ownerCompany) async {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      return null;
    }
    final Uri uri = Uri.parse(
      '$supabaseUrl/rest/v1/ethics_rating'
      '?owner_company=eq.${Uri.encodeComponent(ownerCompany)}'
      '&limit=1',
    );
    try {
      final http.Response response = await client.get(uri, headers: _supabaseHeaders).timeout(_cacheTimeout);
      if (response.statusCode != 200) {
        return null;
      }
      final List<dynamic> rows = jsonDecode(response.body) as List<dynamic>;
      if (rows.isEmpty) {
        return null;
      }
      final Map<String, dynamic> row = rows.first as Map<String, dynamic>;
      return EthicsRating(
        category: row['category'] as String,
        rationale: row['rationale_text'] as String,
        sourceUrl: row['source_url'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // Step 2: Wikidata, walked up the parent chain.
  // ---------------------------------------------------------------------

  /// Descriptions that mark a search hit as a brand or a company, so
  /// "Apple" finds Apple Inc., not the fruit.
  static final RegExp _brandLike = RegExp(
    r'\b(brand|company|corporation|manufacturer|maker|producer|retailer|'
    r'supermarket|conglomerate|multinational|business|enterprise|firm|'
    r'publisher|publishing|chain|group|brewery|distillery|dairy|'
    r'cooperative|trademark|holding)\b',
    caseSensitive: false,
  );

  /// The same, minus "brand"/"trademark": a hit that is itself a company
  /// owns its products when nobody owns it.
  static final RegExp _companyLike = RegExp(
    r'\b(company|corporation|manufacturer|maker|producer|retailer|'
    r'supermarket|conglomerate|multinational|business|enterprise|firm|'
    r'publisher|publishing house|chain|group|brewery|distillery|dairy|'
    r'cooperative|holding)\b',
    caseSensitive: false,
  );

  /// Shareholders listed as "owned by" on public companies. They own
  /// slices of everything, so the walk stops before them.
  static final RegExp _assetManager = RegExp(
    r'vanguard|blackrock|state street|capital group|fidelity|norges bank|'
    r'invesco|geode|northern trust|amundi|schwab|wellington management',
    caseSensitive: false,
  );

  static final RegExp _bareQid = RegExp(r'^Q\d+$');

  /// Brand → company that owns it, following parent organisation (P749),
  /// owned by (P127), brand of (P1716) and manufacturer (P176) up to a
  /// listed company or one nobody owns. Same order as the offline database
  /// (research/prefix/build_db.py).
  Future<BrandOwnerResult?> lookupWikidata(final String brandName) {
    if (!_sharedCache) {
      return _lookupWikidata(brandName);
    }
    final String key = brandName.trim().toLowerCase();
    return _wikidataCache.putIfAbsent(key, () {
      final Future<BrandOwnerResult?> f = _lookupWikidata(brandName);
      // A miss may be a network hiccup: ask again next time.
      unawaited(f.then((BrandOwnerResult? r) => r == null ? _wikidataCache.remove(key) : null));
      return f;
    });
  }

  Future<BrandOwnerResult?> _lookupWikidata(final String brandName) async {
    try {
      final _WikidataHit? start = await _searchWikidataEntity(brandName);
      if (start == null) {
        return null;
      }

      final List<String> chain = <String>[brandName];
      final Set<String> visited = <String>{start.qid};
      String currentQid = start.qid;

      for (int depth = 0; depth < _maxOwnershipDepth; depth++) {
        final _WikidataOwner? owner = await _getOwnedBy(currentQid);
        if (owner == null || visited.contains(owner.qid)) {
          break;
        }
        chain.add(owner.label);
        visited.add(owner.qid);
        currentQid = owner.qid;
      }

      if (chain.length < 2) {
        // Nobody owns it: fine when the hit is a company itself
        // (Apple Inc. owns Apple), not when it is only a brand.
        if (!start.isCompany) {
          return null;
        }
        final String company = start.label ?? brandName;
        if (company.toLowerCase() != brandName.toLowerCase()) {
          chain.add(company);
        }
        return BrandOwnerResult(
          ownerCompany: company,
          ownerChain: chain,
          source: BrandOwnerSource.wikidata,
        );
      }

      return BrandOwnerResult(
        ownerCompany: chain.last,
        ownerChain: chain,
        source: BrandOwnerSource.wikidata,
      );
    } catch (_) {
      // Never let a network hiccup block the fallback chain.
      return null;
    }
  }

  Future<_WikidataHit?> _searchWikidataEntity(final String label) async {
    final Uri uri = Uri.parse(_wikidataSearchUrl).replace(
      queryParameters: <String, String>{
        'action': 'wbsearchentities',
        'search': label,
        'language': 'en',
        'uselang': 'en',
        'format': 'json',
        'type': 'item',
        'limit': '7',
      },
    );
    final http.Response response = await client
        .get(uri, headers: _wikidataHeaders)
        .timeout(_wikidataTimeout);
    if (response.statusCode != 200) {
      return null;
    }
    final Map<String, dynamic> body =
        jsonDecode(response.body) as Map<String, dynamic>;
    final List<Map<String, dynamic>> hits =
        ((body['search'] as List<dynamic>?) ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .where((Map<String, dynamic> h) => h['id'] is String)
            .toList();
    if (hits.isEmpty) {
      return null;
    }
    _WikidataHit hit(final Map<String, dynamic> h) => _WikidataHit(
      qid: h['id'] as String,
      label: h['label'] as String?,
      isCompany: _companyLike.hasMatch(h['description'] as String? ?? ''),
    );

    // Without any descriptions there is nothing to choose on: trust the
    // top hit. Otherwise only a brand- or company-like one will do.
    if (hits.every((Map<String, dynamic> h) => h['description'] == null)) {
      return hit(hits.first);
    }
    for (final Map<String, dynamic> h in hits) {
      if (_brandLike.hasMatch(h['description'] as String? ?? '')) {
        return hit(h);
      }
    }
    return null;
  }

  Future<_WikidataOwner?> _getOwnedBy(final String qid) async {
    // People and families as owners end the walk: the company they own is
    // the answer. A listed company is the top as well.
    final String query =
        'SELECT ?owner ?ownerLabel ?listed WHERE { '
        'OPTIONAL { wd:$qid wdt:P414 ?listed . } '
        'OPTIONAL { '
        '{ wd:$qid wdt:P749 ?owner . BIND(1 AS ?rank) } UNION '
        '{ wd:$qid wdt:P127 ?owner . BIND(2 AS ?rank) } UNION '
        '{ wd:$qid wdt:P1716 ?owner . BIND(3 AS ?rank) } UNION '
        '{ wd:$qid wdt:P176 ?owner . BIND(4 AS ?rank) } '
        'FILTER NOT EXISTS { ?owner wdt:P31 ?ownerType . '
        'VALUES ?ownerType { wd:Q5 wd:Q8436 } } '
        '} '
        'SERVICE wikibase:label { bd:serviceParam wikibase:language "en". } '
        '} ORDER BY ?rank LIMIT 1';
    final Uri uri = Uri.parse(_wikidataSparqlUrl).replace(
      queryParameters: <String, String>{'query': query, 'format': 'json'},
    );
    final http.Response response = await client
        .get(uri, headers: _wikidataHeaders)
        .timeout(_wikidataTimeout);
    if (response.statusCode != 200) {
      return null;
    }
    final Map<String, dynamic> body =
        jsonDecode(response.body) as Map<String, dynamic>;
    final List<dynamic> bindings =
        ((body['results'] as Map<String, dynamic>?)?['bindings']
                as List<dynamic>?) ??
        const <dynamic>[];
    if (bindings.isEmpty) {
      return null;
    }
    final Map<String, dynamic> binding = bindings.first as Map<String, dynamic>;
    if (binding['listed'] != null || binding['owner'] == null) {
      return null;
    }
    final String ownerUri =
        (binding['owner'] as Map<String, dynamic>)['value'] as String;
    final String ownerQid = ownerUri.split('/').last;
    final String ownerLabel =
        (binding['ownerLabel'] as Map<String, dynamic>?)?['value'] as String? ??
        ownerQid;
    // An unlabelled item comes back as its own Q-number: useless to show.
    if (_bareQid.hasMatch(ownerLabel) || _assetManager.hasMatch(ownerLabel)) {
      return null;
    }
    return _WikidataOwner(qid: ownerQid, label: ownerLabel);
  }

  // ---------------------------------------------------------------------
  // Step 3: AI fallback — only called with a brand name the user already
  // confirmed, never on a raw, unconfirmed vision guess.
  // ---------------------------------------------------------------------

  Future<BrandOwnerResult?> lookupAiFallback(final String brandName) async {
    if (anthropicApiKey.isEmpty) {
      return null;
    }
    try {
      final String prompt =
          'You are a fact-checking assistant for a consumer app that shows '
          'who owns a product brand.\n\n'
          'Brand: "$brandName"\n\n'
          'Only state an ownership chain you are highly confident is public, '
          "documented fact (e.g. from the company's own investor filings, "
          'press releases, or well-established reporting). Never guess or '
          'infer from naming similarity alone.\n\n'
          'Respond with ONLY a JSON object, no other text:\n'
          '- If you know the chain: {"known": true, "chain": ["$brandName", '
          '"...", "Ultimate Parent Company"], "note": "short source '
          'description"}\n'
          '- If you are not confident: {"known": false}';

      final http.Response response = await client.post(
        Uri.parse(_anthropicUrl),
        headers: _anthropicHeaders,
        body: jsonEncode(<String, Object?>{
          'model': _model,
          'max_tokens': 1024,
          'output_config': <String, String>{'effort': 'low'},
          'fallbacks': 'default',
          'messages': <Map<String, Object?>>[
            <String, Object?>{'role': 'user', 'content': prompt},
          ],
        }),
      ).timeout(_aiTimeout);
      if (response.statusCode != 200) {
        return null;
      }
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      if (body['stop_reason'] == 'refusal') {
        return null;
      }
      final String? text = _firstTextBlock(body);
      if (text == null) {
        return null;
      }
      final Map<String, dynamic> parsed =
          jsonDecode(_stripCodeFence(text)) as Map<String, dynamic>;
      if (parsed['known'] != true) {
        return null;
      }
      final List<String> chain = (parsed['chain'] as List<dynamic>).cast<String>();
      if (chain.length < 2) {
        return null;
      }
      return BrandOwnerResult(
        ownerCompany: chain.last,
        ownerChain: chain,
        source: BrandOwnerSource.aiFallback,
      );
    } catch (_) {
      return null;
    }
  }

  /// Step 0.5 of the BRIEF.md fallback chain: guesses the brand/product from
  /// a photo when the barcode is unknown, so the user can confirm it before
  /// any ownership lookup runs on it.
  Future<BrandGuess?> guessBrandFromImage(
    final Uint8List imageBytes, {
    final String mediaType = 'image/jpeg',
  }) async {
    if (anthropicApiKey.isEmpty) {
      return null;
    }
    try {
      const String prompt =
          'Look at this photo of a product package. Identify the brand name '
          'printed on it.\n\n'
          'Respond with ONLY a JSON object, no other text:\n'
          '{"brand": "<brand name as printed>", "confidence": <0.0-1.0>}\n\n'
          'If you cannot read a brand name at all, respond '
          '{"brand": null, "confidence": 0.0}.';

      final http.Response response = await client.post(
        Uri.parse(_anthropicUrl),
        headers: _anthropicHeaders,
        body: jsonEncode(<String, Object?>{
          'model': _model,
          'max_tokens': 256,
          'output_config': <String, String>{'effort': 'low'},
          'fallbacks': 'default',
          'messages': <Map<String, Object?>>[
            <String, Object?>{
              'role': 'user',
              'content': <Map<String, Object?>>[
                <String, Object?>{
                  'type': 'image',
                  'source': <String, Object?>{
                    'type': 'base64',
                    'media_type': mediaType,
                    'data': base64Encode(imageBytes),
                  },
                },
                <String, Object?>{'type': 'text', 'text': prompt},
              ],
            },
          ],
        }),
      ).timeout(_aiTimeout);
      if (response.statusCode != 200) {
        return null;
      }
      final Map<String, dynamic> body =
          jsonDecode(response.body) as Map<String, dynamic>;
      if (body['stop_reason'] == 'refusal') {
        return null;
      }
      final String? text = _firstTextBlock(body);
      if (text == null) {
        return null;
      }
      final Map<String, dynamic> parsed =
          jsonDecode(_stripCodeFence(text)) as Map<String, dynamic>;
      final String? brand = parsed['brand'] as String?;
      if (brand == null || brand.isEmpty) {
        return null;
      }
      final double confidence = (parsed['confidence'] as num?)?.toDouble() ?? 0.0;
      return BrandGuess(brandName: brand, confidence: confidence);
    } catch (_) {
      return null;
    }
  }

  String? _firstTextBlock(final Map<String, dynamic> responseBody) {
    final List<dynamic>? content = responseBody['content'] as List<dynamic>?;
    if (content == null) {
      return null;
    }
    for (final dynamic block in content) {
      final Map<String, dynamic> map = block as Map<String, dynamic>;
      if (map['type'] == 'text') {
        return map['text'] as String?;
      }
    }
    return null;
  }

  /// Claude sometimes wraps JSON in a ```json fence despite instructions.
  String _stripCodeFence(final String text) {
    final String trimmed = text.trim();
    if (!trimmed.startsWith('```')) {
      return trimmed;
    }
    final List<String> lines = trimmed.split('\n');
    return lines.sublist(1, lines.length - 1).join('\n');
  }
}
