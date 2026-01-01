import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:smooth_app/services/barcode_rescue.dart';
import 'package:smooth_app/services/brand_text_matcher.dart';
import 'package:smooth_app/services/label_ocr.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/photo_analyzer.dart';

/// 20/11: a barcode the bars did not give is found in the printed digits
/// or on clearer versions of the photo.
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
  'strings': <String>['Ferrero SpA', 'Nutella'],
  'brands': <String, dynamic>{
    'nutella': <dynamic>[0, 'w', <int>[1, 0], ''],
  },
  'by_country': <String, dynamic>{},
  'prefix': <String, dynamic>{},
  'emb': <String, dynamic>{},
  'companies': <String, dynamic>{},
});

void main() {
  group('BarcodeRescue.fromText', () {
    test('EAN-13 printed as 1 + 6 + 6 under the bars', () {
      expect(BarcodeRescue.fromText(<String>['3 017620 422003']), '3017620422003');
    });

    test('the first digit on its own line', () {
      expect(BarcodeRescue.fromText(<String>['3', '017620 422003']), '3017620422003');
    });

    test('UPC-A becomes the 13-digit code', () {
      expect(BarcodeRescue.fromText(<String>['0 36000 29145 2']), '0036000291452');
    });

    test('EAN-8 printed as 4 + 4', () {
      expect(BarcodeRescue.fromText(<String>['9638 5074']), '96385074');
    });

    test('a wrong check digit (a misread) is not a code', () {
      expect(BarcodeRescue.fromText(<String>['3 017620 422004']), isNull);
    });

    test('other numbers on the pack are not codes', () {
      expect(BarcodeRescue.fromText(<String>['Best before 12.03.2027', '400 g', 'Tel. 800 123 456']), isNull);
    });

    test('shop-only codes (weighed food) do not count', () {
      // 2 + 12 digits with a right check digit, but a shop's own code.
      expect(BarcodeRescue.fromText(<String>['2012345678903']), isNull);
    });
  });

  test('makeVariants writes three clearer images and they can be read', () async {
    final Directory dir = await Directory.systemTemp.createTemp('rescue');
    addTearDown(() => dir.delete(recursive: true));
    final String path = '${dir.path}/photo.jpg';
    final img.Image photo = img.Image(width: 2400, height: 1800);
    img.fill(photo, color: img.ColorRgb8(120, 110, 100));
    File(path).writeAsBytesSync(img.encodeJpg(photo));
    final List<String> variants = BarcodeRescue.makeVariants(path);
    expect(variants, hasLength(3));
    for (final String v in variants) {
      final img.Image? i = img.decodeImage(File(v).readAsBytesSync());
      expect(i, isNotNull);
      expect(i!.width <= 3200 && i.height <= 3200, isTrue);
    }
  });

  group('PhotoAnalyzer with blurred bars', () {
    PhotoAnalyzer analyzer(final List<String> lines, {required final List<String> enhancedCalls, String? enhanced}) =>
        PhotoAnalyzer(
          ocr: _Ocr(lines),
          readBarcode: (_) async => null,
          localDb: () async => _db(),
          packWords: () async => const <String>{},
          online: (_) async => null,
          prepare: (_) async => null,
          enhancedRead: (String path, _) async {
            enhancedCalls.add(path);
            return enhanced;
          },
        );

    test('the printed digits give the barcode', () async {
      final List<String> calls = <String>[];
      final PhotoAnalysis a = await analyzer(<String>['Nutella', '3 017620 422003'], enhancedCalls: calls).analyze('x.jpg');
      expect(a.barcode, '3017620422003');
      expect(calls, isEmpty);
    });

    test('nothing readable: the clearer photos are read for bars', () async {
      final List<String> calls = <String>[];
      final PhotoAnalysis a = await analyzer(<String>['blurry'], enhancedCalls: calls, enhanced: '3017620422003')
          .analyze('x.jpg');
      expect(calls, <String>['x.jpg']);
      expect(a.barcode, '3017620422003');
    });

    test('a known brand on the front: the bars are still looked for, the barcode wins', () async {
      final List<String> calls = <String>[];
      final PhotoAnalysis a = await analyzer(<String>['NUTELLA'], enhancedCalls: calls, enhanced: '3017620422003')
          .analyze('x.jpg');
      expect(calls, <String>['x.jpg']);
      expect(a.barcode, '3017620422003');
      expect(a.brands, isNotEmpty);
    });

    test('bars read straight away: no clearer copies', () async {
      final List<String> calls = <String>[];
      final PhotoAnalysis a = await PhotoAnalyzer(
        ocr: const _Ocr(<String>['NUTELLA']),
        readBarcode: (_) async => '3017620422003',
        localDb: () async => _db(),
        packWords: () async => const <String>{},
        online: (_) async => null,
        prepare: (_) async => null,
        enhancedRead: (String path, _) async {
          calls.add(path);
          return null;
        },
      ).analyze('x.jpg');
      expect(calls, isEmpty);
      expect(a.barcode, '3017620422003');
    });

    test('the upright copy is read, not the camera file', () async {
      final List<String> read = <String>[];
      await PhotoAnalyzer(
        ocr: const _Ocr(<String>['blurry']),
        readBarcode: (String p) async {
          read.add(p);
          return null;
        },
        localDb: () async => _db(),
        packWords: () async => const <String>{},
        online: (_) async => null,
        prepare: (_) async => 'x_upright.jpg',
        enhancedRead: (String path, _) async {
          read.add('clearer:$path');
          return null;
        },
      ).analyze('x.jpg');
      expect(read, <String>['x_upright.jpg', 'clearer:x_upright.jpg']);
    });
  });
}
