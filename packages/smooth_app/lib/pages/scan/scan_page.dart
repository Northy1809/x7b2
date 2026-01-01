import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/data_models/continuous_scan_model.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/generic_lib/widgets/owned_wordmark.dart';
import 'package:smooth_app/generic_lib/widgets/smooth_back_button.dart';
import 'package:smooth_app/helpers/camera_helper.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/helpers/permission_helper.dart';
import 'package:smooth_app/l10n/app_localizations.dart';
import 'package:smooth_app/pages/navigator/app_navigator.dart';
import 'package:smooth_app/pages/product/product_page/new_product_header.dart';
import 'package:smooth_app/pages/scan/photo_camera_view.dart';
import 'package:smooth_app/pages/scan/result/photo_result_page.dart';
import 'package:smooth_app/pages/scan/scan_self_test_page.dart';
import 'package:smooth_app/pages/search/search_page.dart';
import 'package:smooth_app/pages/search/search_product_helper.dart';
import 'package:smooth_app/services/pending_scans.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/owned_mark.dart';
import 'package:smooth_app/widgets/scan_sweep.dart';

/// The camera, opened from the + on the home page, laid out as Cal AI's
/// scanner: a × and a ? at the top, white corner brackets, the mode tiles,
/// and the light, the shutter and the photo library at the bottom.
/// The photo is then read on the phone (a barcode anywhere in it, the
/// brand, the company on the label) while a white line sweeps it, and the
/// answer pops up as a sheet (see [PhotoResultPage]).
class ScanPage extends StatefulWidget {
  const ScanPage();

  /// Opens the camera over everything, rising from the bottom.
  static Future<void> open(final BuildContext context) => Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (BuildContext context, _, _) => const ScanPage(),
      transitionsBuilder: (BuildContext context, Animation<double> a, _, Widget child) {
        final Animation<double> t = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.0, 1.0), end: Offset.zero).animate(t),
          child: child,
        );
      },
    ),
  );

  /// Picks a photo from the library and reads it on the home page, as a
  /// camera photo is.
  /// The search, keyboard up: type a brand, product or company and see
  /// who owns it (the + menu's "Who owns…?" and the camera's "Type brand").
  static void openSearch(final BuildContext context) => AppNavigator.of(context).push(
    AppRoutes.SEARCH(transition: ProductPageTransition.slideUp),
    extra: SearchPageExtra(
      searchHelper: SearchProductHelper(),
      autofocus: true,
      backButtonType: BackButtonType.minimize,
    ),
  );

  static Future<void> pickFromGallery(final BuildContext context) async {
    final XFile? file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (file != null) {
      PendingScans.instance.start(file.path);
    }
  }

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final PhotoCameraHandle _camera = PhotoCameraHandle();

  /// A result page is open (or the shutter is busy).
  bool _busy = false;

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  /// As Cal AI: the camera closes and the photo is read in a row at the
  /// top of the home page. Opened as a tab (no route below), the answer
  /// sheet opens over the camera instead.
  Future<void> _open(final String path) async {
    if (!mounted) {
      return;
    }
    final NavigatorState navigator = Navigator.of(context);
    if (navigator.canPop()) {
      PendingScans.instance.start(path);
      navigator.pop();
      return;
    }
    await navigator.push<void>(PhotoResultPage.route(imagePath: path));
  }

  Future<void> _shutter() async {
    if (_busy) {
      return;
    }
    _busy = true;
    try {
      Haptics.shutter();
      final XFile? file = await _camera.takePicture();
      if (file != null) {
        await _open(file.path);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _pickFromGallery() async {
    if (_busy) {
      return;
    }
    _busy = true;
    try {
      final XFile? file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (file != null) {
        await _open(file.path);
      }
    } finally {
      _busy = false;
    }
  }

  void _openSearch() => ScanPage.openSearch(context);

  void _toggleTorch() {
    Haptics.select();
    unawaited(_camera.toggleTorch());
  }

  @override
  Widget build(BuildContext context) {
    if (context.watch<ContinuousScanModel?>() == null) {
      // The camera is starting: the moving logo, white on the camera's black.
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: OwnedLoader(size: 64.0, color: Colors.white)),
      );
    }
    final bool hasACamera = CameraHelper.hasACamera;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (hasACamera)
              Consumer<PermissionListener>(
                builder:
                    (BuildContext context, PermissionListener listener, _) {
                      return switch (listener.value.status) {
                        DevicePermissionStatus.checking => EMPTY_WIDGET,
                        DevicePermissionStatus.granted => PhotoCameraView(
                          handle: _camera,
                        ),
                        _ => const _PermissionDeniedCard(),
                      };
                    },
              ),
            ScanOverlay(
              torch: _camera.torch,
              onShutter: _shutter,
              onGallery: _pickFromGallery,
              onTorch: _toggleTorch,
              onSearch: _openSearch,
              onClose: Navigator.of(context).canPop() ? () => Navigator.of(context).maybePop() : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything drawn over the camera, placed as in Cal AI's scanner.
class ScanOverlay extends StatelessWidget {
  const ScanOverlay({
    required this.torch,
    required this.onShutter,
    required this.onGallery,
    required this.onTorch,
    required this.onSearch,
    this.onClose,
    super.key,
  });

  final ValueListenable<bool?> torch;
  final VoidCallback onShutter;
  final VoidCallback onGallery;
  final VoidCallback onTorch;
  final VoidCallback onSearch;

  /// The × at the top left; hidden when null.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets padding = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        final double top = padding.top + 64.0;
        final double bottom = padding.bottom + 200.0;
        final double room = math.max(120.0, h - top - bottom);
        final Size frame = Size(w - 72.0, math.min((w - 72.0) * 1.3, room));
        final Rect rect = Rect.fromCenter(
          center: Offset(w / 2, top + room / 2),
          width: frame.width,
          height: frame.height,
        );
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: IgnorePointer(child: CustomPaint(painter: _FramePainter(rect: rect))),
              ),
              // 17/11: the scan line moves inside the corners while the
              // camera looks, the same line that then reads the photo.
              Positioned.fromRect(
                rect: rect.deflate(16.0),
                child: ScanSweep(
                  pingPong: true,
                  period: const Duration(milliseconds: 2200),
                  color: Colors.white.withValues(alpha: 0.9),
                  inset: 8.0,
                  trail: 0.22,
                ),
              ),
              Positioned(
                top: padding.top + 10.0,
                left: 20.0,
                right: 20.0,
                child: Row(
                  children: <Widget>[
                    if (onClose != null)
                      _RoundButton(icon: Icons.close_rounded, tooltip: 'Close', onTap: onClose!, size: 40.0)
                    else
                      const SizedBox.square(dimension: 40.0),
                    // The wordmark in the middle, white, as Cal AI's camera.
                    // Held down: the scanner's self-test (23/11).
                    Expanded(
                      child: Center(
                        child: GestureDetector(
                          onLongPress: () => Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(builder: (_) => const ScanSelfTestPage()),
                          ),
                          child: const OwnedWordmark(height: 22.0, color: Colors.white),
                        ),
                      ),
                    ),
                    _RoundButton(
                      icon: Icons.question_mark_rounded,
                      tooltip: 'How to scan',
                      onTap: () => _showTips(context),
                      size: 40.0,
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0.0,
                right: 0.0,
                bottom: padding.bottom + 112.0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const _ModeTile(icon: Icons.center_focus_strong_outlined, label: 'Scan product', selected: true),
                    const SizedBox(width: 8.0),
                    _ModeTile(icon: Icons.keyboard_alt_outlined, label: 'Type brand', onTap: onSearch),
                  ],
                ),
              ),
              Positioned(
                left: 0.0,
                right: 0.0,
                bottom: padding.bottom + 18.0,
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: 36.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      ValueListenableBuilder<bool?>(
                        valueListenable: torch,
                        builder: (BuildContext context, bool? on, _) => on == null
                            ? const SizedBox.square(dimension: 48.0)
                            : _RoundButton(
                                icon: on ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                                tooltip: on ? 'Turn the light off' : 'Turn the light on',
                                onTap: onTorch,
                                active: on,
                              ),
                      ),
                      _Shutter(onTap: onShutter),
                      _RoundButton(
                        icon: Icons.photo_outlined,
                        tooltip: 'Pick a photo',
                        onTap: onGallery,
                        plain: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static void _showTips(final BuildContext context) => showModalBottomSheet<void>(
    context: context,
    builder: (BuildContext context) {
      final ThemeData theme = Theme.of(context);
      Widget tip(final IconData icon, final String text) => Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 14.0),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 22.0),
            const SizedBox(width: 14.0),
            Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
          ],
        ),
      );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(24.0, 0.0, 24.0, 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('How to scan', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 18.0),
              tip(Icons.crop_free_rounded, 'Fill the corners with the front of the pack.'),
              tip(Icons.qr_code_rounded, 'A barcode anywhere in the photo is read too.'),
              tip(Icons.receipt_long_outlined, 'No luck? Snap the back, where the company is printed.'),
              const SizedBox(height: 8.0),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Got it')),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// One of the tiles above the shutter (Cal AI: Scan Food, Barcode...): white
/// when selected, frosted otherwise.
class _ModeTile extends StatelessWidget {
  const _ModeTile({required this.icon, required this.label, this.selected = false, this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color fore = selected ? const Color(0xFF1E1A22) : Colors.white;
    final Widget body = SizedBox(
      width: 104.0,
      height: 62.0,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 22.0, color: fore),
          const SizedBox(height: 4.0),
          Text(
            label,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontFamily: 'CupertinoSystemText',
              fontFamilyFallback: const <String>['Inter'],
              color: fore,
              fontSize: 12.0,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: PressScale(
        onTap: onTap,
        child: selected
            ? DecoratedBox(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14.0)),
                child: body,
              )
            : _Frosted(radius: 14.0, child: body),
      ),
    );
  }
}

/// Cal AI's white rounded corner brackets, with no darkening around them.
class _FramePainter extends CustomPainter {
  _FramePainter({required this.rect});

  final Rect rect;

  static const double _radius = 26.0;
  static const double _corner = 48.0;

  @override
  void paint(Canvas canvas, Size size) {
    const double r = _radius;
    const double c = _corner;
    final double l = rect.left;
    final double t = rect.top;
    final double ri = rect.right;
    final double b = rect.bottom;
    final Path corners = Path()
      ..moveTo(l, t + c)
      ..lineTo(l, t + r)
      ..arcToPoint(Offset(l + r, t), radius: const Radius.circular(r))
      ..lineTo(l + c, t)
      ..moveTo(ri - c, t)
      ..lineTo(ri - r, t)
      ..arcToPoint(Offset(ri, t + r), radius: const Radius.circular(r))
      ..lineTo(ri, t + c)
      ..moveTo(ri, b - c)
      ..lineTo(ri, b - r)
      ..arcToPoint(Offset(ri - r, b), radius: const Radius.circular(r))
      ..lineTo(ri - c, b)
      ..moveTo(l + c, b)
      ..lineTo(l + r, b)
      ..arcToPoint(Offset(l, b - r), radius: const Radius.circular(r))
      ..lineTo(l, b - c);
    canvas.drawPath(
      corners,
      Paint()
        ..color = Colors.black26
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
    );
    canvas.drawPath(
      corners,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.rect != rect;
}

/// Frosted glass over the camera.
class _Frosted extends StatelessWidget {
  const _Frosted({required this.child, this.radius = 24.0});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.size = 48.0,
    this.plain = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final double size;

  /// Just the white icon, no disc (Cal AI's library button).
  final bool plain;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: PressScale(
          onTap: onTap,
          scale: 0.9,
          child: plain
              ? SizedBox.square(
                  dimension: size,
                  child: Icon(icon, color: Colors.white, size: 28.0),
                )
              : active
              ? Container(
                  width: size,
                  height: size,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: const Color(0xFF1E1A22), size: size * 0.48),
                )
              : _Frosted(
                  radius: size / 2,
                  child: SizedBox.square(
                    dimension: size,
                    child: Icon(icon, color: Colors.white, size: size * 0.48),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Cal AI's shutter: a plain white disc that shrinks while pressed.
class _Shutter extends StatefulWidget {
  const _Shutter({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_Shutter> createState() => _ShutterState();
}

class _ShutterState extends State<_Shutter> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Take the photo',
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.9 : 1.0,
          duration: _down ? CalMotion.pressIn : CalMotion.pressOut,
          curve: _down ? Curves.easeOut : Curves.easeOutBack,
          child: Container(
            width: 78.0,
            height: 78.0,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: <BoxShadow>[BoxShadow(color: Color(0x33000000), blurRadius: 12.0)],
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionDeniedCard extends StatelessWidget {
  const _PermissionDeniedCard();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations localizations = AppLocalizations.of(context);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsetsDirectional.all(VERY_LARGE_SPACE),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.no_photography_outlined,
                color: Colors.white70,
                size: 48.0,
              ),
              const SizedBox(height: LARGE_SPACE),
              Text(
                localizations.permission_photo_denied_title,
                style: const TextStyle(
                  fontFamily: 'CupertinoSystemDisplay',
                  color: Colors.white,
                  fontSize: 22.0,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: SMALL_SPACE),
              Text(
                localizations.permission_photo_denied_message(APP_NAME),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'CupertinoSystemText',
                  color: Colors.white70,
                  height: 1.4,
                  fontSize: 15.0,
                ),
              ),
              const SizedBox(height: LARGE_SPACE),
              FilledButton(
                onPressed: () => _askPermission(context),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF121212),
                  minimumSize: const Size(200.0, 52.0),
                ),
                child: Text(localizations.permission_photo_denied_button),
              ),
              // The search and gallery still work without the camera.
              const SizedBox(height: 200.0),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _askPermission(BuildContext context) {
    return Provider.of<PermissionListener>(
      context,
      listen: false,
    ).askPermission(
      onRationaleNotAvailable: () async {
        return showCupertinoDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            final AppLocalizations localizations = AppLocalizations.of(context);
            return CupertinoAlertDialog(
              title: Text(localizations.permission_photo_denied_dialog_settings_title),
              content: Text(localizations.permission_photo_denied_dialog_settings_message),
              actions: <Widget>[
                CupertinoDialogAction(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(localizations.permission_photo_denied_dialog_settings_button_cancel),
                ),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(localizations.permission_photo_denied_dialog_settings_button_open),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
