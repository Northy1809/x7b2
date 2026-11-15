import 'package:flutter/material.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/pages/companies/companies_page.dart';
import 'package:smooth_app/pages/home/owned_home_page.dart';
import 'package:smooth_app/pages/homepage/homepage.dart';
import 'package:smooth_app/pages/page_manager.dart';
import 'package:smooth_app/pages/profile/owned_profile_page.dart';
import 'package:smooth_app/pages/search/search_page.dart';
import 'package:smooth_app/pages/search/search_product_helper.dart';

class TabNavigator extends StatelessWidget {
  const TabNavigator({
    required this.navigatorKey,
    required this.tabItem,
    this.visible = true,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final BottomNavigationTab tabItem;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return EMPTY_WIDGET;
    }

    final Widget child = switch (tabItem) {
      BottomNavigationTab.HomePage => const HomePage(),
      // History lives behind "See all" on the home page now.
      BottomNavigationTab.List => const CompaniesPage(),
      BottomNavigationTab.Profile => const OwnedProfilePage(),
      BottomNavigationTab.Scan => const OwnedHomePage(),
      BottomNavigationTab.Search => SearchPage(
        SearchProductHelper(),
        autofocus: false,
        showBackButton: false,
      ),
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic res) async {
        if (didPop) {
          return;
        }

        if (navigatorKey.currentState!.canPop()) {
          navigatorKey.currentState!.pop(res);
        }
      },
      child: Navigator(
        key: navigatorKey,
        onGenerateRoute: (RouteSettings routeSettings) {
          return MaterialPageRoute<dynamic>(
            builder: (BuildContext context) => child,
          );
        },
      ),
    );
  }
}
