import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/helpers/haptics.dart';

/// The scan result layout (as in Cal AI, Yuka): the photo fills the top and
/// stays still; the answer is a sheet that pops up over it and slides up as
/// you scroll. Pulling the sheet down shows more of the photo.
///
/// The sheet's content is [slivers]; they scroll with the sheet's own
/// controller, given to [onScrollController] so a page can follow it.
class ScanSheetScaffold extends StatefulWidget {
  const ScanSheetScaffold({
    required this.photo,
    required this.slivers,
    this.title,
    this.leading,
    this.actions = const <Widget>[],
    this.bottomBar,
    this.sheetController,
    this.onScrollController,
    this.photoFraction = 0.42,
    this.animateIn = true,
    this.analyzing = false,
    this.liftPhoto = true,
    super.key,
  });

  /// The photo is a full-screen camera shot (not a packshot that places
  /// itself): it slides up as the sheet comes in.
  final bool liftPhoto;

  /// The photo is still being read: no sheet yet, a white line sweeps the
  /// photo and "Analyzing" shows. When it turns false the sheet pops up.
  final bool analyzing;

  /// Fills the screen behind the sheet; keep the subject in the top part.
  final Widget photo;
  final List<Widget> slivers;

  /// Shown over the photo once the sheet is pulled all the way up.
  final String? title;
  final Widget? leading;
  final List<Widget> actions;

  /// Pinned under the sheet ("Fix", "Done").
  final Widget? bottomBar;
  final DraggableScrollableController? sheetController;
  final ValueChanged<ScrollController>? onScrollController;

  /// How much of the screen the photo gets while the sheet rests.
  final double photoFraction;

  /// The sheet rises into place, like a result that pops up.
  final bool animateIn;

  static const double radius = 32.0;

  /// Height of the [bottomBar] area, without the safe area.
  static const double bottomBarHeight = 76.0;

  @override
  State<ScanSheetScaffold> createState() => _ScanSheetScaffoldState();
}

class _ScanSheetScaffoldState extends State<ScanSheetScaffold>
    with SingleTickerProviderStateMixin {
  late final DraggableScrollableController _sheet =
      widget.sheetController ?? DraggableScrollableController();
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
    value: widget.animateIn || widget.analyzing ? 0.0 : 1.0,
  );
  ScrollController? _reported;

  /// 0 while the sheet rests, 1 when it is all the way up.
  final ValueNotifier<double> _lift = ValueNotifier<double>(0.0);
  double _min = 0.5;
  double _max = 0.9;

  @override
  void initState() {
    super.initState();
    _sheet.addListener(_onSheet);
    // Created here, not lazily: a page that never shows the sheet would
    // otherwise first create its ticker in dispose().
    if (widget.animateIn && !widget.analyzing) {
      Haptics.success();
      _intro.forward();
    } else {
      _intro.stop();
    }
  }

  @override
  void didUpdateWidget(final ScanSheetScaffold old) {
    super.didUpdateWidget(old);
    if (old.analyzing && !widget.analyzing) {
      // The answer is in: the sheet rises with a two-beat tap.
      Haptics.success();
      _intro.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _sheet.removeListener(_onSheet);
    if (widget.sheetController == null) {
      _sheet.dispose();
    }
    _intro.dispose();
    _lift.dispose();
    super.dispose();
  }

  void _onSheet() {
    if (!_sheet.isAttached) {
      return;
    }
    final double range = _max - _min;
    _lift.value = range <= 0
        ? 0.0
        : ((_sheet.size - _min) / range).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final EdgeInsets padding = MediaQuery.paddingOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: Colors.black,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double h = constraints.maxHeight;
            // Capped, so a tall screen (iPad, big text) shows more answer.
            final double photo = math.min(
              math.max(h * widget.photoFraction, 240.0),
              math.min(440.0, h - 260.0),
            );
            final double bar = widget.bottomBar == null
                ? 0.0
                : ScanSheetScaffold.bottomBarHeight + padding.bottom;
            _min = ((h - photo + ScanSheetScaffold.radius) / h).clamp(
              0.2,
              0.95,
            );
            _max = math.max(_min, (h - padding.top - kToolbarHeight) / h);
            final double floor = math.max(0.2, _min - 0.12);
            // A camera shot slides up with the sheet, so what was in the
            // middle of the frame stays in view above the answer.
            final double shift = widget.liftPhoto
                ? math.max(0.0, h / 2 - (padding.top + photo / 2) - 16.0)
                : 0.0;
            return Stack(
              children: <Widget>[
                Positioned.fill(
                  child: shift == 0.0
                      ? widget.photo
                      : AnimatedBuilder(
                          animation: _intro,
                          builder: (BuildContext context, Widget? child) =>
                              Transform.translate(
                                offset: Offset(
                                  0.0,
                                  -shift *
                                      Curves.easeOutCubic.transform(
                                        _intro.value,
                                      ),
                                ),
                                child: child,
                              ),
                          child: widget.photo,
                        ),
                ),
                // The photo dims as the answer covers it.
                Positioned.fill(
                  child: IgnorePointer(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _lift,
                      builder: (_, double lift, _) => ColoredBox(
                        color: Colors.black.withValues(alpha: 0.45 * lift),
                      ),
                    ),
                  ),
                ),
                // Keeps the buttons readable on a white packshot.
                Positioned(
                  top: 0.0,
                  left: 0.0,
                  right: 0.0,
                  height: padding.top + kToolbarHeight + 24.0,
                  child: const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[Color(0x66000000), Color(0x00000000)],
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.analyzing)
                  const Positioned.fill(child: ScanningOverlay()),
                if (!widget.analyzing)
                AnimatedBuilder(
                  animation: _intro,
                  builder: (BuildContext context, Widget? child) {
                    final double t = Curves.easeOutCubic.transform(
                      _intro.value,
                    );
                    return FractionalTranslation(
                      translation: Offset(0.0, (1.0 - t) * 0.8),
                      child: child,
                    );
                  },
                  child: DraggableScrollableSheet(
                    controller: _sheet,
                    initialChildSize: _min,
                    minChildSize: floor,
                    maxChildSize: _max,
                    snap: true,
                    snapSizes: <double>[_min],
                    builder: (BuildContext context, ScrollController scroll) {
                      if (!identical(scroll, _reported)) {
                        _reported = scroll;
                        widget.onScrollController?.call(scroll);
                      }
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(ScanSheetScaffold.radius),
                          ),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 24.0,
                              offset: Offset(0.0, -4.0),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(ScanSheetScaffold.radius),
                          ),
                          child: CustomScrollView(
                            controller: scroll,
                            slivers: <Widget>[
                              const SliverToBoxAdapter(child: SheetHandle()),
                              ...widget.slivers,
                              SliverToBoxAdapter(
                                child: SizedBox(height: bar + LARGE_SPACE),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  top: padding.top,
                  left: 0.0,
                  right: 0.0,
                  height: kToolbarHeight,
                  child: _TopBar(
                    leading: widget.leading,
                    actions: widget.actions,
                    title: widget.title,
                    lift: _lift,
                  ),
                ),
                if (widget.bottomBar != null && !widget.analyzing)
                  Positioned(
                    left: 0.0,
                    right: 0.0,
                    bottom: 0.0,
                    child: AnimatedBuilder(
                      animation: _intro,
                      builder: (BuildContext context, Widget? child) =>
                          FractionalTranslation(
                            translation: Offset(
                              0.0,
                              1.0 -
                                  Curves.easeOutCubic.transform(_intro.value),
                            ),
                            child: child,
                          ),
                      child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.scaffoldBackgroundColor,
                        border: Border(
                          top: BorderSide(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.06,
                            ),
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsetsDirectional.fromSTEB(
                          LARGE_SPACE,
                          MEDIUM_SPACE,
                          LARGE_SPACE,
                          math.max(padding.bottom, MEDIUM_SPACE),
                        ),
                        child: widget.bottomBar,
                      ),
                    ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// While a photo is read: a thin white line sweeps down the frozen photo,
/// leaving a faint light wash behind it, and a frosted "Analyzing" pill sits
/// in the lower part of the screen, clear of the subject.
class ScanningOverlay extends StatefulWidget {
  const ScanningOverlay({this.label = 'Analyzing', super.key});

  final String label;

  @override
  State<ScanningOverlay> createState() => _ScanningOverlayState();
}

class _ScanningOverlayState extends State<ScanningOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool still = MediaQuery.disableAnimationsOf(context);
    final EdgeInsets padding = MediaQuery.paddingOf(context);
    return Semantics(
      liveRegion: true,
      label: '${widget.label}…',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final double top = padding.top + kToolbarHeight;
          final double bottom = c.maxHeight - padding.bottom - 120.0;
          return Stack(
            children: <Widget>[
              // A light dim, so the white line reads on any photo.
              const Positioned.fill(
                child: ColoredBox(color: Color(0x26000000)),
              ),
              if (!still)
                AnimatedBuilder(
                  animation: _c,
                  builder: (BuildContext context, _) {
                    final double t = Curves.easeInOutSine.transform(_c.value);
                    final double y = top + (bottom - top) * t;
                    final double fade = _c.value < 0.08
                        ? _c.value / 0.08
                        : _c.value > 0.92
                        ? (1.0 - _c.value) / 0.08
                        : 1.0;
                    return Stack(
                      children: <Widget>[
                        // The wash: brighter right behind the line.
                        Positioned(
                          left: 0.0,
                          right: 0.0,
                          top: math.max(top, y - 140.0),
                          height: math.min(140.0, y - top).clamp(0.0, 140.0),
                          child: Opacity(
                            opacity: fade,
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: <Color>[
                                    Color(0x00FFFFFF),
                                    Color(0x2EFFFFFF),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 18.0,
                          right: 18.0,
                          top: y - 1.5,
                          height: 3.0,
                          child: Opacity(
                            opacity: fade,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2.0),
                                gradient: const LinearGradient(
                                  colors: <Color>[
                                    Color(0x00FFFFFF),
                                    Color(0xFFFFFFFF),
                                    Color(0xFFFFFFFF),
                                    Color(0x00FFFFFF),
                                  ],
                                  stops: <double>[0.0, 0.18, 0.82, 1.0],
                                ),
                                boxShadow: const <BoxShadow>[
                                  BoxShadow(
                                    color: Color(0xAAFFFFFF),
                                    blurRadius: 14.0,
                                    spreadRadius: 1.0,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              Positioned(
                left: 0.0,
                right: 0.0,
                bottom: padding.bottom + 56.0,
                child: Center(child: _AnalyzingPill(label: widget.label)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AnalyzingPill extends StatelessWidget {
  const _AnalyzingPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26.0),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18.0, sigmaY: 18.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(26.0),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16.0, 12.0, 20.0, 12.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox.square(
                  dimension: 18.0,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Color(0xFF121212),
                  ),
                ),
                const SizedBox(width: 10.0),
                Text(
                  '$label…',
                  style: const TextStyle(
                    fontFamily: 'CupertinoSystemText',
                    fontSize: 16.0,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                    color: Color(0xFF121212),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The grab handle on top of a sheet.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsetsDirectional.only(top: 10.0, bottom: 6.0),
        width: 40.0,
        height: 5.0,
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(3.0),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.leading,
    required this.actions,
    required this.title,
    required this.lift,
  });

  final Widget? leading;
  final List<Widget> actions;
  final String? title;
  final ValueListenable<double> lift;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: SMALL_SPACE),
      child: Row(
        children: <Widget>[
          ?leading,
          Expanded(
            child: ValueListenableBuilder<double>(
              valueListenable: lift,
              builder: (_, double v, _) => Opacity(
                opacity: ((v - 0.8) * 5.0).clamp(0.0, 1.0),
                child: Text(
                  title ?? '',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 17.0,
                  ),
                ),
              ),
            ),
          ),
          ...actions,
          if (leading != null && actions.isEmpty) const SizedBox(width: 48.0),
        ],
      ),
    );
  }
}

/// A round, frosted button that reads on any photo (back, share, ...).
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.all(4.0),
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
          child: Material(
            color: Colors.black.withValues(alpha: 0.32),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: tooltip,
              onPressed: onPressed,
              icon: Icon(icon, color: Colors.white, size: 22.0),
            ),
          ),
        ),
      ),
    );
  }
}

/// The photo behind a sheet: a shot from the camera fills the screen; a
/// product packshot (usually on white) is shown whole in the visible part,
/// over a blurred copy of itself.
class ScanPhoto extends StatelessWidget {
  const ScanPhoto({
    this.image,
    this.packshot = false,
    this.visibleFraction = 0.42,
    this.placeholder,
    super.key,
  });

  final ImageProvider? image;

  /// A product's own photo rather than the user's camera shot.
  final bool packshot;
  final double visibleFraction;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = placeholder ?? const _PhotoPlaceholder();
    if (image == null) {
      return fallback;
    }
    if (!packshot) {
      return Image(
        image: image!,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double top = MediaQuery.paddingOf(context).top + kToolbarHeight;
        final double visible = math.min(constraints.maxHeight * visibleFraction, 440.0);
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 30.0, sigmaY: 30.0),
              child: Image(
                image: image!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
            ),
            const ColoredBox(color: Color(0x33000000)),
            Positioned(
              top: top,
              left: VERY_LARGE_SPACE,
              right: VERY_LARGE_SPACE,
              height: math.max(80.0, visible - top),
              child: Image(
                image: image!,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFFFFFF), Color(0xFFE9E7E2)],
        ),
      ),
      child: Align(
        alignment: Alignment(0.0, -0.45),
        child: Icon(
          Icons.shopping_basket_outlined,
          size: 72.0,
          color: Color(0x33121212),
        ),
      ),
    );
  }
}
