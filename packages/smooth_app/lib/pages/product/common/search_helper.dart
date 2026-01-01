import 'package:flutter/material.dart';
import 'package:smooth_app/database/dao_string_list.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/l10n/app_localizations.dart';

typedef SearchQueryCallback = void Function(String query);

/// Common "text-field + history" search helper.
/// Will emit a [SearchQuery] when a search is performed.
/// By default (with the [null] value), the history will be displayed.
abstract class SearchHelper extends ValueNotifier<SearchQuery?> {
  SearchHelper() : super(null);

  /// Action to perform for a search.
  @protected
  void search(
    BuildContext context,
    String query, {
    required SearchQueryCallback searchQueryCallback,
  });

  /// Key for [DaoStringList], used to store the latest X queries.
  @protected
  String get historyKey;

  /// Hint text for the search field.
  String getHintText(final AppLocalizations appLocalizations);

  /// A small message that will be displayed below the search bar
  String getHelpText(final AppLocalizations appLocalizations);

  /// An optional leading widget for the search bar.
  Widget? getLeadingWidget(BuildContext context) => null;

  /// Suggestions to show while the user types [text], before submitting.
  /// Null keeps the default (history) view.
  Widget? buildLiveSuggestions(
    final BuildContext context,
    final String text, {
    required final TextEditingController controller,
    required final FocusNode focusNode,
  }) => null;

  /// Returns all the previous queries, in reverse order.
  ///
  /// 18/11: a history that cannot be read (a damaged store) shows as empty;
  /// it must never stop the search itself.
  List<String> getAllQueries(final LocalDatabase localDatabase) {
    try {
      return DaoStringList(localDatabase).getAll(historyKey).reversed.toList();
    } catch (_) {
      return const <String>[];
    }
  }

  /// Adds a query to the history; the search runs even if this fails.
  Future<void> addQuery(
    final LocalDatabase localDatabase,
    final String query,
  ) async {
    try {
      await DaoStringList(localDatabase).add(historyKey, query);
    } catch (_) {
      // Not remembered, still searched.
    }
  }

  /// Removes a query from the history.
  Future<bool> removeQuery(
    final LocalDatabase localDatabase,
    final String query,
  ) async {
    try {
      return await DaoStringList(localDatabase).remove(historyKey, query);
    } catch (_) {
      return false;
    }
  }

  /// Typical search when we have a controller+focus. The keyboard goes
  /// down, so the results are not hidden behind it (17/11: a search started
  /// by a tap, not the keyboard's Search key, left it up).
  void searchWithController(
    BuildContext context,
    String query,
    TextEditingController controller,
    FocusNode focusNode,
  ) {
    focusNode.unfocus();
    search(
      context,
      query,
      searchQueryCallback: (String query) {
        controller.text = query;
        focusNode.requestFocus();
      },
    );
  }
}

class SearchQuery {
  const SearchQuery({required this.search, required this.widget})
    : assert(search.length > 0);

  final String search;
  final Widget widget;
}
