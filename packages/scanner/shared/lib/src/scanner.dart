import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:scanner_shared/src/scanner_remote.dart';

/// Base class for the Scanner interface…
abstract class Scanner {
  const Scanner();

  static const String ANALYTICS_CATEGORY = 'scanning';
  static const String ANALYTICS_STRANGE_RESTART = 'strange restart';
  static const String ANALYTICS_STRANGE_RESTOP = 'strange restop';

  String getType();

  Widget getScanner({
    required Future<bool> Function(String) onScan,
    required Future<void> Function() hapticFeedback,
    required Function(BuildContext)? onCameraFlashError,
    required Function(
      String msg,
      String category, {
      int? eventValue,
      String? barcode,
    })
    trackCustomEvent,
    required bool hasMoreThanOneCamera,
    required Widget barcodeScannerIcon,
    required Widget torchOnIcon,
    required Widget torchOffIcon,

    String? toggleCameraModeTooltip,
    String? toggleFlashModeTooltip,

    /// Padding to apply to the content (eg: the visor)
    EdgeInsetsGeometry? contentPadding,

    /// The camera frame a barcode was read from (JPEG), when available.
    /// Called before [onScan].
    void Function(Uint8List image)? onImage,

    /// false: no visor and no buttons; the page draws its own (see [remote]).
    bool showOverlay = true,
    ScannerRemote? remote,
  });
}
