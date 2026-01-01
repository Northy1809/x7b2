import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_app/pages/product/product_page/overview/health_score_page.dart';
import 'package:smooth_app/services/health_score.dart';

/// 20/11: the health score has the same kind of page as the moral score:
/// the score in one sentence, its parts as bars and cards that open what
/// they mean and their sources, the nutrients, and how it is made.
HealthScoreResult _nesquikLike() => HealthScore.compute(
  nutriscoreGrade: 'd',
  novaGroup: 4,
  additiveTags: const <String>['en:e322'],
  nutrientLevels: const <String, String>{'sugars': 'high', 'fat': 'low'},
  per100g: const <String, double?>{'sugars': 76.0, 'fat': 3.1},
);

void main() {
  void tallPhone(final WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 7000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pump(final WidgetTester tester, final HealthScoreResult r) async {
    await tester.pumpWidget(MaterialApp(home: HealthScorePage(result: r, productName: 'Nesquik')));
    await tester.pump(const Duration(seconds: 2));
  }

  test('verdict names what holds the score back and what helps it', () {
    expect(HealthScorePage.verdict(_nesquikLike()), 'Held back by nutrition and processing. Strong on additives.');
    final HealthScoreResult missing = HealthScore.compute(nutriscoreGrade: null);
    expect(HealthScorePage.verdict(missing), missing.missingReason);
  });

  testWidgets('the page shows the score, every part and the nutrients', (WidgetTester tester) async {
    tallPhone(tester);
    final HealthScoreResult r = _nesquikLike();
    await pump(tester, r);
    expect(find.text('Nesquik'), findsOneWidget);
    expect(find.text('What goes into it'), findsOneWidget);
    for (final String part in <String>['Nutrition', 'Additives', 'Processing', 'Organic']) {
      // Once as a bar in the score card, once on its card.
      expect(find.text(part), findsNWidgets(2), reason: part);
    }
    expect(find.text('Nutri-Score D'), findsOneWidget);
    expect(find.text('High in sugar'), findsOneWidget);
    expect(find.text('Low in fat'), findsOneWidget);
    expect(find.text('How we score health'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Health score ${r.score} out of 100')), findsOneWidget);
  });

  testWidgets('a part opens what it gives and its sources', (WidgetTester tester) async {
    tallPhone(tester);
    await pump(tester, _nesquikLike());
    await tester.tap(find.text('Nutri-Score D'));
    await tester.pumpAndSettle();
    expect(find.text('Gives 15 of the 60 points for nutrition.'), findsOneWidget);
    expect(find.text('Sources'), findsWidgets);
  });

  testWidgets('no score: says why, still shows the nutrients', (WidgetTester tester) async {
    tallPhone(tester);
    final HealthScoreResult r = HealthScore.compute(
      nutriscoreGrade: null,
      nutrientLevels: const <String, String>{'sugars': 'high'},
    );
    await pump(tester, r);
    expect(find.text('No score'), findsOneWidget);
    expect(find.text(r.missingReason!), findsOneWidget);
    expect(find.text('What goes into it'), findsNothing);
    expect(find.text('High in sugar'), findsOneWidget);
  });
}
