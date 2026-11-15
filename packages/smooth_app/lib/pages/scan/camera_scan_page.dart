import 'dart:typed_data';

import 'package:flutter/material.dart' hide Listener;
import 'package:matomo_tracker/matomo_tracker.dart';
import 'package:scanner_shared/scanner_shared.dart';
import 'package:smooth_app/generic_lib/dialogs/smooth_alert_dialog.dart';
import 'package:smooth_app/helpers/analytics_helper.dart';
import 'package:smooth_app/helpers/camera_helper.dart';
import 'package:smooth_app/helpers/global_vars.dart';
import 'package:smooth_app/helpers/haptic_feedback_helper.dart';
import 'package:smooth_app/l10n/app_localizations.dart';
import 'package:smooth_app/resources/app_icons.dart' as icons;

/// The camera feed, decoding barcodes. Draws nothing on top: the scan page
/// owns the frame and the buttons (torch through [remote]).
class CameraScannerPage extends StatefulWidget {
  const CameraScannerPage({
    required this.onBarcode,
    this.onImage,
    this.remote,
    super.key,
  });

  /// true when the code was taken.
  final Future<bool> Function(String barcode) onBarcode;

  /// The frame the next barcode is read from (JPEG).
  final void Function(Uint8List image)? onImage;
  final ScannerRemote? remote;

  @override
  State<CameraScannerPage> createState() => _CameraScannerPageState();

  static Future<void> onCameraFlashError(BuildContext context) async {
    final AppLocalizations appLocalizations = AppLocalizations.of(context);
    return showDialog<void>(
      context: context,
      builder: (_) => SmoothAlertDialog(
        title: appLocalizations.camera_flash_error_dialog_title,
        body: Text(appLocalizations.camera_flash_error_dialog_message),
      ),
    );
  }
}

class _CameraScannerPageState extends State<CameraScannerPage>
    with TraceableClientMixin {
  @override
  String get actionName => 'Opened ${GlobalVars.barcodeScanner.getType()}_page';

  @override
  Widget build(BuildContext context) {
    final AppLocalizations appLocalizations = AppLocalizations.of(context);

    if (!CameraHelper.hasACamera) {
      return Center(child: Text(appLocalizations.permission_photo_none_found));
    }

    return ScreenVisibilityDetector(
      child: Semantics(
        label: appLocalizations.camera_window_accessibility_label,
        explicitChildNodes: true,
        child: GlobalVars.barcodeScanner.getScanner(
          onScan: widget.onBarcode,
          onImage: widget.onImage,
          remote: widget.remote,
          showOverlay: false,
          hapticFeedback: () => SmoothHapticFeedback.click(),
          onCameraFlashError: CameraScannerPage.onCameraFlashError,
          trackCustomEvent: AnalyticsHelper.trackCustomEvent,
          hasMoreThanOneCamera: CameraHelper.hasMoreThanOneCamera,
          toggleCameraModeTooltip: appLocalizations.camera_toggle_camera,
          toggleFlashModeTooltip: appLocalizations.camera_toggle_flash,
          barcodeScannerIcon: const icons.Barcode.withCorners(),
          torchOnIcon: const icons.Torch.on(),
          torchOffIcon: const icons.Torch.off(),
        ),
      ),
    );
  }
}
