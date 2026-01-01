import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/data_models/preferences/user_preferences.dart';
import 'package:smooth_app/helpers/provider_helper.dart';
import 'package:smooth_app/pages/companies/avoid_list.dart';
import 'package:smooth_app/pages/preferences/user_preferences_dev_mode.dart';
import 'package:smooth_app/pages/scan/carousel/scan_carousel_manager.dart';
import 'package:smooth_app/pages/scan/scan_page.dart';
import 'package:smooth_app/services/pending_scans.dart';
import 'package:smooth_app/widgets/plus_menu.dart';
import 'package:smooth_app/widgets/smooth_navigation_bar.dart';
import 'package:smooth_app/widgets/tab_navigator.dart';
import 'package:smooth_app/widgets/will_pop_scope.dart';

enum BottomNavigationTab { Scan, HomePage, Search, List, Profile }

/// Here the different tabs in the bottom navigation bar are taken care of,
/// so that they are stateful, that is not only things like the scroll position
/// but also keeping the navigation on the different tabs.
///
/// Scan Page is an exception here as it needs a little more work so that the
/// camera is not kept unnecessarily kept active.
class PageManager extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => PageManagerState();
}

class PageManagerState extends State<PageManager> {
  static const List<BottomNavigationTab> _pageKeys = BottomNavigationTab.values;

  static final Map<BottomNavigationTab, GlobalKey<NavigatorState>>
  _navigatorKeys = <BottomNavigationTab, GlobalKey<NavigatorState>>{
    for (final BottomNavigationTab tab in BottomNavigationTab.values)
      tab: GlobalKey<NavigatorState>(),
  };

  BottomNavigationTab? _currentPage;

  /// The + menu is showing.
  bool _plusOpen = false;

  void _closePlus() {
    if (_plusOpen) {
      setState(() => _plusOpen = false);
    }
  }

  PendingScan? _lastPending;

  /// A photo started reading: show it on the home page, as Cal AI does.
  void _onPending() {
    final List<PendingScan> scans = PendingScans.instance.scans;
    final PendingScan? first = scans.isEmpty ? null : scans.first;
    if (first != null && first != _lastPending && mounted) {
      _plusOpen = false;
      _selectTab(BottomNavigationTab.Scan, BottomNavigationTab.Scan.index);
    }
    _lastPending = first;
  }

  @override
  void initState() {
    super.initState();
    PendingScans.instance.addListener(_onPending);
  }

  @override
  void dispose() {
    PendingScans.instance.removeListener(_onPending);
    super.dispose();
  }
  bool? _useNewHomePage;
  late List<Widget> _tabs;

  /// Switches to [tab] from anywhere inside the tabs (e.g. the home page's
  /// "Average moral score" opens Companies). Does nothing outside them.
  static void showTab(final BuildContext context, final BottomNavigationTab tab) =>
      context.findAncestorStateOfType<PageManagerState>()?._selectTab(tab, tab.index);

  void _selectTab(BottomNavigationTab tabItem, int index) {
    if (tabItem == _currentPage) {
      _navigatorKeys[tabItem]!.currentState!.popUntil(
        (Route<dynamic> route) => route.isFirst,
      );
    } else {
      setState(() {
        _currentPage = _pageKeys[index];
      });
    }
  }

  void _generateTabsIfNecessary(bool showNewHomePage) {
    if (_useNewHomePage == showNewHomePage) {
      return;
    }

    _useNewHomePage = showNewHomePage;

    _tabs = <Widget>[
      TabNavigator(
        navigatorKey: _navigatorKeys[BottomNavigationTab.Scan]!,
        tabItem: BottomNavigationTab.Scan,
        visible: !showNewHomePage,
      ),
      TabNavigator(
        navigatorKey: _navigatorKeys[BottomNavigationTab.HomePage]!,
        tabItem: BottomNavigationTab.HomePage,
        visible: showNewHomePage,
      ),
      TabNavigator(
        navigatorKey: _navigatorKeys[BottomNavigationTab.Search]!,
        tabItem: BottomNavigationTab.Search,
      ),
      TabNavigator(
        navigatorKey: _navigatorKeys[BottomNavigationTab.List]!,
        tabItem: BottomNavigationTab.List,
      ),
      TabNavigator(
        navigatorKey: _navigatorKeys[BottomNavigationTab.Profile]!,
        tabItem: BottomNavigationTab.Profile,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bool showNewHomePage = _showNewHomePage(
      context.watch<UserPreferences>(),
    );

    /// Temp fix
    _generateTabsIfNecessary(showNewHomePage);

    _currentPage ??= showNewHomePage
        ? BottomNavigationTab.HomePage
        : BottomNavigationTab.Scan;

    final ExternalScanCarouselManagerState carouselManager =
        ExternalScanCarouselManager.watch(context);

    if (carouselManager.forceShowScannerTab) {
      _currentPage = showNewHomePage
          ? BottomNavigationTab.HomePage
          : BottomNavigationTab.Scan;
    }

    final Widget bar = SmoothNavigationBar(
      destinations: <SmoothNavigationDestination>[
        SmoothNavigationDestination(
          icon: const Icon(CupertinoIcons.house),
          selectedIcon: const Icon(CupertinoIcons.house_fill),
          label: 'Home',
          visible: !showNewHomePage,
        ),
        SmoothNavigationDestination(
          icon: const Icon(CupertinoIcons.house),
          selectedIcon: const Icon(CupertinoIcons.house_fill),
          label: 'Home',
          visible: showNewHomePage,
        ),
        const SmoothNavigationDestination(
          icon: Icon(CupertinoIcons.search),
          selectedIcon: Icon(CupertinoIcons.search, weight: 700),
          label: 'Search',
        ),
        const SmoothNavigationDestination(
          icon: Icon(CupertinoIcons.chart_bar),
          selectedIcon: Icon(CupertinoIcons.chart_bar_fill),
          label: 'Companies',
        ),
        const SmoothNavigationDestination(
          icon: Icon(CupertinoIcons.person),
          selectedIcon: Icon(CupertinoIcons.person_fill),
          label: 'Profile',
        ),
      ],
      selectedIndex: _currentPage!.index,
      onDestinationSelected: (int index) {
        _closePlus();
        _selectTab(_pageKeys[index], index);
      },
      onPlus: () => setState(() => _plusOpen = !_plusOpen),
      plusOpen: _plusOpen,
    );
    return WillPopScope2(
      onWillPop: () async {
        if (_plusOpen) {
          _closePlus();
          return (false, null);
        }
        final bool isFirstRouteInCurrentTab = !_navigatorKeys[_currentPage]!
            .currentState!
            .canPop();

        if (isFirstRouteInCurrentTab) {
          if (_currentPage != BottomNavigationTab.Scan) {
            _selectTab(
              BottomNavigationTab.Scan,
              BottomNavigationTab.Scan.index,
            );
            return (false, null);
          } else {
            /// Exit the app
            return (true, null);
          }
        }

        // let system handle back button if we're on the first route
        return (false, null);
      },
      child: Scaffold(
        extendBody: true,
        body: Stack(
          children: <Widget>[
            Provider<BottomNavigationTab>.value(
              value: _currentPage!,
              child: _TabFade(
                index: _currentPage!.index,
                child: IndexedStack(index: _currentPage!.index, children: _tabs),
              ),
            ),
            PlusMenu(
              open: _plusOpen,
              onClose: _closePlus,
              actions: <PlusMenuAction>[
                PlusMenuAction(
                  icon: CupertinoIcons.viewfinder,
                  label: 'Scan product',
                  onTap: () => ScanPage.open(context),
                ),
                PlusMenuAction(
                  icon: CupertinoIcons.photo_on_rectangle,
                  label: 'From photos',
                  onTap: () => ScanPage.pickFromGallery(context),
                ),
                PlusMenuAction(
                  icon: CupertinoIcons.keyboard,
                  label: 'Who owns…?',
                  onTap: () => ScanPage.openSearch(context),
                ),
                PlusMenuAction(
                  icon: CupertinoIcons.nosign,
                  label: 'Avoid list',
                  onTap: () => AvoidListPage.open(context),
                ),
              ],
            ),
          ],
        ),
        bottomNavigationBar: ConsumerFilter<UserPreferences>(
          buildWhen:
              (UserPreferences? previousValue, UserPreferences currentValue) =>
                  _isProd(currentValue) != (_isProd(previousValue)),
          builder:
              (BuildContext context, UserPreferences prefs, Widget? child) {
                if (_isProd(prefs)) {
                  return bar;
                } else {
                  return Banner(
                    message: 'TEST ENV',
                    location: BannerLocation.bottomEnd,
                    color: const Color(0xFF1E1A22),
                    child: bar,
                  );
                }
              },
          child: bar,
        ),
      ),
    );
  }

  bool _isProd(UserPreferences? userPreferences) =>
      userPreferences?.getFlag(
        UserPreferencesDevMode.userPreferencesFlagProd,
      ) ??
      true;

  // TODO(g123k): Remove once the Scan page is removed.
  bool _showNewHomePage(UserPreferences userPreferences) =>
      userPreferences.getFlag(
        UserPreferencesDevMode.userPreferencesFlagHomePageV2,
      ) ??
      false;
}

/// A new tab fades in while it grows from 98.5 % to full size, instead of
/// appearing at once (180 ms, ease-out).
class _TabFade extends StatefulWidget {
  const _TabFade({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<_TabFade> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 1.0,
  );
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void didUpdateWidget(final _TabFade old) {
    super.didUpdateWidget(old);
    final bool reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (old.index != widget.index && !reduced) {
      _c.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_t),
    child: ScaleTransition(
      scale: Tween<double>(begin: 0.985, end: 1.0).animate(_t),
      child: widget.child,
    ),
  );
}
