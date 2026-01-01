import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/l10n/app_localizations.dart';
import 'package:smooth_app/pages/navigator/app_navigator.dart';
import 'package:smooth_app/pages/owner/moral_score_page.dart';
import 'package:smooth_app/pages/owner/owner_page.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/widgets/company_logo.dart';

import '../tests_utils/local_database_mock.dart';

/// 18/11: every moral score opens one page that explains it: the score in
/// one sentence, the record as a bar, the categories as filters and the
/// scandals on a timeline, each opening its story and sources.
const int _year = 2026;

Map<String, dynamic> _source(final String host) => <String, dynamic>{
  'title': 'Report on $host',
  'url': 'https://www.$host/a',
};

EthicsDb _ethics() => EthicsDb.fromJson(<String, dynamic>{
  'updated': '2026-11-09',
  'companies': <dynamic>[
    <String, dynamic>{
      'id': 'acme',
      'name': 'Acme Foods',
      'about': 'A food company.',
      'issues': <dynamic>[
        <String, dynamic>{
          'cat': 'people',
          'sev': 3,
          'year': 2024,
          'title': 'Child labour in cocoa',
          'text': 'Reports found children on farms it buys from.',
          'sources': <dynamic>[_source('reuters.com'), _source('bbc.co.uk')],
        },
        <String, dynamic>{
          'cat': 'climate',
          'sev': 2,
          'year': 2022,
          'title': 'Plastic polluter',
          'text': 'Among the top plastic polluters.',
          'sources': <dynamic>[_source('breakfreefromplastic.org')],
        },
        <String, dynamic>{
          'cat': 'conduct',
          'sev': 1,
          'year': 2001,
          'title': 'Old price cartel',
          'text': 'Fined for a price cartel.',
          'sources': <dynamic>[_source('ec.europa.eu')],
        },
      ],
      'good': <dynamic>[
        <String, dynamic>{
          'cat': 'climate',
          'title': 'Science-based climate targets',
          'text': 'Approved targets.',
          'sources': <dynamic>[_source('sciencebasedtargets.org')],
        },
      ],
    },
  ],
});

OwnershipLocalDb _db() => OwnershipLocalDb.fromJson(<String, dynamic>{
  'strings': <String>['Acme Foods'],
  'brands': <String, dynamic>{},
  'by_country': <String, dynamic>{},
  'prefix': <String, dynamic>{},
  'emb': <String, dynamic>{},
  'companies': <String, dynamic>{},
  'top': <String, dynamic>{},
});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LogoIndex.instance.online = false;
    LogoIndex.instance.resetForTest();
  });

  void tallPhone(final WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 6000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Future<void> settle(final WidgetTester tester, {final int rounds = 10}) async {
    for (int i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> pump(final WidgetTester tester, final Widget home) async {
    await tester.pumpWidget(
      AppNavigator(
        child: ChangeNotifierProvider<LocalDatabase>.value(
          value: MockLocalDatabase(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: home,
          ),
        ),
      ),
    );
    await settle(tester);
  }

  EthicsScoreResult acme() => EthicsScore.compute(_ethics().companies.single, currentYear: _year);

  test('impact: severity, age and good practices', () {
    final List<EthicsItem> issues = _ethics().companies.single.issues;
    expect(EthicsScore.impact(issues[0], currentYear: _year), -45);
    expect(EthicsScore.impact(issues[1], currentYear: _year), -30);
    // 25 years old: 60 % of 15.
    expect(EthicsScore.impact(issues[2], currentYear: _year), -9);
    expect(EthicsScore.impact(_ethics().companies.single.good.single), EthicsScore.goodBonus);
  });

  test('timeline: newest year first', () {
    final List<(int?, List<EthicsItem>)> groups = ScandalTimeline.groups(_ethics().companies.single.issues);
    expect(groups.map(((int?, List<EthicsItem>) g) => g.$1), <int>[2024, 2022, 2001]);
  });

  testWidgets('the page explains the score and lists every case', (WidgetTester tester) async {
    tallPhone(tester);
    await pump(tester, MoralScorePage(result: acme(), ownerName: 'Acme Foods', db: _ethics(), currentYear: _year));
    expect(find.text('Acme Foods'), findsOneWidget);
    expect(find.text('3 documented cases, 1 very serious. 1 good practice.'), findsOneWidget);
    expect(find.text('Scandals and crises'), findsOneWidget);
    for (final String title in <String>['Child labour in cocoa', 'Plastic polluter', 'Old price cartel']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('2024'), findsOneWidget);
    expect(find.text('Older, counts less'), findsOneWidget);
    expect(find.text('What it does well'), findsOneWidget);
    expect(find.text('Science-based climate targets'), findsOneWidget);
  });

  testWidgets('a category card filters the cases', (WidgetTester tester) async {
    tallPhone(tester);
    await pump(tester, MoralScorePage(result: acme(), ownerName: 'Acme Foods', db: _ethics(), currentYear: _year));
    await tester.tap(find.bySemanticsLabel(RegExp(r'^People \d+ out of 100')));
    await settle(tester);
    expect(find.text('Child labour in cocoa'), findsOneWidget);
    expect(find.text('Plastic polluter'), findsNothing);
    // Tapping it again shows all of them.
    await tester.tap(find.bySemanticsLabel(RegExp(r'^People \d+ out of 100')));
    await settle(tester);
    expect(find.text('Plastic polluter'), findsOneWidget);
  });

  testWidgets('a case opens its story, what it costs and its sources', (WidgetTester tester) async {
    tallPhone(tester);
    await pump(tester, MoralScorePage(result: acme(), ownerName: 'Acme Foods', db: _ethics(), currentYear: _year));
    await tester.tap(find.text('Child labour in cocoa'));
    await settle(tester);
    expect(find.text('Takes 45 points off People & workers.'), findsOneWidget);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.textContaining('Report on reuters.com', findRichText: true), findsOneWidget);
  });

  testWidgets('not researched: says so', (WidgetTester tester) async {
    tallPhone(tester);
    await pump(tester, MoralScorePage(result: null, ownerName: 'small dairy', db: _ethics()));
    expect(find.text('Small dairy'), findsOneWidget);
    expect(find.textContaining('We have not researched Small dairy yet'), findsOneWidget);
    expect(find.text('Scandals and crises'), findsNothing);
  });

  testWidgets('company page: the score card and "See all" open the same page', (WidgetTester tester) async {
    tallPhone(tester);
    final OwnerPage page = OwnerPage(
      name: 'Acme Foods',
      localDb: () async => _db(),
      ethicsDb: () async => _ethics(),
      loadProducts: () async => <Product>[],
    );
    await pump(tester, page);
    expect(find.text('Child labour in cocoa'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Moral score \d+ out of 100')));
    await settle(tester);
    expect(find.byType(MoralScorePage), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await settle(tester);
    await tester.tap(find.text('See all 3 cases'));
    await settle(tester);
    expect(find.byType(MoralScorePage), findsOneWidget);
  });
}
