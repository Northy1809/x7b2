import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:smooth_app/helpers/gs1_code.dart';

/// 25/11 2026: barcodes read from the live camera picture, before the
/// shutter is pressed, as every barcode app does. One photo gives the
/// readers one chance; the live picture gives them several a second while
/// the hand moves, the focus settles and the glare shifts.
///
/// The frames go to zxing-cpp in a background isolate, one at a time. A
/// code counts when [agree] frames in a row (within [window]) read it, so
/// a misread of one frame never opens a product.
class LiveBarcodeReader {
  LiveBarcodeReader({required this.onCode, this.agree = 2, this.window = const Duration(milliseconds: 1500)});

  /// Called once per [start] with the product code.
  final void Function(String code) onCode;
  final int agree;
  final Duration window;

  static const int _formats = Format.ean13 | Format.ean8 | Format.upca | Format.upce;

  bool _running = false;
  bool _busy = false;
  bool _done = false;
  String? _last;
  int _seen = 0;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Frames read since [start], for the log.
  int frames = 0;
  int _ms = 0;

  Future<void> start() async {
    _done = false;
    _last = null;
    _seen = 0;
    frames = 0;
    _ms = 0;
    if (_running) {
      return;
    }
    _running = true;
    try {
      await zx.startCameraProcessing();
    } catch (_) {
      _running = false;
    }
  }

  void stop() {
    if (!_running) {
      return;
    }
    _running = false;
    zx.stopCameraProcessing();
  }

  /// For the camera's image stream; frames that come while one is being
  /// read are skipped.
  Future<void> onFrame(final CameraImage image) async {
    if (!_running || _busy || _done) {
      return;
    }
    _busy = true;
    final Stopwatch watch = Stopwatch()..start();
    try {
      final int format = cameraImageFormat(image);
      if (format == ImageFormat.none) {
        return;
      }
      // The middle three quarters, where the brackets are.
      final int w = (image.width * 0.75).round();
      final int h = (image.height * 0.75).round();
      final Codes result = await zx.processCameraImageMulti(
        image,
        DecodeParams(
          imageFormat: format,
          format: _formats,
          width: image.width,
          height: image.height,
          cropLeft: (image.width - w) ~/ 2,
          cropTop: (image.height - h) ~/ 2,
          cropWidth: w,
          cropHeight: h,
          tryHarder: true,
          tryRotate: true,
          tryInverted: false,
          tryDownscale: true,
          maxNumberOfSymbols: 3,
          isMultiScan: true,
          maxSize: math.max(w, h),
        ),
      );
      frames++;
      _ms += watch.elapsedMilliseconds;
      if (frames == 1 || frames % 30 == 0) {
        // For the device log: proof the live picture is being read, and how fast.
        debugPrint('OWNED_LIVE frames=$frames avgMs=${_ms ~/ frames} size=${image.width}x${image.height} read=${result.codes.length}');
      }
      final String? code = vote(
        <String>[
          for (final Code c in result.codes)
            if (c.isValid && c.text != null) c.text!,
        ],
        DateTime.now(),
      );
      if (code != null && !_done && _running) {
        _done = true;
        onCode(code);
      }
    } catch (_) {
      // A frame that could not be read; the next one is.
    } finally {
      _busy = false;
    }
  }

  /// A right check digit, and not a shop's weighed-food code. EAN-8 codes
  /// starting with 2 do count: Lidl prints its own brands with them.
  static bool _counts(final String code) =>
      Gs1Code.hasValidCheckDigit(code) && !(code.length == 13 && Gs1Code.isInStoreCode(code));

  /// The product code to open, once [agree] frames in a row read the same
  /// one; null until then. [texts] are what one frame read.
  String? vote(final List<String> texts, final DateTime now) {
    final List<String> codes = <String>{
      for (final String t in texts)
        if (Gs1Code.toProductCode(t) case final String p when _counts(p)) p,
    }.toList();
    if (codes.length != 1) {
      // Nothing, or several products in view: wait for a clearer frame.
      if (codes.isEmpty && now.difference(_lastAt) > window) {
        _last = null;
        _seen = 0;
      }
      return null;
    }
    final String code = codes.single;
    if (code == _last && now.difference(_lastAt) <= window) {
      _seen++;
    } else {
      _last = code;
      _seen = 1;
    }
    _lastAt = now;
    return _seen >= agree ? code : null;
  }
}
