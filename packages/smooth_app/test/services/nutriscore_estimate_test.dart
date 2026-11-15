import 'package:flutter_test/flutter_test.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:smooth_app/services/health_score.dart';
import 'package:smooth_app/services/nutriscore_estimate.dart';

void main() {
  group('NutriScoreEstimate (2023 algorithm)', () {
    test('Nutella: 31 negative points, proteins not counted -> E', () {
      expect(
        NutriScoreEstimate.grade(
          categories: const <String>['en:spreads', 'en:sweet-spreads'],
          energyKJ: 2252,
          sugars: 56.3,
          fat: 30.9,
          saturatedFat: 10.6,
          salt: 0.107,
          fiber: 0,
          proteins: 6.3,
        ),
        'e',
      );
    });

    test('plain oats -> A', () {
      // energy 1550 kJ = 4, sugars 1 = 0, sat fat 1.3 = 1, salt 0 = 0: N = 5;
      // proteins 13 = 5, fibre 10 = 5: score -5.
      expect(
        NutriScoreEstimate.grade(
          categories: const <String>['en:cereals-and-potatoes', 'en:oat-flakes'],
          energyKJ: 1550,
          sugars: 1,
          saturatedFat: 1.3,
          salt: 0,
          fiber: 10,
          proteins: 13,
        ),
        'a',
      );
    });

    test('beverages use their own thresholds, water is A', () {
      // Cola: 180 kJ = 3, sugars 10.6 = 9 -> 12 -> E.
      expect(
        NutriScoreEstimate.grade(
          categories: const <String>['en:beverages', 'en:sodas', 'en:colas'],
          energyKJ: 180,
          sugars: 10.6,
          fat: 0,
          salt: 0,
          proteins: 0,
        ),
        'e',
      );
      // Same cola without sugar but with aspartame: 4 sweetener points -> C.
      expect(
        NutriScoreEstimate.grade(
          categories: const <String>['en:beverages', 'en:sodas', 'en:colas'],
          additives: const <String>['en:e951'],
          energyKJ: 1,
          sugars: 0,
          saturatedFat: 0,
          salt: 0,
          proteins: 0,
        ),
        'c',
      );
      expect(
        NutriScoreEstimate.grade(
          categories: const <String>['en:beverages', 'en:waters', 'en:spring-waters'],
          energyKJ: 0,
          sugars: 0,
          saturatedFat: 0,
          salt: 0,
          proteins: 0,
        ),
        'a',
      );
    });

    test('fats use energy from saturates and the saturated-fat ratio', () {
      // Olive oil: sat fat 14 of 100 g fat -> ratio 14 % = 1, energy from
      // saturates 518 kJ = 4: N = 5 -> score 5 -> C.
      expect(
        NutriScoreEstimate.grade(
          categories: const <String>['en:fats', 'en:vegetable-oils', 'en:olive-oils'],
          energyKJ: 3700,
          sugars: 0,
          fat: 100,
          saturatedFat: 14,
          salt: 0,
          proteins: 0,
        ),
        'c',
      );
    });

    test('no grade when exempt, uncategorised or facts are missing', () {
      expect(
        NutriScoreEstimate.grade(
          categories: const <String>['en:beverages', 'en:alcoholic-beverages'],
          energyKJ: 180,
          sugars: 1,
          saturatedFat: 0,
          salt: 0,
          proteins: 0,
        ),
        isNull,
      );
      expect(
        NutriScoreEstimate.grade(categories: const <String>[], energyKJ: 1, sugars: 1, saturatedFat: 0, salt: 0, proteins: 0),
        isNull,
      );
      expect(
        NutriScoreEstimate.grade(categories: const <String>['en:snacks'], energyKJ: 1, sugars: 1, proteins: 0),
        isNull,
      );
      // A fruit-heavy food needs its fruit share: without it, no estimate.
      expect(
        NutriScoreEstimate.grade(
          categories: const <String>['en:fruits-based-foods', 'en:compotes'],
          energyKJ: 300,
          sugars: 12,
          saturatedFat: 0,
          salt: 0,
          proteins: 0.5,
        ),
        isNull,
      );
    });
  });

  test('the health score uses the estimate when OFF has no grade', () {
    final Product nutella = Product(barcode: '3017620422003', categoriesTags: const <String>['en:spreads'])
      ..nutriscore = 'unknown'
      ..nutriments = (Nutriments.empty()
        ..setValue(Nutrient.energyKJ, PerSize.oneHundredGrams, 2252)
        ..setValue(Nutrient.sugars, PerSize.oneHundredGrams, 56.3)
        ..setValue(Nutrient.fat, PerSize.oneHundredGrams, 30.9)
        ..setValue(Nutrient.saturatedFat, PerSize.oneHundredGrams, 10.6)
        ..setValue(Nutrient.salt, PerSize.oneHundredGrams, 0.107)
        ..setValue(Nutrient.proteins, PerSize.oneHundredGrams, 6.3));
    final HealthScoreResult r = HealthScore.fromProduct(nutella);
    expect(r.score, isNotNull);
    expect(r.factors.first.title, 'Nutri-Score E (estimated)');

    nutella.nutriscore = 'not-applicable';
    expect(HealthScore.fromProduct(nutella).score, isNull);
  });

  test('plain and mineral water are A, flavoured water is not', () {
    String? g(final List<String> cats) => NutriScoreEstimate.grade(
      categories: <String>['en:beverages', ...cats],
      energyKJ: 0,
      sugars: 0,
      saturatedFat: 0,
      salt: 0.01,
      proteins: 0,
    );
    expect(g(<String>['en:waters', 'en:mineral-waters']), 'a');
    expect(g(<String>['en:waters']), 'a');
    expect(g(<String>['en:waters', 'en:flavoured-waters']), 'b');
  });
}
