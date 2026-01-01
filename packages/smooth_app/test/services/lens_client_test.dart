import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_app/services/brand_text_matcher.dart';
import 'package:smooth_app/services/label_ocr.dart';
import 'package:smooth_app/services/lens_client.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/photo_analyzer.dart';

/// 25/11: "Lens" (the vision model) for photos without a readable barcode.
class _Ocr implements LabelOcr {
  const _Ocr(this.lines);

  final List<String> lines;

  @override
  Future<LabelText> readLines(String imagePath) async =>
      LabelText(lines.join('\n'), <PackTextLine>[for (final String l in lines) PackTextLine(l, 20.0)]);

  @override
  Future<String> readText(String imagePath) async => (await readLines(imagePath)).text;
}

OwnershipLocalDb _db() => OwnershipLocalDb.fromJson(<String, dynamic>{
  'strings': <String>['Ferrero SpA', 'Nutella', 'Savencia', 'Cœur de Lion'],
  'brands': <String, dynamic>{
    'nutella': <dynamic>[0, 'w', <int>[1, 0], ''],
    'c ur de lion': <dynamic>[2, 'w', <int>[3, 2], ''],
  },
  'by_country': <String, dynamic>{},
  'prefix': <String, dynamic>{},
  'emb': <String, dynamic>{},
  'companies': <String, dynamic>{},
});

void main() {
  group('LensClient.candidates', () {
    test('the brand the model read, owner from the offline table', () {
      final List<BrandCandidate> c = LensClient.candidates(const LensResult(brand: 'Nutella'), _db());
      expect(c.single.owner.owner, 'Ferrero SpA');
    });

    test('"Coeur de Lion" finds the table\'s "Cœur de Lion"', () {
      final List<BrandCandidate> c = LensClient.candidates(const LensResult(brand: 'Coeur de Lion'), _db());
      expect(c.single.owner.owner, 'Savencia');
    });

    test('an unknown brand gives no owner (the model is never asked for one)', () {
      expect(LensClient.candidates(const LensResult(brand: 'Raw Bite'), _db()), isEmpty);
    });

    test('digits under the bars count only with a right check digit', () {
      expect(LensClient.barcodeOf(const LensResult(barcode: '3017620422003')), '3017620422003');
      expect(LensClient.barcodeOf(const LensResult(barcode: '3017620422004')), isNull);
      expect(LensClient.barcodeOf(const LensResult()), isNull);
    });
  });

  group('PhotoAnalyzer with Lens', () {
    PhotoAnalyzer analyzer({String? bars, LensResult? lens, List<String>? asked, List<String> lines = const <String>['x']}) =>
        PhotoAnalyzer(
          ocr: _Ocr(lines),
          readBarcode: (_) async => bars,
          localDb: () async => _db(),
          packWords: () async => const <String>{},
          online: (_) async => null,
          prepare: (_) async => null,
          lens: (String p) async {
            asked?.add(p);
            return lens;
          },
        );

    test('no barcode: the brand the model read answers', () async {
      final List<String> asked = <String>[];
      final PhotoAnalysis a = await analyzer(lens: const LensResult(brand: 'Nutella'), asked: asked).analyze('x.jpg');
      expect(asked, <String>['x.jpg']);
      expect(a.brands.first.owner.owner, 'Ferrero SpA');
    });

    test('bars read: Lens is not asked', () async {
      final List<String> asked = <String>[];
      final PhotoAnalysis a = await analyzer(bars: '3017620422003', asked: asked).analyze('x.jpg');
      expect(asked, isEmpty);
      expect(a.barcode, '3017620422003');
    });

    test('the digits the model read become the barcode', () async {
      final PhotoAnalysis a = await analyzer(lens: const LensResult(barcode: '3017620422003')).analyze('x.jpg');
      expect(a.barcode, '3017620422003');
    });

    test('a live barcode skips both readers', () async {
      final List<String> asked = <String>[];
      final PhotoAnalysis a = await analyzer(asked: asked).analyze('x.jpg', liveBarcode: '3017620422003');
      expect(asked, isEmpty);
      expect(a.barcode, '3017620422003');
    });

    test('offline (Lens gives nothing): the text reader still answers', () async {
      final PhotoAnalysis a = await analyzer(lines: const <String>['NUTELLA']).analyze('x.jpg');
      expect(a.brands.first.owner.owner, 'Ferrero SpA');
    });
  });
}
