import 'package:flutter/foundation.dart';

/// Lets the page around a scanner draw its own controls (torch) instead of
/// the scanner's built-in ones. The scanner implementation binds itself here
/// while it is on screen.
class ScannerRemote {
  /// null: no torch on this camera (or no camera yet); else whether it is on.
  final ValueNotifier<bool?> torch = ValueNotifier<bool?>(null);

  VoidCallback? _toggleTorch;

  void toggleTorch() => _toggleTorch?.call();

  /// Called by a scanner implementation.
  void bind({required final VoidCallback toggleTorch}) => _toggleTorch = toggleTorch;

  void unbind() {
    _toggleTorch = null;
    torch.value = null;
  }

  void dispose() => torch.dispose();
}
