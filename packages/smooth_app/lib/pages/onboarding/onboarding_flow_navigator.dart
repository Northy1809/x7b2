import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/data_models/preferences/user_preferences.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/pages/navigator/app_navigator.dart';
import 'package:smooth_app/pages/onboarding/owned_onboarding_pages.dart';
import 'package:smooth_app/pages/onboarding/owned_setup_page.dart';
import 'package:smooth_app/pages/onboarding/permissions_page.dart';
import 'package:smooth_app/pages/onboarding/preferences_page.dart';
import 'package:smooth_app/pages/onboarding/welcome_page.dart';
import 'package:smooth_app/pages/page_manager.dart';
import 'package:smooth_app/pages/scan/carousel/scan_carousel_manager.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/smooth_scaffold.dart';
import 'package:smooth_app/widgets/will_pop_scope.dart';

enum OnboardingPage {
  NOT_STARTED,
  HOME_PAGE,
  WELCOME,
  HEALTH_CARD_EXAMPLE,
  ECO_CARD_EXAMPLE,
  PREFERENCES_PAGE,
  PERMISSIONS_PAGE,
  ONBOARDING_COMPLETE;

  /// Owned's flow: intro -> country -> the two scores -> setting up (Cal
  /// AI's percentage screen, in the old eco-card slot) -> camera. OFF's
  /// food-preferences page is skipped (indexes stay, because the last
  /// visited page is stored by index). Back from the camera skips the
  /// setup screen.
  OnboardingPage getPrevPage() => switch (this) {
    NOT_STARTED || HOME_PAGE => NOT_STARTED,
    WELCOME => HOME_PAGE,
    HEALTH_CARD_EXAMPLE => WELCOME,
    ECO_CARD_EXAMPLE || PREFERENCES_PAGE || PERMISSIONS_PAGE => HEALTH_CARD_EXAMPLE,
    ONBOARDING_COMPLETE => PERMISSIONS_PAGE,
  };

  OnboardingPage getNextPage() => switch (this) {
    NOT_STARTED => HOME_PAGE,
    HOME_PAGE => WELCOME,
    WELCOME => HEALTH_CARD_EXAMPLE,
    HEALTH_CARD_EXAMPLE => ECO_CARD_EXAMPLE,
    ECO_CARD_EXAMPLE || PREFERENCES_PAGE => PERMISSIONS_PAGE,
    PERMISSIONS_PAGE || ONBOARDING_COMPLETE => ONBOARDING_COMPLETE,
  };

  bool isOnboardingComplete() =>
      OnboardingPage.values.indexOf(this) == OnboardingPage.values.length - 1;

  bool isOnboardingNotStarted() => OnboardingPage.values.indexOf(this) == 0;

  Color getBackgroundColor() {
    switch (this) {
      case OnboardingPage.NOT_STARTED:
      case OnboardingPage.HOME_PAGE:
        return BrandColors.paper;
      case OnboardingPage.WELCOME:
        return BrandColors.paper;
      case OnboardingPage.HEALTH_CARD_EXAMPLE:
        return BrandColors.paper;
      case OnboardingPage.ECO_CARD_EXAMPLE:
        return BrandColors.paper;
      case OnboardingPage.PREFERENCES_PAGE:
        return BrandColors.paper;
      case OnboardingPage.PERMISSIONS_PAGE:
        return BrandColors.paper;
      case OnboardingPage.ONBOARDING_COMPLETE:
        // whatever, it's not used
        return Colors.black;
    }
  }

  Widget getPageWidget(BuildContext context) {
    final LocalDatabase localDatabase = context.read<LocalDatabase>();
    final Color backgroundColor = getBackgroundColor();
    switch (this) {
      case OnboardingPage.NOT_STARTED:
      case OnboardingPage.HOME_PAGE:
        return const OwnedIntroPage();
      case OnboardingPage.WELCOME:
        return WelcomePage(backgroundColor);
      case OnboardingPage.HEALTH_CARD_EXAMPLE:
        return _wrapWidgetInCustomBackNavigator(
          context,
          OwnedScoresIntroPage(backgroundColor),
        );
      case OnboardingPage.ECO_CARD_EXAMPLE:
        return _wrapWidgetInCustomBackNavigator(context, const OwnedSetupPage());
      case OnboardingPage.PREFERENCES_PAGE:
        return _wrapWidgetInCustomBackNavigator(
          context,
          PreferencesPage(localDatabase, backgroundColor),
        );
      case OnboardingPage.PERMISSIONS_PAGE:
        return _wrapWidgetInCustomBackNavigator(
          context,
          PermissionsPage(backgroundColor),
        );
      case OnboardingPage.ONBOARDING_COMPLETE:
        return ExternalScanCarouselManager(child: PageManager());
    }
  }

  Widget _wrapWidgetInCustomBackNavigator(
    BuildContext context,
    Widget widget,
  ) => WillPopScope2(
    onWillPop: () async => (false, null),
    // wrap the widget in [Builder] to allow navigation on the [context].
    child: Builder(
      builder: (BuildContext context) => SmoothBrightnessOverride(
        brightness: Brightness.dark,
        child: SmoothScaffold(body: widget),
      ),
    ),
  );
}

/// Decide which page to take the user to.
class OnboardingFlowNavigator {
  OnboardingFlowNavigator(this._userPreferences) {
    if (_historyOnboardingNav.isEmpty) {
      _historyOnboardingNav.add(_userPreferences.lastVisitedOnboardingPage);
    }
  }

  final UserPreferences _userPreferences;

  //used for recording history of onboarding pages navigated
  static final List<OnboardingPage> _historyOnboardingNav = <OnboardingPage>[];

  Future<void> navigateToPage(BuildContext context, OnboardingPage page) async {
    await _userPreferences.setLastVisitedOnboardingPage(page);
    _historyOnboardingNav.add(page);

    if (!context.mounted) {
      return;
    }

    if (page.isOnboardingComplete()) {
      AppNavigator.of(context)
        ..clearStack()
        ..pushReplacement(AppRoutes.HOME(redraw: true));
    } else {
      // Cal AI cross-fades from question to question (measured: about
      // 170 ms, then the choices rise in one by one).
      final PageRouteBuilder<void> route = PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (BuildContext context, _, _) => page.getPageWidget(context),
        transitionsBuilder: (_, Animation<double> a, _, Widget child) =>
            FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
      );
      await Navigator.of(context).push<void>(route);
    }
  }

  static bool isOnboardingPagedInHistory(OnboardingPage page) {
    bool exists = false;
    if (_historyOnboardingNav.isNotEmpty) {
      final int indexPage = _historyOnboardingNav.indexOf(page);
      exists = indexPage >= 0 && indexPage < (_historyOnboardingNav.length - 1);
    }
    return exists;
  }
}
