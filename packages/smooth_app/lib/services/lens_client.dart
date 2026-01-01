import 'dart:async';
import 'dart:convert';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:smooth_app/helpers/gs1_code.dart';
import 'package:smooth_app/services/brand_text_matcher.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/ownership_norm.dart';

/// What the vision model read on a photo of a pack.
class LensResult {
  const LensResult({this.brand = '', this.product = '', this.company = '', this.barcode = ''});

  factory LensResult.fromJson(final Map<String, dynamic> j) => LensResult(
    brand: (j['brand'] as String? ?? '').trim(),
    product: (j['product'] as String? ?? '').trim(),
    company: (j['company'] as String? ?? '').trim(),
    barcode: (j['barcode'] as String? ?? '').trim(),
  );

  /// The brand as printed (the logo).
  final String brand;
  final String product;

  /// The company the label names.
  final String company;

  /// Digits printed under a barcode, when the model could read them.
  final String barcode;
}

/// 25/11 2026: "Lens" for packs no barcode or offline brand gives: the
/// photo (768 px) goes to a vision model (Llama 4 Scout on Cloudflare
/// Workers AI, free daily allowance, no key in the app; see lens-worker/).
/// On the 120 test products it named the brand of 105 from the front; with
/// the offline table that gave the right owner for 104 of the 112 whose
/// owner is known.
class LensClient {
  const LensClient({this.endpoint, this.timeout = const Duration(seconds: 9)});

  static const String defaultEndpoint = String.fromEnvironment(
    'OWNED_LENS_URL',
    defaultValue: 'https://owned-lens.supreme-naranja.workers.dev',
  );

  /// 25/11: where the server is now, one line of text. The server can move
  /// (a new Cloudflare account) without a new app.
  static const String configUrl = 'https://raw.githubusercontent.com/Northy1809/x7b2/main/l';

  /// null: [current], read from [configUrl].
  final String? endpoint;
  final Duration timeout;

  static Future<String>? _current;

  /// The server's address: from [configUrl] once per run of the app, else
  /// [defaultEndpoint].
  static Future<String> current() => _current ??= _fetch().then((String? u) {
    if (u == null) {
      // Ask again on the next scan.
      _current = null;
    }
    return u ?? defaultEndpoint;
  });

  static Future<String?> _fetch() async {
    try {
      final http.Response r = await http.get(Uri.parse(configUrl)).timeout(const Duration(seconds: 4));
      return r.statusCode == 200 ? parseConfig(r.body) : null;
    } catch (_) {
      return null;
    }
  }

  /// The address in the config text: one https URL, without a trailing /.
  static String? parseConfig(final String text) {
    final String line = text.trim().split('\n').first.trim();
    final Uri? u = Uri.tryParse(line);
    if (u == null || u.scheme != 'https' || u.host.isEmpty) {
      return null;
    }
    return line.endsWith('/') ? line.substring(0, line.length - 1) : line;
  }

  /// Looks the address up before the first photo (the scan page opens).
  static void warmUp() => unawaited(current());

  Future<LensResult?> identify(final String path) async {
    final Future<String> where = endpoint == null ? current() : Future<String>.value(endpoint);
    // 1024 px: 107 of 120 brands against 105 at 768 (25/11).
    final List<int>? jpeg = await FlutterImageCompress.compressWithFile(
      path,
      minWidth: 1024,
      minHeight: 1024,
      quality: 85,
    );
    if (jpeg == null) {
      return null;
    }
    final http.Response r = await http
        .post(Uri.parse('${await where}/id'), headers: <String, String>{'content-type': 'image/jpeg'}, body: jpeg)
        .timeout(timeout);
    if (r.statusCode != 200) {
      return null;
    }
    return LensResult.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  /// The product code the model read under the bars: a whole EAN-13 or
  /// EAN-8 with a right check digit. Other lengths are not trusted: it
  /// drops digits ("810721998120" for 8010721998120, 25/11), and a padded
  /// short read passes the check digit one time in ten.
  static String? barcodeOf(final LensResult r) {
    if (r.barcode.length != 13 && r.barcode.length != 8) {
      return null;
    }
    final String? code = Gs1Code.toProductCode(r.barcode);
    return code != null && Gs1Code.hasValidCheckDigit(code) ? code : null;
  }

  /// Owners for what the model read, best first: the brand in the offline
  /// table, then the company on the label. Never the model's own idea of
  /// the owner: asked, it was wrong too often (Sanex -> Unilever, Santa
  /// Maria -> Orkla, OZMO -> Coop; 25/11).
  static List<BrandCandidate> candidates(
    final LensResult r,
    final OwnershipLocalDb? db, {
    final List<String> countryTags = const <String>[],
    final Set<String> packWords = const <String>{},
  }) {
    final List<BrandCandidate> out = <BrandCandidate>[];
    final String key = OwnershipNorm.normCore(r.brand);
    if (db != null && r.brand.isNotEmpty && !OwnershipNorm.stopBrands.contains(key)) {
      LocalOwnerResult? byBrand;
      // The model writes "Coeur de Lion"; the table has the pack's "Cœur".
      for (final String spelling in <String>{r.brand, r.brand.replaceAll('oe', 'œ').replaceAll('Oe', 'Œ')}) {
        byBrand = db.lookup(barcode: '', brands: spelling, countryTags: countryTags);
        if (byBrand != null) {
          break;
        }
      }
      // A product word read as the brand ("Tortilla") that the table has as
      // a brand owning itself is junk; a pack word with a real owner
      // ("Cointreau" -> Rémy Cointreau, "Be-Kind" -> Mars) is not (25/11).
      final bool junk =
          byBrand != null && packWords.contains(key) && OwnershipNorm.normCore(byBrand.owner) == key;
      if (byBrand != null && byBrand.source != LocalOwnerSource.barcodePrefix && !junk) {
        out.add(BrandCandidate(key: OwnershipNorm.normCore(r.brand), name: r.brand, owner: byBrand, score: 1.0));
      }
    }
    if (db != null && r.company.isNotEmpty) {
      final String? owner = db.ownerOfCompany(r.company);
      if (owner != null) {
        out.add(BrandCandidate(
          key: OwnershipNorm.normCore(r.company),
          name: r.brand.isEmpty ? r.company : r.brand,
          owner: LocalOwnerResult(
            owner: owner,
            source: LocalOwnerSource.labelCompany,
            chain: <String>[r.company, if (OwnershipNorm.normCore(owner) != OwnershipNorm.normCore(r.company)) owner],
          ),
          score: 0.9,
        ));
      }
    }
    return out;
  }
}
