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
  const LensClient({this.endpoint = defaultEndpoint, this.timeout = const Duration(seconds: 9)});

  static const String defaultEndpoint = String.fromEnvironment(
    'OWNED_LENS_URL',
    defaultValue: 'https://owned-lens.ossified-glow.workers.dev',
  );

  final String endpoint;
  final Duration timeout;

  Future<LensResult?> identify(final String path) async {
    final List<int>? jpeg = await FlutterImageCompress.compressWithFile(
      path,
      minWidth: 768,
      minHeight: 768,
      quality: 85,
    );
    if (jpeg == null) {
      return null;
    }
    final http.Response r = await http
        .post(Uri.parse('$endpoint/id'), headers: <String, String>{'content-type': 'image/jpeg'}, body: jpeg)
        .timeout(timeout);
    if (r.statusCode != 200) {
      return null;
    }
    return LensResult.fromJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  /// The product code the model read under the bars, when its check digit
  /// is right.
  static String? barcodeOf(final LensResult r) {
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
  }) {
    final List<BrandCandidate> out = <BrandCandidate>[];
    if (db != null && r.brand.isNotEmpty) {
      LocalOwnerResult? byBrand;
      // The model writes "Coeur de Lion"; the table has the pack's "Cœur".
      for (final String spelling in <String>{r.brand, r.brand.replaceAll('oe', 'œ').replaceAll('Oe', 'Œ')}) {
        byBrand = db.lookup(barcode: '', brands: spelling, countryTags: countryTags);
        if (byBrand != null) {
          break;
        }
      }
      if (byBrand != null && byBrand.source != LocalOwnerSource.barcodePrefix) {
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
