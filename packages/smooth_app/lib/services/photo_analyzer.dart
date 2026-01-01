import 'dart:async';

import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:smooth_app/helpers/gs1_code.dart';
import 'package:smooth_app/services/barcode_rescue.dart';
import 'package:smooth_app/services/brand_text_matcher.dart';
import 'package:smooth_app/services/label_ocr.dart';
import 'package:smooth_app/services/label_operator_parser.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/ownership_norm.dart';
import 'package:smooth_app/services/ownership_service.dart';

/// What a photo of a pack told us.
class PhotoAnalysis {
  const PhotoAnalysis({this.barcode, this.brands = const <BrandCandidate>[]});

  /// A barcode in the picture (GTIN): the normal product page answers when
  /// a database knows it; else [brands] (read on the photo, or the barcode
  /// prefix's company) do.
  final String? barcode;

  /// Brands (or the company on the label) with their owner, best first.
  final List<BrandCandidate> brands;

  bool get isEmpty => barcode == null && brands.isEmpty;
}

/// Reads a photo of a product on the phone, in this order:
/// 1. a barcode anywhere in the picture;
/// 2. the brand printed on the pack, matched against the offline DB;
/// 3. the company the EU label names ("Fabriqué pour ...", art. 9(1)(h)
///    1169/2011), followed up to its owner;
/// 4. online, the biggest words on Wikidata (only when 1-3 found nothing).
class PhotoAnalyzer {
  PhotoAnalyzer({
    this.ocr = const MlKitLabelOcr(),
    Future<String?> Function(String path)? readBarcode,
    Future<OwnershipLocalDb> Function()? localDb,
    Future<Set<String>> Function()? packWords,
    Future<BrandOwnerResult?> Function(String brand)? online,
    Future<String?> Function(String path, Future<String?> Function(String path) read)? enhancedRead,
  }) : _readBarcode = readBarcode ?? _mlKitBarcode,
       _enhancedRead = enhancedRead ?? BarcodeRescue.enhancedPasses,
       _localDb = localDb ?? OwnershipLocalDb.load,
       _packWords = packWords ?? BrandTextMatcher.loadPackWords,
       _online = online ?? OwnershipService().lookupWikidata;

  final LabelOcr ocr;
  final Future<String?> Function(String path) _readBarcode;
  final Future<OwnershipLocalDb> Function() _localDb;
  final Future<Set<String>> Function() _packWords;
  final Future<BrandOwnerResult?> Function(String brand) _online;
  final Future<String?> Function(String path, Future<String?> Function(String path) read) _enhancedRead;

  /// Steps for the "analyzing" screen.
  static const List<String> steps = <String>[
    'Looking for a barcode',
    'Reading the pack',
    'Matching 18,000 brands',
    'Finding the owner',
  ];

  Future<PhotoAnalysis> analyze(
    final String path, {
    final List<String> countryTags = const <String>[],
    final void Function(int step)? onStep,
  }) async {
    onStep?.call(0);
    // The pack is read even when a barcode is found: a barcode no database
    // knows still gets an answer from the brand on the photo (11/11 2026).
    String? barcode = await _safe(() => _readBarcode(path));
    onStep?.call(1);
    final LabelText text = await _safe(() => ocr.readLines(path)) ?? LabelText.empty;
    final List<String> lines = <String>[for (final PackTextLine l in text.lines) l.text];
    // 20/11: the bars were not readable (blur, glare, a curved pack); the
    // digits printed under them often are.
    barcode ??= BarcodeRescue.fromText(lines);
    onStep?.call(2);
    final OwnershipLocalDb? db = await _safe(_localDb);
    final List<BrandCandidate> found = <BrandCandidate>[];
    if (db != null) {
      final BrandTextMatcher matcher = BrandTextMatcher(db, await _safe(_packWords) ?? const <String>{});
      found.addAll(matcher.match(text.lines, countryTags: countryTags));
      for (final String company in LabelOperatorParser.candidates(text.text)) {
        final String? owner = db.ownerOfCompany(company);
        if (owner == null) {
          continue;
        }
        found.add(BrandCandidate(
          key: OwnershipNorm.normCore(company),
          name: company,
          owner: LocalOwnerResult(
            owner: owner,
            source: LocalOwnerSource.labelCompany,
            chain: <String>[company, if (OwnershipNorm.normCore(owner) != OwnershipNorm.normCore(company)) owner],
          ),
          score: 0.0,
        ));
      }
    }
    onStep?.call(3);
    if (barcode == null && (found.isEmpty || BarcodeRescue.mentionsACode(lines))) {
      // Nothing else to go on, or digits as long as a barcode's: read the
      // bars again on clearer versions of the photo. Skipped for a plain
      // front-of-pack photo with a known brand, so that stays fast.
      barcode = await _safe(() => _enhancedRead(path, _readBarcode));
    }
    if (found.isEmpty && barcode != null && db != null) {
      // The company that registered the barcode's GS1 prefix.
      final LocalOwnerResult? byCode = db.lookup(barcode: barcode);
      if (byCode != null) {
        found.add(BrandCandidate(
          key: OwnershipNorm.normCore(byCode.owner),
          name: byCode.chain.isEmpty ? byCode.owner : byCode.chain.first,
          owner: byCode,
          score: 0.0,
        ));
      }
    }
    if (found.isEmpty && barcode == null) {
      found.addAll(await _onlineGuess(text.lines));
    }
    return PhotoAnalysis(barcode: barcode, brands: _distinctOwners(found));
  }

  /// The biggest words on the pack, looked up on Wikidata.
  Future<List<BrandCandidate>> _onlineGuess(final List<PackTextLine> lines) async {
    final List<PackTextLine> big = List<PackTextLine>.of(lines)
      ..sort((PackTextLine a, PackTextLine b) => b.height.compareTo(a.height));
    final List<BrandCandidate> out = <BrandCandidate>[];
    for (final PackTextLine line in big.take(2)) {
      final String name = line.text.trim();
      final String key = OwnershipNorm.normCore(name);
      if (key.replaceAll(' ', '').length < 3 || key.split(' ').length > 3 || int.tryParse(key.replaceAll(' ', '')) != null) {
        continue;
      }
      final BrandOwnerResult? r = await _safe(() => _online(name).timeout(const Duration(seconds: 8)));
      if (r == null) {
        continue;
      }
      out.add(BrandCandidate(
        key: key,
        name: name,
        owner: LocalOwnerResult(owner: r.ownerCompany, source: LocalOwnerSource.other, chain: r.ownerChain),
        score: 0.0,
      ));
    }
    return out;
  }

  static List<BrandCandidate> _distinctOwners(final List<BrandCandidate> all) {
    final Set<String> owners = <String>{};
    return <BrandCandidate>[
      for (final BrandCandidate c in all)
        if (owners.add(OwnershipNorm.normCore(c.owner.owner))) c,
    ];
  }

  static Future<T?> _safe<T>(final Future<T?> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _mlKitBarcode(final String path) async {
    final MobileScannerController controller = MobileScannerController(autoStart: false);
    try {
      final BarcodeCapture? capture = await controller.analyzeImage(path).timeout(const Duration(seconds: 6));
      for (final Barcode b in capture?.barcodes ?? const <Barcode>[]) {
        final String? code = Gs1Code.toProductCode(b.rawValue ?? b.displayValue ?? '');
        if (code != null) {
          return code;
        }
      }
      return null;
    } finally {
      unawaited(controller.dispose());
    }
  }
}
