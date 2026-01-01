import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:image/image.dart' as img;
import 'package:smooth_app/helpers/gs1_code.dart';

/// 24/11 2026: the second barcode reader, zxing-cpp (the C++ ZXing), next to
/// the phone's own (Apple Vision on iOS). On the 240 test photos Vision
/// missed 22; zxing-cpp read half of those. The rest show no whole barcode.
///
/// 25/11: the photo is decoded once and every pass works on its grey
/// pixels (whole, smaller, the middle and a band, contrast stretched). The
/// old way wrote three clearer JPEG copies with package:image first: 8 s on
/// a PC, the main part of a 22 s scan on the phone.
class ZxingBarcodeReader {
  const ZxingBarcodeReader._();

  static const int _formats = Format.ean13 | Format.ean8 | Format.upca | Format.upce;

  /// The product codes on the photo at [path] (upright already), read in a
  /// background isolate. Passes stop after [budget].
  static Future<List<String>> readFile(final String path, {final Duration budget = const Duration(seconds: 4)}) async {
    final Uint8List bytes = await File(path).readAsBytes();
    final int ms = budget.inMilliseconds;
    return Isolate.run(() => readBytes(bytes, budgetMs: ms));
  }

  /// Product codes in an encoded image ([bytes]: JPEG, PNG ...): a code
  /// counts once two passes read it. 25/11: on 82 test photos the first
  /// pass to read anything was wrong twice (a dark photo gave a valid but
  /// wrong EAN); two agreeing passes were never wrong and lost 2 of 71.
  /// No new pass starts after [budgetMs].
  static List<String> readBytes(final Uint8List bytes, {final int budgetMs = 4000}) {
    final Stopwatch watch = Stopwatch()..start();
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return const <String>[];
    }
    final img.Image image = img.bakeOrientation(decoded);
    final Lum full = Lum.of(image);
    final Map<String, int> seen = <String, int>{};
    for (final Lum Function() pass in passes(full)) {
      if (watch.elapsedMilliseconds > budgetMs) {
        break;
      }
      for (final String code in _read(pass())) {
        seen[code] = (seen[code] ?? 0) + 1;
      }
      final List<String> agreed = agreedCodes(seen);
      if (agreed.isNotEmpty) {
        return agreed;
      }
    }
    return const <String>[];
  }

  /// Codes read by at least two passes.
  static List<String> agreedCodes(final Map<String, int> seen) => <String>[
    for (final MapEntry<String, int> e in seen.entries)
      if (e.value >= 2) e.key,
  ];

  /// The images read, in order: the whole photo, then 2000, 1600, 1400 and 1000
  /// pixels on the long side (a big, soft barcode reads better small; on
  /// the test photos each size read some the others did not), its middle 60 %
  /// and a band across the middle, contrast stretched (where a barcode is
  /// when someone aims at it, often grey from glare).
  static List<Lum Function()> passes(final Lum full) {
    final int w = full.width;
    final int h = full.height;
    final int long = w > h ? w : h;
    return <Lum Function()>[
      () => full,
      for (final int side in const <int>[2000, 1600, 1400, 1000])
        if (long > side * 1.15) () => full.fit(side),
      () => full.crop((w * 0.2).round(), (h * 0.2).round(), (w * 0.6).round(), (h * 0.6).round()).stretched(),
      () => full.crop(0, (h * 0.3).round(), w, (h * 0.4).round()).stretched(),
    ];
  }

  static List<String> _read(final Lum lum) {
    final Codes result = zx.readBarcodes(
      lum.pixels,
      DecodeParams(
        imageFormat: ImageFormat.lum,
        format: _formats,
        width: lum.width,
        height: lum.height,
        tryHarder: true,
        tryRotate: true,
        tryInverted: true,
        tryDownscale: true,
        maxNumberOfSymbols: 4,
        maxSize: lum.width > lum.height ? lum.width : lum.height,
      ),
    );
    return <String>{
      for (final Code c in result.codes)
        if (c.isValid && Gs1Code.toProductCode(c.text ?? '') != null) Gs1Code.toProductCode(c.text!)!,
    }.toList();
  }
}

/// Grey pixels, one byte each, row by row.
class Lum {
  const Lum(this.pixels, this.width, this.height);

  /// (R + 2G + B) / 4 of every pixel of [image].
  factory Lum.of(final img.Image image) {
    final Uint8List rgb = image.getBytes(order: img.ChannelOrder.rgb);
    final int n = image.width * image.height;
    final Uint8List out = Uint8List(n);
    for (int i = 0, j = 0; i < n; i++, j += 3) {
      out[i] = (rgb[j] + 2 * rgb[j + 1] + rgb[j + 2]) >> 2;
    }
    return Lum(out, image.width, image.height);
  }

  final Uint8List pixels;
  final int width;
  final int height;

  /// Made smaller to [side] pixels on the long side, each new pixel the
  /// average of the old ones it covers.
  Lum fit(final int side) {
    final int long = width > height ? width : height;
    if (side >= long) {
      return this;
    }
    final int w = (width * side / long).round();
    final int h = (height * side / long).round();
    return shrinkTo(w, h);
  }

  /// Box average to [w] x [h] (not larger than now), rows then columns.
  Lum shrinkTo(final int w, final int h) {
    final Uint16List rows = Uint16List(w * height);
    for (int x = 0; x < w; x++) {
      final int x0 = x * width ~/ w;
      final int x1 = (x + 1) * width ~/ w;
      final int n = x1 - x0;
      for (int y = 0; y < height; y++) {
        int sum = 0;
        final int row = y * width;
        for (int i = x0; i < x1; i++) {
          sum += pixels[row + i];
        }
        rows[y * w + x] = sum ~/ n;
      }
    }
    final Uint8List out = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      final int y0 = y * height ~/ h;
      final int y1 = (y + 1) * height ~/ h;
      final int n = y1 - y0;
      for (int x = 0; x < w; x++) {
        int sum = 0;
        for (int i = y0; i < y1; i++) {
          sum += rows[i * w + x];
        }
        out[y * w + x] = sum ~/ n;
      }
    }
    return Lum(out, w, h);
  }

  Lum crop(final int x, final int y, final int w, final int h) {
    final Uint8List out = Uint8List(w * h);
    for (int r = 0; r < h; r++) {
      final int from = (y + r) * width + x;
      out.setRange(r * w, r * w + w, pixels, from);
    }
    return Lum(out, w, h);
  }

  /// The darkest 1 % made black and the lightest 1 % white.
  Lum stretched() {
    final List<int> count = List<int>.filled(256, 0);
    for (final int p in pixels) {
      count[p]++;
    }
    final int cut = pixels.length ~/ 100;
    int lo = 0;
    for (int seen = 0; lo < 255 && seen + count[lo] <= cut; lo++) {
      seen += count[lo];
    }
    int hi = 255;
    for (int seen = 0; hi > 0 && seen + count[hi] <= cut; hi--) {
      seen += count[hi];
    }
    if (hi <= lo) {
      return this;
    }
    final Uint8List map = Uint8List(256);
    for (int v = 0; v < 256; v++) {
      map[v] = v <= lo ? 0 : (v >= hi ? 255 : ((v - lo) * 255) ~/ (hi - lo));
    }
    final Uint8List out = Uint8List(pixels.length);
    for (int i = 0; i < pixels.length; i++) {
      out[i] = map[pixels[i]];
    }
    return Lum(out, width, height);
  }
}
