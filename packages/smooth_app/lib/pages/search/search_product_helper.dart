import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/database/dao_string_list.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/helpers/analytics_helper.dart';
import 'package:smooth_app/helpers/barcode_utils.dart';
import 'package:smooth_app/helpers/provider_helper.dart';
import 'package:smooth_app/helpers/string_extension.dart';
import 'package:smooth_app/l10n/app_localizations.dart';
import 'package:smooth_app/pages/navigator/app_navigator.dart';
import 'package:smooth_app/pages/product/common/search_helper.dart';
import 'package:smooth_app/pages/search/live_search_suggestions.dart';
import 'package:smooth_app/pages/search/product_search_results_view.dart';
import 'package:smooth_app/services/product_search_service.dart';

/// Search helper dedicated to product search.
/// 16/11: every search goes through the fast engine with Owned's own
/// results page; a barcode opens Owned's product loader. Open Food Facts'
/// classic search page, product-type switch and dialogs are gone.
class SearchProductHelper extends SearchHelper {
  SearchProductHelper();

  @override
  String get historyKey => DaoStringList.keySearchProductHistory;

  @override
  String getHintText(final AppLocalizations appLocalizations) => 'Brand, product or barcode';

  @override
  String getHelpText(final AppLocalizations appLocalizations) =>
      'Type a brand to see who owns it, or a product name or barcode.';

  @override
  Widget? buildLiveSuggestions(
    final BuildContext context,
    final String text, {
    required final TextEditingController controller,
    required final FocusNode focusNode,
  }) {
    if (text.trim().isEmpty) {
      return null;
    }
    return LiveSearchSuggestions(
      text: text,
      history: getAllQueries(context.read<LocalDatabase>()),
      onSearch: (String query) {
        controller.text = query;
        searchWithController(context, query, controller, focusNode);
      },
      onCategory: (CategorySuggestion category) {
        focusNode.unfocus();
        controller.text = category.name;
        emit(
          SearchQuery(
            search: category.name,
            widget: ProductSearchResultsView(
              key: ValueKey<String>('category:${category.tag}'),
              query: category.name,
              category: category,
            ),
          ),
        );
      },
    );
  }

  @override
  void search(
    BuildContext context,
    String query, {
    required SearchQueryCallback searchQueryCallback,
  }) {
    query = query.trim();
    if (query.isEmpty) {
      return;
    } else if (query.removeSpaces().hasOnlyDigits()) {
      // This maybe a barcode => remove spaces within the string
      query = query.removeSpaces();
    }

    final LocalDatabase localDatabase = context.read<LocalDatabase>();
    addQuery(localDatabase, query);

    if (query.isBarcode) {
      AnalyticsHelper.trackSearch(search: query, searchCategory: 'barcode', searchCount: 1);
      AppNavigator.of(context).push(AppRoutes.PRODUCT_LOADER(query));
      return;
    }
    emit(
      SearchQuery(
        search: query,
        widget: ProductSearchResultsView(key: ValueKey<String>('text:$query'), query: query),
      ),
    );
  }
}
