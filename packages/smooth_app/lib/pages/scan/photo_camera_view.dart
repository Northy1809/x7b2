import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:smooth_app/services/live_barcode_reader.dart';
import 'package:visibility_detector/visibility_detector.dart';

/// Lets the scan page take a picture and switch the torch of a
/// [PhotoCameraView] it does not own.
class PhotoCameraHandle {
  /// null: no torch; else whether it is on.
  final ValueNotifier<bool?> torch = ValueNotifier<bool?>(null);
  _PhotoCameraViewState? _view;

  Future<XFile?> takePicture() async => _view?._takePicture();

  Future<void> toggleTorch() async => _view?._toggleTorch();

  /// 25/11: a barcode read from the live picture (see [LiveBarcodeReader]),
  /// before the shutter is pressed. Called once; again after [rearm].
  void Function(String code)? onBarcode;

  /// Reads live barcodes again (after a result was closed).
  void rearm() => _view?._live.start();

  /// Stops the camera so another view can take it.
  Future<void> release() async => _view?._stop();

  void dispose() => torch.dispose();
}

/// Full-screen camera preview for "Photo" mode: a picture of the pack is
/// read on the phone (brand, company on the label) instead of a barcode.
/// The camera only runs while the view is on screen and the app is open.
class PhotoCameraView extends StatefulWidget {
  const PhotoCameraView({required this.handle, super.key});

  final PhotoCameraHandle handle;

  @override
  State<PhotoCameraView> createState() => _PhotoCameraViewState();
}

class _PhotoCameraViewState extends State<PhotoCameraView> {
  CameraController? _controller;
  late final AppLifecycleListener _lifecycle;
  bool _visible = false;
  bool _busy = false;
  String? _error;
  late final LiveBarcodeReader _live = LiveBarcodeReader(onCode: (String code) => widget.handle.onBarcode?.call(code));
  bool _streaming = false;

  @override
  void initState() {
    super.initState();
    widget.handle._view = this;
    _lifecycle = AppLifecycleListener(
      onPause: () => unawaited(_stop()),
      onResume: () {
        if (_visible) {
          unawaited(_start());
        }
      },
    );
  }

  @override
  void dispose() {
    if (identical(widget.handle._view, this)) {
      widget.handle._view = null;
      widget.handle.torch.value = null;
    }
    _lifecycle.dispose();
    unawaited(_controller?.dispose());
    _controller = null;
    super.dispose();
  }

  Future<void> _start() async {
    if (_controller != null || _busy) {
      return;
    }
    _busy = true;
    try {
      // The barcode scanner releases the camera as it leaves the screen.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!mounted || !_visible) {
        return;
      }
      final List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('none', 'No camera found');
      }
      final CameraDescription back = cameras.firstWhere(
        (CameraDescription c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final CameraController controller = CameraController(
        back,
        // 23/11: the full sensor. "high" gave 1280 x 720 photos, too few
        // pixels for the bars of a barcode a hand's width away, and closer
        // than that the lens cannot focus.
        ResolutionPreset.max,
        enableAudio: false,
        // 25/11: frames the barcode reader can use; photos stay JPEG.
        imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted || !_visible) {
        await controller.dispose();
        return;
      }
      try {
        await controller.setFlashMode(FlashMode.off);
        widget.handle.torch.value = false;
      } catch (_) {
        widget.handle.torch.value = null;
      }
      setState(() {
        _controller = controller;
        _error = null;
      });
      await _live.start();
      await _startStream();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'The camera could not start.');
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _stop() async {
    final CameraController? controller = _controller;
    if (controller == null) {
      return;
    }
    if (mounted) {
      setState(() => _controller = null);
    } else {
      _controller = null;
    }
    widget.handle.torch.value = null;
    _live.stop();
    _streaming = false;
    await controller.dispose();
  }

  Future<void> _startStream() async {
    final CameraController? controller = _controller;
    if (controller == null || _streaming || !controller.value.isInitialized) {
      return;
    }
    try {
      await controller.startImageStream(_live.onFrame);
      _streaming = true;
    } catch (_) {}
  }

  Future<void> _stopStream() async {
    final CameraController? controller = _controller;
    if (controller == null || !_streaming) {
      return;
    }
    _streaming = false;
    try {
      await controller.stopImageStream();
    } catch (_) {}
  }

  Future<XFile?> _takePicture() async {
    final CameraController? controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return null;
    }
    // The photo is taken with the frame stream paused (iOS cannot always
    // do both), which then runs on.
    await _stopStream();
    try {
      return await controller.takePicture();
    } catch (_) {
      return null;
    } finally {
      unawaited(_startStream());
    }
  }

  Future<void> _toggleTorch() async {
    final CameraController? controller = _controller;
    final bool? on = widget.handle.torch.value;
    if (controller == null || on == null) {
      return;
    }
    try {
      await controller.setFlashMode(on ? FlashMode.off : FlashMode.torch);
      widget.handle.torch.value = !on;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final CameraController? controller = _controller;
    return VisibilityDetector(
      key: const ValueKey<String>('photo-camera'),
      onVisibilityChanged: (VisibilityInfo info) {
        final bool visible = info.visibleFraction > 0.0;
        if (visible == _visible) {
          return;
        }
        _visible = visible;
        unawaited(visible ? _start() : _stop());
      },
      child: ColoredBox(
        color: Colors.black,
        child: controller == null || !controller.value.isInitialized
            ? Center(
                child: _error == null
                    ? const SizedBox.shrink()
                    : Text(
                        _error!,
                        style: const TextStyle(color: Colors.white70),
                      ),
              )
            : ClipRect(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    // The preview size is landscape; the screen is portrait.
                    width: controller.value.previewSize?.height ?? 1080.0,
                    height: controller.value.previewSize?.width ?? 1920.0,
                    child: CameraPreview(controller),
                  ),
                ),
              ),
      ),
    );
  }
}
