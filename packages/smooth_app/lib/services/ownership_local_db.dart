import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:smooth_app/services/owner_overrides.dart';
import 'package:smooth_app/services/ownership_norm.dart';

/// Where an offline answer came from, strongest first.
enum LocalOwnerSource {
  /// Corrected by the user on this phone (OwnerOverrides).
  user,
  storeBrandList,
  wikidata,
  companyName,
  aiResearch,
  wikipedia,
  /// Brand field is itself a legal company name ("Foo S.L.") = the company owns it.
  labelCompany,
  barcodePrefix,
  healthMark,
  healthMarkProducer,
  other,
}

class LocalOwnerResult {
  const LocalOwnerResult({
    required this.owner,
    required this.source,
    this.chain = const <String>[],
    this.sourceUrl,
    this.controlledBy,
  });

  final String owner;
  final LocalOwnerSource source;
  final List<String> chain;
  final String? sourceUrl;

  /// Person or family in control of [owner] ("Lactalis" -> "Emmanuel Besnier").
  final String? controlledBy;

  /// Names to match against the ethics data after the owner itself: the
  /// chain, and last the controlling family ("famille Gervoson" -> Andros).
  List<String> get ethicsChain => <String>[?controlledBy, ...chain];
}

/// Offline ownership database built by research/prefix/export_app_db.py
/// (Wikidata, verified store-brand lists, AI research with sources,
/// barcode prefixes, EU health/identification marks). No network, no cost.
class OwnershipLocalDb {
  OwnershipLocalDb._(this._db);

  static const String assetPath = 'assets/ownership/ownership_db.json.gz';
  static Future<OwnershipLocalDb>? _instance;

  final Map<String, dynamic> _db;

  /// Loads the bundled database once; decoding runs off the UI isolate.
  static Future<OwnershipLocalDb> load() =>
      _instance ??= rootBundle.load(assetPath).then(
        (ByteData data) => compute(_decode, data.buffer.asUint8List()),
      ).then(OwnershipLocalDb._);

  @visibleForTesting
  static OwnershipLocalDb fromJson(final Map<String, dynamic> json) => OwnershipLocalDb._(json);

  static Map<String, dynamic> _decode(final Uint8List bytes) =>
      jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;

  List<dynamic> get _strings => _db['strings'] as List<dynamic>;

  /// When research/prefix/export_app_db.py built this data (ISO date).
  String? get built => _db['built'] as String?;

  /// Brands with a known owner, store brands included.
  int get brandCount =>
      (_db['brands'] as Map<String, dynamic>).length + (_db['by_country'] as Map<String, dynamic>).length;

  String _s(final dynamic i) => _strings[i as int] as String;

  static const Map<String, LocalOwnerSource> _codes = <String, LocalOwnerSource>{
    's': LocalOwnerSource.storeBrandList,
    'w': LocalOwnerSource.wikidata,
    'n': LocalOwnerSource.companyName,
    'a': LocalOwnerSource.aiResearch,
    'p': LocalOwnerSource.wikipedia,
    'l': LocalOwnerSource.labelCompany,
    'h': LocalOwnerSource.healthMark,
    'm': LocalOwnerSource.healthMarkProducer,
  };

  LocalOwnerResult _entry(final List<dynamic> e) => LocalOwnerResult(
        owner: _s(e[0]),
        source: _codes[e[1]] ?? LocalOwnerSource.other,
        chain: e.length > 2 ? (e[2] as List<dynamic>).map(_s).toList() : const <String>[],
        sourceUrl: e.length > 3 && (e[3] as String).isNotEmpty ? e[3] as String : null,
        controlledBy: e.length > 4 ? _s(e[4]) : null,
      );

  /// The user's own correction first, then the same resolution order as
  /// research/prefix/predict.py.
  LocalOwnerResult? lookup({
    required final String barcode,
    final String? brands,
    final List<String> countryTags = const <String>[],
    final List<String> embCodeTags = const <String>[],
  }) {
    final String? corrected = OwnerOverrides.instance.ownerFor(barcode: barcode, brands: brands);
    if (corrected != null) {
      // "Nestlé Suisse" -> Nestlé: follow a named subsidiary up to its owner.
      final String? parent = ownerOfCompany(corrected);
      if (parent != null && OwnershipNorm.normCore(parent) != OwnershipNorm.normCore(corrected)) {
        return LocalOwnerResult(owner: parent, source: LocalOwnerSource.user, chain: <String>[corrected, parent]);
      }
      return LocalOwnerResult(owner: corrected, source: LocalOwnerSource.user);
    }
    final LocalOwnerResult? byBrand = _byBrands(brands, countryTags);
    if (byBrand != null) {
      return byBrand;
    }
    final String? company = legalCompanyName(brands);
    if (company != null) {
      // "Jordans & Ryvita Company Limited - A Division of ABF ..." may itself
      // be a known company with a parent.
      final String? parent = ownerOfCompany(company);
      return LocalOwnerResult(
        owner: parent ?? company,
        source: LocalOwnerSource.labelCompany,
        chain: <String>[company, if (parent != null && parent != company) parent],
      );
    }
    final LocalOwnerResult? byHead = _byCompanyHead(brands, countryTags);
    if (byHead != null) {
      return byHead;
    }
    final String? prefixOwner = _byPrefix(barcode);
    if (prefixOwner != null) {
      return LocalOwnerResult(owner: prefixOwner, source: LocalOwnerSource.barcodePrefix);
    }
    final Map<String, dynamic> emb = _db['emb'] as Map<String, dynamic>;
    for (final String tag in embCodeTags) {
      for (final String key in embKeys(tag)) {
        final List<dynamic>? e = emb[key] as List<dynamic>?;
        if (e != null) {
          return _entry(e);
        }
      }
    }
    return null;
  }

  LocalOwnerResult? _byBrands(final String? brands, final List<String> countryTags) {
    final Map<String, dynamic> byBrand = _db['brands'] as Map<String, dynamic>;
    final Map<String, dynamic> byCountry = _db['by_country'] as Map<String, dynamic>;
    LocalOwnerResult? best;
    bool bestIsSelf = false;
    for (final String raw in OwnershipNorm.splitBrands(brands)) {
      final String norm = OwnershipNorm.normCore(raw);
      if (OwnershipNorm.stopBrands.contains(norm)) {
        continue;
      }
      final String key = variantKey(norm) ?? norm;
      List<dynamic>? e;
      final Map<String, dynamic>? perCountry = byCountry[key] as Map<String, dynamic>?;
      if (perCountry != null) {
        for (final String c in countryTags) {
          e = perCountry[c] as List<dynamic>?;
          if (e != null) {
            break;
          }
        }
      }
      e ??= byBrand[key] as List<dynamic>?;
      if (e == null) {
        continue;
      }
      final LocalOwnerResult r = _entry(e);
      // "MAIZENA, Unilever": a brand that is its own owner loses to another
      // brand on the pack that names a known group.
      final bool self = r.chain.length <= 1 && OwnershipNorm.normCore(r.owner) == key && !_isGroup(r.owner);
      if (best == null ||
          r.source.index < best.source.index && (bestIsSelf || !self) ||
          bestIsSelf && !self && _isGroup(r.owner)) {
        best = r;
        bestIsSelf = self;
      }
    }
    return best;
  }

  /// Trailing words that make a brand field a local company name:
  /// "L'OREAL NORGE AS", "Mondelez Danmark ApS", "Unilever Nordic".
  static const Set<String> _companyTail = <String>{
    'as', 'asa', 'ab', 'a s', 'aps', 'amba', 'gmbh', 'ag', 'kg', 'co', 'inc', 'llc', 'ltd', 'plc', 'sa', 'sas',
    'srl', 'spa', 'bv', 'nv', 'oy', 'oyj', 'norge', 'norway', 'danmark', 'denmark', 'sverige', 'sweden',
    'suomi', 'finland', 'deutschland', 'germany', 'france', 'espana', 'italia', 'italy', 'uk', 'nederland',
    'belgium', 'belgique', 'polska', 'austria', 'osterreich', 'schweiz', 'suisse', 'nordic', 'nordics',
    'scandinavia', 'europe', 'international', 'group', 'and',
  };

  /// "L'OREAL NORGE AS" -> the brand "L'Oreal", when that brand is known.
  LocalOwnerResult? _byCompanyHead(final String? brands, final List<String> countryTags) {
    for (final String raw in OwnershipNorm.splitBrands(brands)) {
      final List<String> words = OwnershipNorm.normCore(raw).split(' ');
      int end = words.length;
      while (end > 1 && _companyTail.contains(words[end - 1])) {
        end--;
      }
      if (end == words.length) {
        continue;
      }
      final String head = words.sublist(0, end).join(' ');
      if (head.length < 4 || OwnershipNorm.stopBrands.contains(head)) {
        continue;
      }
      final LocalOwnerResult? r = _byBrands(head, countryTags);
      if (r != null) {
        return LocalOwnerResult(
          owner: r.owner,
          source: LocalOwnerSource.companyName,
          chain: <String>[raw.trim(), ...r.chain.where((String c) => c != raw.trim())],
          controlledBy: r.controlledBy,
        );
      }
    }
    return null;
  }

  Set<String>? _groupOwners;

  /// Owners with a ranked brand list: the big groups ("Unilever", "Nestlé").
  bool _isGroup(final String owner) {
    _groupOwners ??= <String>{
      for (final String k in ((_db['top'] as Map<String, dynamic>?) ?? const <String, dynamic>{}).keys)
        OwnershipNorm.normCore(_s(int.parse(k))),
    };
    return _groupOwners!.contains(OwnershipNorm.normCore(owner));
  }

  String? _byPrefix(final String code) {
    final Map<String, dynamic> prefix = _db['prefix'] as Map<String, dynamic>;
    final List<String> keys = <String>[];
    if (code.length == 13 && !code.startsWith('2')) {
      for (int k = 10; k >= 7; k--) {
        keys.add(code.substring(0, k));
      }
    } else if (code.length == 8) {
      for (int k = 6; k >= 3; k--) {
        keys.add('8:${code.substring(0, k)}');
      }
    }
    for (final String k in keys) {
      final dynamic i = prefix[k];
      if (i != null) {
        return _s(i);
      }
    }
    return null;
  }

  Map<String, List<String>>? _topByOwner;

  /// The owner's most scanned brands in the EU ("Nestlé also owns ..."),
  /// from research/prefix/add_top_brands.py. Empty when unknown.
  List<String> topBrandsOf(final String owner) {
    _topByOwner ??= <String, List<String>>{
      for (final MapEntry<String, dynamic> e
          in ((_db['top'] as Map<String, dynamic>?) ?? const <String, dynamic>{}).entries)
        OwnershipNorm.normCore(_s(int.parse(e.key))): (e.value as List<dynamic>).cast<String>(),
    };
    return _topByOwner![OwnershipNorm.normCore(owner)] ?? const <String>[];
  }

  /// Owners with a ranked brand list (the big groups), as stored.
  List<String> get topOwners => <String>[
    for (final String k in ((_db['top'] as Map<String, dynamic>?) ?? const <String, dynamic>{}).keys)
      _s(int.parse(k)),
  ];

  /// A brand with this [OwnershipNorm.normCore] key is in the data, in the
  /// brand table or as a per-country (store) brand, or under a known
  /// spelling variant ([variantKey]). Used to answer "who owns <typed
  /// text>?" only when the text really is a brand.
  bool knowsBrand(final String key) {
    if (key.isEmpty) {
      return false;
    }
    final Map<String, dynamic> brands = _db['brands'] as Map<String, dynamic>;
    final Map<String, dynamic> byCountry = _db['by_country'] as Map<String, dynamic>;
    return brands.containsKey(key) || byCountry.containsKey(key) || variantKey(key) != null;
  }

  /// The brand table has this [OwnershipNorm.normCore] key.
  bool hasBrandKey(final String key) => (_db['brands'] as Map<String, dynamic>).containsKey(key);

  Map<String, String>? _noSpace;

  static final List<(RegExp, String)> _swaps = <(RegExp, String)>[
    (RegExp(r'\b(et|und|e|y|en|og|och|i)\b'), 'and'),
    (RegExp(r'\band\b'), 'et'),
    (RegExp(r'\bst\b'), 'saint'),
    (RegExp(r'\bste\b'), 'sainte'),
    (RegExp(r'\bsaint\b'), 'st'),
    (RegExp(r'\bsainte\b'), 'ste'),
  ];

  /// A known brand key for a spelling the table does not have: "elle et
  /// vire" -> "elle and vire", "isigny ste mere" -> "isigny sainte mere",
  /// "fuzetea" -> "fuze tea" (7+ letters, one candidate only). Null when
  /// [key] is known as it is, or nothing matches. Twin of
  /// research/prefix/variant_eval.py: on the 2 000 brands that cost the most
  /// unanswered scans in the EU, it answered 26 (plural and article rules
  /// were tried and dropped: they gave wrong owners).
  String? variantKey(final String key) {
    final Map<String, dynamic> brands = _db['brands'] as Map<String, dynamic>;
    final Map<String, dynamic> byCountry = _db['by_country'] as Map<String, dynamic>;
    bool known(final String k) => brands.containsKey(k) || byCountry.containsKey(k);
    if (known(key)) {
      return null;
    }
    for (final (RegExp pattern, String to) in _swaps) {
      final String v = key.replaceAll(pattern, to);
      if (v != key && known(v)) {
        return v;
      }
    }
    final String flat = key.replaceAll(' ', '');
    if (flat.length < 7) {
      return null;
    }
    _noSpace ??= () {
      final Map<String, String> out = <String, String>{};
      final Set<String> clash = <String>{};
      for (final String k in <String>[...brands.keys, ...byCountry.keys]) {
        final String f = k.replaceAll(' ', '');
        final String? old = out[f];
        if (old != null && old != k) {
          clash.add(f);
        }
        out[f] = k;
      }
      clash.forEach(out.remove);
      return out;
    }();
    final String? v = _noSpace![flat];
    return v == key ? null : v;
  }

  /// Ultimate owner for a company name read off a label (EU 1169/2011 art. 9(1)(h)).
  String? ownerOfCompany(final String companyName) {
    final Map<String, dynamic> companies = _db['companies'] as Map<String, dynamic>;
    final dynamic i = companies[OwnershipNorm.normCore(companyName)];
    if (i != null) {
      return _s(i);
    }
    final LocalOwnerResult? asBrand = _byBrands(companyName, const <String>[]);
    // "Nestlé Suisse", "Mondelez Danmark ApS": the group behind a local name.
    return asBrand?.owner ?? _byCompanyHead(companyName, const <String>[])?.owner;
  }

  static final RegExp _legalForm = RegExp(
    r'(?:^|[\s,])(s\.?\s?l\.?\s?u?|s\.?\s?a\.?\s?u?|s\.?a\.?s\.?u?|s\.?r\.?l|s\.?p\.?a|gmbh(?:\s?&\s?co\.?\s?kg)?|'
    r'sp\.?\s?z\s?o\.?\s?o|a/s|aps|b\.?v|n\.?v|ltd|limited|sarl|oyj?)\.?\s*$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _word = RegExp(r'\p{L}{3,}', unicode: true);
  static final RegExp _spaces = RegExp(r'\s+', unicode: true);

  /// A brand field that is itself a company name ("Foo S.L.") means that
  /// company owns the product. Only the raw string counts: the bare name
  /// "Foo" could be any other company. Port of build_db.legal_company.
  static String? legalCompanyName(final String? brands) {
    for (final String x in OwnershipNorm.splitBrands(brands)) {
      final RegExpMatch? m = _legalForm.firstMatch(x);
      if (m != null && _word.hasMatch(x.substring(0, m.start))) {
        return x.replaceAll(_spaces, ' ').replaceAll(RegExp(r'^[ ,.]+|[ ,.]+$'), '');
      }
    }
    return null;
  }

  /// OFF stores `emb_codes` as free text ("FR 56.178.001 CE, ..."); the
  /// database keys use OFF's tag form ("fr-56-178-001-ec").
  static List<String> embCodeTags(final String? embCodes) => (embCodes ?? '')
      .split(',')
      .map((String c) => c.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'))
      .map((String t) => t.replaceAll(RegExp(r'^-+|-+$'), '').replaceFirst(RegExp(r'-ce$'), '-ec'))
      .where((String t) => t.isNotEmpty)
      .toList();

  static final RegExp _markSuffix = RegExp(r'(^|[^a-z])(ec|ce|eg|eu|ue|ek|ey|we|es|ef)$');
  static final RegExp _groups = RegExp(r'[a-z]+|\d+');

  /// Port of research/prefix/packager_map.py tag_keys/normkey.
  static List<String> embKeys(final String tag) {
    final int dash = tag.indexOf('-');
    if (dash < 0) {
      return <String>[tag];
    }
    final String cc = tag.substring(0, dash);
    final String rest = tag.substring(dash + 1).toLowerCase().trim().replaceFirst(_markSuffix, '');
    final String key = _groups
        .allMatches(rest)
        .map((Match m) => int.tryParse(m.group(0)!)?.toString() ?? m.group(0)!)
        .join('.');
    return <String>[tag, 'n:$cc:$key'];
  }
}
