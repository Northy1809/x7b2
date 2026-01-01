import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:smooth_app/services/zxing_barcode_reader.dart';

/// 25/11: the zxing passes work on grey pixels, without image files.
void main() {
  test('grey pixels of an image', () {
    final img.Image i = img.Image(width: 2, height: 1);
    i.setPixelRgb(0, 0, 255, 255, 255);
    i.setPixelRgb(1, 0, 0, 100, 0);
    final Lum l = Lum.of(i);
    expect(l.pixels, <int>[255, 50]);
  });

  test('shrinkTo averages blocks, fit keeps the shape, crop keeps the rows', () {
    final Lum l = Lum(Uint8List.fromList(<int>[0, 100, 10, 20, 200, 60, 30, 40]), 4, 2);
    final Lum s = l.shrinkTo(2, 1);
    expect(<int>[s.width, s.height], <int>[2, 1]);
    expect(s.pixels, <int>[90, 25]);
    final Lum f = Lum(Uint8List(2400 * 3200), 2400, 3200).fit(1400);
    expect(<int>[f.width, f.height], <int>[1050, 1400]);
    final Lum c = l.crop(1, 0, 2, 2);
    expect(c.pixels, <int>[100, 10, 60, 30]);
  });

  test('stretched makes grey glare black and white', () {
    final Lum l = Lum(Uint8List.fromList(List<int>.generate(1000, (int i) => i.isEven ? 120 : 140)), 1000, 1);
    expect(l.stretched().pixels.toSet(), <int>{0, 255});
  });

  test('a phone photo gives seven passes, all quick', () {
    final Lum full = Lum(Uint8List(2400 * 3200), 2400, 3200);
    final Stopwatch w = Stopwatch()..start();
    final List<Lum> made = <Lum>[for (final Lum Function() p in ZxingBarcodeReader.passes(full)) p()];
    expect(made, hasLength(7));
    expect(w.elapsedMilliseconds, lessThan(3000));
  });

  test('a code counts once two passes read it', () {
    expect(ZxingBarcodeReader.agreedCodes(<String, int>{'3017620422003': 1}), isEmpty);
    expect(ZxingBarcodeReader.agreedCodes(<String, int>{'3017620422003': 2, '0130640000006': 1}), <String>['3017620422003']);
  });
}
