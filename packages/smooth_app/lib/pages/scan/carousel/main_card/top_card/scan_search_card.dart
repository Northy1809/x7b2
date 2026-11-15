import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/generic_lib/duration_constants.dart';
import 'package:smooth_app/generic_lib/widgets/owned_wordmark.dart';
import 'package:smooth_app/generic_lib/widgets/smooth_back_button.dart';
import 'package:smooth_app/l10n/app_localizations.dart';
import 'package:smooth_app/pages/navigator/app_navigator.dart';
import 'package:smooth_app/pages/product/product_page/new_product_header.dart';
import 'package:smooth_app/pages/product/product_type_extensions.dart';
import 'package:smooth_app/pages/search/search_field.dart';
import 'package:smooth_app/pages/search/search_icon.dart';
import 'package:smooth_app/pages/search/search_page.dart';
import 'package:smooth_app/pages/search/search_product_helper.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/themes/smooth_theme_colors.dart';
import 'package:smooth_app/themes/theme_provider.dart';
import 'package:smooth_app/widgets/text/text_extensions.dart';
import 'package:vector_graphics/vector_graphics.dart';
import 'package:visibility_detector/visibility_detector.dart';

class ScanSearchCard extends StatelessWidget {
  const ScanSearchCard({required this.expandedMode});

  /// Expanded is when this card is the only one (no tagline, no app review…)
  final bool expandedMode;

  @override
  Widget build(BuildContext context) {
    final Widget widget = Container(
      margin: const EdgeInsets.symmetric(vertical: VERY_SMALL_SPACE),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: ROUNDED_BORDER_RADIUS,
        border: Border.all(color: BrandColors.hairline),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(
          vertical: MEDIUM_SPACE,
          horizontal: LARGE_SPACE,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            OwnedWordmark(height: 44.0),
            SizedBox(height: VERY_SMALL_SPACE),
            Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(text: 'Scan any product to see '),
                  TextSpan(
                    text: 'who really owns it',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: '.'),
                ],
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                height: 1.5,
                fontSize: 15.0,
                color: BrandColors.muted,
              ),
            ),
            SizedBox(height: MEDIUM_SPACE),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: SMALL_SPACE),
              child: _ScanSearchBar(),
            ),
          ],
        ),
      ),
    );

    if (expandedMode) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.4,
        ),
        child: widget,
      );
    } else {
      return widget;
    }
  }

  static double computeMinSize(BuildContext context, {bool expanded = false}) {
    if (expanded) {
      return MediaQuery.sizeOf(context).height * 0.4;
    } else {
      return (MEDIUM_SPACE * 3) +
          (VERY_SMALL_SPACE * 3) +
          // Logo
          54.0 +
          // Text
          ((2 * DefaultTextStyle.of(context).style.fontSize!) * 1.3) *
              context.textScaler() +
          // Search bar
          SearchFieldUIHelper.SEARCH_BAR_HEIGHT +
          // Extra space
          VERY_LARGE_SPACE;
    }
  }
}

class _ScanSearchBar extends StatelessWidget {
  const _ScanSearchBar();

  static const String HERO_TAG = 'search_field';

  @override
  Widget build(BuildContext context) {
    final AppLocalizations localizations = AppLocalizations.of(context);

    final SmoothColorsThemeExtension theme = context
        .extension<SmoothColorsThemeExtension>();

    return Semantics(
      button: true,
      child: Hero(
        tag: HERO_TAG,
        child: Material(
          // ↑ Needed by the Hero Widget
          type: MaterialType.transparency,
          child: SizedBox(
            height: SearchFieldUIHelper.SEARCH_BAR_HEIGHT,
            child: InkWell(
              onTap: () => AppNavigator.of(context).push(
                AppRoutes.SEARCH(transition: ProductPageTransition.slideUp),
                extra: SearchPageExtra(
                  searchHelper: SearchProductHelper(),
                  autofocus: true,
                  heroTag: HERO_TAG,
                  backButtonType: BackButtonType.minimize,
                ),
              ),
              borderRadius: SearchFieldUIHelper.SEARCH_BAR_BORDER_RADIUS,
              child: Ink(
                decoration: SearchFieldUIHelper.decoration(context),
                child: Padding(
                  padding: const EdgeInsetsDirectional.all(1.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: SMALL_SPACE,
                        ),
                        child: Icon(
                          Icons.search_rounded,
                          color: context.lightTheme()
                              ? theme.primaryAccent
                              : theme.primaryUltraBlack,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          localizations.homepage_main_card_search_field_hint,
                          maxLines: 1,
                          textScaler: TextScaler.noScaling,
                          overflow: TextOverflow.ellipsis,
                          style: SearchFieldUIHelper.hintTextStyle,
                        ),
                      ),
                      const SearchBarIcon(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OxFLogosAnimation extends StatefulWidget {
  const OxFLogosAnimation();

  @override
  State<OxFLogosAnimation> createState() => _OxFLogosAnimationState();
}

class _OxFLogosAnimationState extends State<OxFLogosAnimation> {
  late Timer _timer;
  int _currentLogo = 0;

  @override
  void initState() {
    super.initState();
    _initTimer();
  }

  void _initTimer() {
    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      setState(() {
        _currentLogo = (_currentLogo + 1) % ProductType.values.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final ProductType productType = ProductType.values[_currentLogo];

    return VisibilityDetector(
      key: const Key('OxFLogosAnimationVisibilityDetector'),
      onVisibilityChanged: (VisibilityInfo info) {
        if (info.visibleFraction == 0.0) {
          _timer.cancel();
        } else if (!_timer.isActive) {
          _initTimer();
        }
      },
      child: AspectRatio(
        aspectRatio: 1.0,
        child: AnimatedSwitcher(
          duration: SmoothAnimationsDuration.medium,
          transitionBuilder: _transitionBuilder,
          child: KeyedSubtree(
            key: Key(productType.offTag),
            child: SvgPicture(
              AssetBytesLoader(productType.getIllustration()),
              width: 30.0,
            ),
          ),
        ),
      ),
    );
  }

  Widget _transitionBuilder(Widget child, Animation<double> animation) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(-0.5, 0.0),
        end: Offset.zero,
      ).animate(animation),
      child: FadeTransition(
        key: ValueKey<Key?>(child.key),
        opacity: animation,
        child: child,
      ),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }
}
