import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_app/data_models/preferences/user_preferences.dart';
import 'package:smooth_app/data_models/product_preferences.dart';
import 'package:smooth_app/data_models/user_management_provider.dart';
import 'package:smooth_app/pages/product/product_page/tabs/ownership/ownership_result_view.dart';
import 'package:smooth_app/services/ownership_service.dart';
import 'package:smooth_app/themes/color_provider.dart';
import 'package:smooth_app/themes/contrast_provider.dart';
import 'package:smooth_app/themes/theme_provider.dart';

import '../../tests_utils/mocks.dart';

/// These widgets render [ProductPageTitle] section headers, which read the
/// app's real [ThemeProvider]/[SmoothColorsThemeExtension] from context (see
/// `product_page_title.dart`) — a bare `MaterialApp` doesn't provide either,
/// so pumping one directly throws a null-check error before layout even
/// starts. [MockSmoothApp] (`tests_utils/mocks.dart`) is the app's own
/// fixture for exactly this: the same provider stack `scan_news_card_test.dart`
/// uses for widgets with the same dependency.
Future<void> _pumpOwnershipWidget(
  final WidgetTester tester,
  final Widget child,
) async {
  final UserPreferences userPreferences =
      await UserPreferences.getUserPreferences();

  late ProductPreferences productPreferences;
  productPreferences = ProductPreferences(
    ProductPreferencesSelection(
      setImportance: userPreferences.setImportance,
      getImportance: userPreferences.getImportance,
      notify: () => productPreferences.notifyListeners(),
    ),
  );
  await productPreferences.init(PlatformAssetBundle());
  await userPreferences.init(productPreferences);

  await tester.pumpWidget(
    MockSmoothApp(
      userPreferences,
      UserManagementProvider(),
      productPreferences,
      ThemeProvider(userPreferences),
      TextContrastProvider(userPreferences),
      ColorProvider(userPreferences),
      Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  // Not `pumpAndSettle`: `OwnershipLoadingView` contains a
  // `CircularProgressIndicator`, which animates forever and would make
  // `pumpAndSettle` time out waiting for a frame that never stops scheduling.
  await tester.pump();
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues(mockSharedPreferences());
  });

  group('OwnershipChainView', () {
    testWidgets('renders every link in the chain once', (
      final WidgetTester tester,
    ) async {
      await _pumpOwnershipWidget(
        tester,
        const OwnershipChainView(
          chain: <String>['Oreo', 'Nabisco', 'Mondelez International'],
        ),
      );
      expect(find.text('Oreo'), findsOneWidget);
      expect(find.text('Nabisco'), findsOneWidget);
      expect(find.text('Mondelez International'), findsOneWidget);
    });

    testWidgets('renders a single-link chain without crashing', (
      final WidgetTester tester,
    ) async {
      await _pumpOwnershipWidget(
        tester,
        const OwnershipChainView(chain: <String>['Independent Brand']),
      );
      expect(find.text('Independent Brand'), findsOneWidget);
    });
  });

  group('OwnershipSourceLine', () {
    testWidgets('labels a Wikidata source', (final WidgetTester tester) async {
      await _pumpOwnershipWidget(
        tester,
        const OwnershipSourceLine(source: BrandOwnerSource.wikidata),
      );
      expect(find.textContaining('Wikidata'), findsOneWidget);
    });

    testWidgets('labels an AI-fallback source as user-confirmed', (
      final WidgetTester tester,
    ) async {
      await _pumpOwnershipWidget(
        tester,
        const OwnershipSourceLine(source: BrandOwnerSource.aiFallback),
      );
      expect(find.textContaining('confirmed'), findsOneWidget);
    });
  });

  group('EthicsRatingSection', () {
    testWidgets('shows an honest empty state when nothing is curated yet', (
      final WidgetTester tester,
    ) async {
      await _pumpOwnershipWidget(
        tester,
        const EthicsRatingSection(
          ownerCompany: 'Mondelez International',
          ethics: null,
        ),
      );
      expect(
        find.textContaining('No ethics rating yet'),
        findsOneWidget,
      );
      expect(find.textContaining('Mondelez International'), findsOneWidget);
    });

    testWidgets('shows the rationale and a tappable source link when curated', (
      final WidgetTester tester,
    ) async {
      await _pumpOwnershipWidget(
        tester,
        EthicsRatingSection(
          ownerCompany: 'Mondelez International',
          ethics: EthicsRating(
            category: 'contested',
            rationale: 'Nogle kontroversielle praksisser.',
            sourceUrl: 'https://example.com/kilde',
          ),
        ),
      );
      expect(find.text('contested'), findsOneWidget);
      expect(
        find.text('Nogle kontroversielle praksisser.'),
        findsOneWidget,
      );
      expect(find.text('Source'), findsOneWidget);
    });

    testWidgets('renders an unrecognised category without crashing', (
      final WidgetTester tester,
    ) async {
      await _pumpOwnershipWidget(
        tester,
        EthicsRatingSection(
          ownerCompany: 'Some Company',
          ethics: EthicsRating(
            category: 'noget helt andet',
            rationale: 'En note uden kendt kategori-nøgleord.',
          ),
        ),
      );
      expect(find.text('noget helt andet'), findsOneWidget);
    });
  });

  group('OwnershipLoadingView', () {
    testWidgets('shows the given label under the spinner', (
      final WidgetTester tester,
    ) async {
      await _pumpOwnershipWidget(
        tester,
        const OwnershipLoadingView(label: 'Læser billedet…'),
      );
      expect(find.text('Læser billedet…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
