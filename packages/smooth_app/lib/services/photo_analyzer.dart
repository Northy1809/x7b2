import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:smooth_app/helpers/gs1_code.dart';
import 'package:smooth_app/services/barcode_rescue.dart';
import 'package:smooth_app/services/brand_text_matcher.dart';
import 'package:smooth_app/services/label_ocr.dart';
import 'package:smooth_app/services/label_operator_parser.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/ownership_norm.dart';
import 'package:smooth_app/services/ownership_service.dart';
import 'package:smooth_app/services/zxing_barcode_reader.dart';

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
    Future<String?> Function(String path)? prepare,
  }) : _prepare = prepare ?? uprightCopy,
       _readBarcode = readBarcode ?? bothReaders,
       _enhancedRead = enhancedRead,
       _localDb = localDb ?? OwnershipLocalDb.load,
       _packWords = packWords ?? BrandTextMatcher.loadPackWords,
       _online = online ?? OwnershipService().lookupWikidata;

  final LabelOcr ocr;
  final Future<String?> Function(String path) _prepare;
  final Future<String?> Function(String path) _readBarcode;
  final Future<OwnershipLocalDb> Function() _localDb;
  final Future<Set<String>> Function() _packWords;
  final Future<BrandOwnerResult?> Function(String brand) _online;
  /// Extra reads of the photo when nothing was found. None by default: the
  /// clearer passes (middle, band, contrast) are part of zxing-cpp's read
  /// since 25/11, without writing image files.
  final Future<String?> Function(String path, Future<String?> Function(String path) read)? _enhancedRead;

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
    final Stopwatch watch = Stopwatch()..start();
    // 23/11: the camera's full-size photo, turned upright (the camera only
    // notes "turned" in the file, and the barcode reader ignores that) and
    // made a sensible size, read by everything below.
    final String work = await _safe(() => _prepare(path)) ?? path;
    final int tUpright = watch.elapsedMilliseconds;
    // The pack is read even when a barcode is found: a barcode no database
    // knows still gets an answer from the brand on the photo (11/11 2026).
    // 25/11: both at the same time (they were one after the other).
    int tBars = 0;
    int tText = 0;
    final Future<String?> bars = _safe(() => _readBarcode(work)).then((String? c) {
      tBars = watch.elapsedMilliseconds - tUpright;
      return c;
    });
    final Future<LabelText?> reading = _safe(() => ocr.readLines(work)).then((LabelText? t) {
      tText = watch.elapsedMilliseconds - tUpright;
      return t;
    });
    String? barcode = await bars;
    String how = barcode == null ? '' : 'bars';
    onStep?.call(1);
    final LabelText text = await reading ?? LabelText.empty;
    final List<String> lines = <String>[for (final PackTextLine l in text.lines) l.text];
    // 20/11: the bars were not readable (blur, glare, a curved pack); the
    // digits printed under them often are.
    if (barcode == null) {
      barcode = BarcodeRescue.fromText(lines);
      how = barcode == null ? '' : 'digits';
    }
    // 23/11: still none: the bars again on clearer versions of the photo,
    // while the brands are matched. Always, also with a brand on the front:
    // a guessed brand is worse than the product the barcode names.
    final Future<String?>? rescue =
        barcode == null && _enhancedRead != null ? _safe(() => _enhancedRead(work, _readBarcode)) : null;
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
    if (rescue != null) {
      barcode = await rescue;
      how = barcode == null ? 'none' : 'clearer';
    }
    if (barcode == null) {
      how = 'none';
    }
    if (!identical(work, path)) {
      unawaited(_safe(() => File(work).delete()));
    }
    lastRun = 'barcode=${barcode ?? '-'} via=$how brands=${found.length} lines=${lines.length} ms=${watch.elapsedMilliseconds} upright=$tUpright bars=$tBars text=$tText';
    debugPrint('OWNED_SCAN $lastRun');
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

  /// What the last [analyze] found and how, for the log and the self-test.
  String lastRun = '';

  /// [path] turned upright and at most about 2400 x 3200, written next to
  /// it; null when it could not be made (the original is read then).
  static Future<String?> uprightCopy(final String path) async {
    final String target = path.replaceFirst(RegExp(r'(\.[^./\\]+)?$'), '_upright.jpg');
    final XFile? out = await FlutterImageCompress.compressAndGetFile(
      path,
      target,
      minWidth: 2400,
      minHeight: 2400,
      quality: 92,
    ).timeout(const Duration(seconds: 4));
    return out?.path;
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

  /// 24/11: the phone's reader (Apple Vision) first, zxing-cpp when it
  /// finds nothing. When the phone's reader sees several product codes,
  /// one zxing-cpp also reads wins.
  static Future<String?> bothReaders(final String path) async {
    final List<String> phone = await _safe(() => _phoneBarcodes(path)) ?? const <String>[];
    if (phone.length == 1) {
      return phone.first;
    }
    final List<String> zxing = await _safe(
          () => ZxingBarcodeReader.readFile(path).timeout(const Duration(seconds: 5)),
        ) ??
        const <String>[];
    for (final String code in phone) {
      if (zxing.contains(code)) {
        return code;
      }
    }
    if (phone.isNotEmpty) {
      return phone.first;
    }
    return zxing.isEmpty ? null : zxing.first;
  }

  static Future<List<String>> _phoneBarcodes(final String path) async {
    final MobileScannerController controller = MobileScannerController(autoStart: false);
    try {
      final BarcodeCapture? capture = await controller.analyzeImage(path).timeout(const Duration(seconds: 4));
      return <String>{
        for (final Barcode b in capture?.barcodes ?? const <Barcode>[])
          if (Gs1Code.toProductCode(b.rawValue ?? b.displayValue ?? '') != null)
            Gs1Code.toProductCode(b.rawValue ?? b.displayValue ?? '')!,
      }.toList();
    } finally {
      unawaited(controller.dispose());
    }
  }
}
