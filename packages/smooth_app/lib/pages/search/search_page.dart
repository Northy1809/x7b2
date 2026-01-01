import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/generic_lib/widgets/smooth_back_button.dart';
import 'package:smooth_app/helpers/provider_helper.dart';
import 'package:smooth_app/l10n/app_localizations.dart';
import 'package:smooth_app/pages/product/common/search_helper.dart';
import 'package:smooth_app/pages/product/common/search_preloaded_item.dart';
import 'package:smooth_app/pages/search/search_history_view.dart';
import 'package:smooth_app/widgets/cal_ui.dart';
import 'package:smooth_app/widgets/will_pop_scope.dart';

/// The search, as a Cal AI page (16/11): a big "Search" title on the tab
/// (a round back arrow when pushed), Cal AI's grey search field, then the
/// recent searches and popular brands, live suggestions while typing, or
/// the results.
/// It can opened directly with the [SearchPageExtra] constructor.
/// From GoRouter, the page is named [AppRoutes.SEARCH] and we need to pass a
/// [SearchPageExtra] object for extras.
class SearchPage extends StatefulWidget {
  const SearchPage(
    this.searchHelper, {
    this.preloadedList,
    this.autofocus = true,
    this.heroTag,
    this.backButtonType,
    this.showBackButton = true,
    this.initialQuery,
  });

  SearchPage.fromExtra(SearchPageExtra extra)
    : this(
        extra.searchHelper,
        preloadedList: extra.preloadedList,
        autofocus: extra.autofocus ?? true,
        heroTag: extra.heroTag,
        backButtonType: extra.backButtonType,
      );

  final SearchHelper searchHelper;
  final List<SearchPreloadedItem>? preloadedList;
  final bool autofocus;

  /// Kept for callers; the Cal field has no hero animation.
  final String? heroTag;
  final BackButtonType? backButtonType;

  /// False when the page is a root tab: nothing to go back to.
  final bool showBackButton;

  /// Runs this search right away (e.g. a brand tapped on a product page).
  final String? initialQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class SearchPageExtra {
  const SearchPageExtra({
    required this.searchHelper,
    this.preloadedList,
    this.autofocus,
    this.heroTag,
    this.backButtonType,
  });

  final SearchHelper searchHelper;
  final List<SearchPreloadedItem>? preloadedList;

  /// If not passed, will default to [false]
  final bool? autofocus;
  final String? heroTag;

  final BackButtonType? backButtonType;
}

class _SearchPageState extends State<SearchPage> {
  // https://github.com/openfoodfacts/smooth-app/pull/2219
  final TextEditingController _searchTextController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _searchTextController.addListener(_onTextChanged);
    final String? query = widget.initialQuery;
    if (query != null && query.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _search(query);
        _searchFocusNode.unfocus();
      });
    }
  }

  void _search(final String query) => widget.searchHelper.searchWithController(
    context,
    query,
    _searchTextController,
    _searchFocusNode,
  );

  /// Editing the text after a search goes back to the live suggestions;
  /// clearing it goes back to the recent searches.
  void _onTextChanged() {
    final SearchQuery? current = widget.searchHelper.value;
    if (current == null) {
      return;
    }
    final String text = _searchTextController.text.trim();
    if (text.isEmpty || (_searchFocusNode.hasFocus && text != current.search.trim())) {
      widget.searchHelper.value = null;
    }
  }

  @override
  void dispose() {
    _searchTextController.removeListener(_onTextChanged);
    _searchTextController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// The back arrow first leaves the results, then the page.
  void _back() {
    if (widget.searchHelper.value != null) {
      setState(() => widget.searchHelper.value = null);
      _searchTextController.clear();
      return;
    }
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations appLocalizations = AppLocalizations.of(context);
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    return WillPopScope2(
      onWillPop: () async {
        /// For the world view, we need to intercept the back button from here
        /// See below for the custom [Navigator]
        if (widget.searchHelper.value != null) {
          setState(() => widget.searchHelper.value = null);
          return (false, null);
        }
        return (true, null);
      },
      child: MultiProvider(
        providers: <ChangeNotifierProvider<dynamic>>[
          ChangeNotifierProvider<TextEditingController>.value(value: _searchTextController),
          ChangeNotifierProvider<SearchHelper>.value(value: widget.searchHelper),
        ],
        child: Scaffold(
          appBar: widget.showBackButton ? CalTopBar(title: 'Search', onBack: _back) : null,
          body: Padding(
            padding: EdgeInsetsDirectional.only(top: widget.showBackButton ? 0.0 : pad.top),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (!widget.showBackButton)
                  const Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(kCalSide, 14.0, kCalSide, 0.0),
                    child: CalLargeTitle('Search'),
                  ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(kCalSide, 12.0, kCalSide, 8.0),
                  child: ValueNotifierListener<SearchHelper, SearchQuery?>(
                    listener: _onSearchChanged,
                    child: CalSearchField(
                      controller: _searchTextController,
                      focusNode: _searchFocusNode,
                      autofocus: widget.autofocus,
                      hint: widget.searchHelper.getHintText(appLocalizations),
                      onSubmitted: _search,
                    ),
                  ),
                ),
                Expanded(
                  child: Consumer2<SearchHelper, TextEditingController>(
                    builder: (BuildContext context, SearchHelper searchHelper, TextEditingController controller, _) {
                      /// Suggestions while typing, before a search is submitted
                      final Widget? live = searchHelper.value == null
                          ? searchHelper.buildLiveSuggestions(
                              context,
                              controller.text,
                              controller: _searchTextController,
                              focusNode: _searchFocusNode,
                            )
                          : null;
                      if (live != null) {
                        return live;
                      }

                      /// The recent searches when there is no search
                      if (searchHelper.value == null) {
                        return SearchHistoryView(
                          focusNode: _searchFocusNode,
                          onTap: _search,
                          searchHelper: widget.searchHelper,
                          preloadedList: widget.preloadedList ?? <SearchPreloadedItem>[],
                        );
                      }

                      /// A custom [Navigator] is used to intercept the World
                      /// results to be embedded in this part of the screen and
                      /// not on a new one.
                      return Navigator(
                        key: _navigatorKey,
                        pages: <MaterialPage<dynamic>>[MaterialPage<void>(child: searchHelper.value!.widget)],
                        onDidRemovePage: (_) {
                          /// Mandatory to provide this method
                          /// The event is intercepted by the [WillPopScope2]
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onSearchChanged(BuildContext context, SearchQuery? oldValue, SearchQuery? value) {
    if (value != null && _searchTextController.text != value.search) {
      /// Update the search field when an history item is selected
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchTextController.text = value.search;
      });
    } else if (oldValue != null) {
      /// If we were on the world results, ensure to go back to
      /// the main list of results
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigatorKey.currentState?.popUntil((Route<dynamic> route) {
          return route.isFirst;
        });
      });
    }
  }
}
