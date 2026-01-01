import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:image/image.dart' as img;
import 'package:smooth_app/helpers/gs1_code.dart';

/// 24/11 2026: the second barcode reader, zxing-cpp (the C++ ZXing), next to
/// the phone's own (Apple Vision on iOS). On the 240 test photos Vision
/// missed 22; zxing-cpp read half of those. The rest show no whole barcode.
class ZxingBarcodeReader {
  const ZxingBarcodeReader._();

  static const int _formats = Format.ean13 | Format.ean8 | Format.upca | Format.upce;

  /// The product codes on the photo at [path] (upright already), read in a
  /// background isolate.
  static Future<List<String>> readFile(final String path) async {
    final Uint8List bytes = await File(path).readAsBytes();
    return Isolate.run(() => readBytes(bytes));
  }

  /// Product codes in an encoded image ([bytes]: JPEG, PNG ...), trying the
  /// full size and smaller ones (a big, soft barcode reads better small).
  static List<String> readBytes(final Uint8List bytes) {
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return const <String>[];
    }
    final img.Image image = img.bakeOrientation(decoded);
    final int long = image.width > image.height ? image.width : image.height;
    for (final int side in <int>[long, 1400, 1000]) {
      if (side > long) {
        continue;
      }
      final img.Image scaled = side == long
          ? image
          : img.copyResize(
              image,
              width: image.width >= image.height ? side : null,
              height: image.width >= image.height ? null : side,
              interpolation: img.Interpolation.average,
            );
      final List<String> codes = _read(scaled);
      if (codes.isNotEmpty) {
        return codes;
      }
    }
    return const <String>[];
  }

  static List<String> _read(final img.Image image) {
    final Uint8List lum = Uint8List(image.width * image.height);
    int i = 0;
    for (final img.Pixel p in image) {
      lum[i++] = (p.r.toInt() + 2 * p.g.toInt() + p.b.toInt()) >> 2;
    }
    final Codes result = zx.readBarcodes(
      lum,
      DecodeParams(
        imageFormat: ImageFormat.lum,
        format: _formats,
        width: image.width,
        height: image.height,
        tryHarder: true,
        tryRotate: true,
        tryInverted: true,
        tryDownscale: true,
        maxNumberOfSymbols: 4,
        maxSize: image.width > image.height ? image.width : image.height,
      ),
    );
    return <String>{
      for (final Code c in result.codes)
        if (c.isValid && Gs1Code.toProductCode(c.text ?? '') != null) Gs1Code.toProductCode(c.text!)!,
    }.toList();
  }
}
