import 'package:flutter_test/flutter_test.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:smooth_app/services/health_score.dart';
import 'package:smooth_app/services/score_types.dart';

void main() {
  group('HealthScore.compute', () {
    test('Nutri-Score A, no additives, NOVA 1, organic = 100', () {
      final HealthScoreResult r = HealthScore.compute(
        nutriscoreGrade: 'a',
        novaGroup: 1,
        additiveTags: const <String>[],
        labelsTags: const <String>['en:organic', 'en:eu-organic'],
      );
      expect(r.score, 100);
      expect(r.band, ScoreBand.excellent);
      expect(r.factors.map((ScoreFactor f) => f.points), <int>[60, 20, 10, 10]);
    });

    test('Nutri-Score E, ultra-processed, risky additives = 0', () {
      final HealthScoreResult r = HealthScore.compute(
        nutriscoreGrade: 'E',
        novaGroup: 4,
        // E250 (high), E211 (high), E338 (high): 20 - 24 -> 0
        additiveTags: const <String>['en:e250', 'en:e211', 'en:e338'],
      );
      expect(r.score, 0);
      expect(r.band, ScoreBand.bad);
      final ScoreFactor additives = r.factors[1];
      expect(additives.title, '3 risky additives');
      expect(additives.tone, FactorTone.negative);
      expect(additives.detail, contains('E250'));
      expect(additives.sources.length, 4);
    });

    test('moderate additive costs 4 points; harmless ones cost nothing', () {
      final HealthScoreResult r = HealthScore.compute(
        nutriscoreGrade: 'c',
        novaGroup: 3,
        // E133 moderate, E330 (citric acid) not in the risk list
        additiveTags: const <String>['en:e133', 'en:e330'],
      );
      // 30 + 16 + 5 + 0 = 51 of 100
      expect(r.score, 51);
      expect(r.factors[1].tone, FactorTone.neutral);
      final HealthScoreResult clean = HealthScore.compute(
        nutriscoreGrade: 'c',
        novaGroup: 3,
        additiveTags: const <String>['en:e330'],
      );
      expect(clean.factors[1].title, 'No risky additives');
      expect(clean.score, 55);
    });

    test('unknown parts are left out and the rest scaled to 100', () {
      final HealthScoreResult r = HealthScore.compute(nutriscoreGrade: 'b');
      // nutrition 45/60 + organic 0/10 = 45/70
      expect(r.score, (45 * 100 / 70).round());
      expect(r.factors.length, 2);
    });

    test('no Nutri-Score means no score, with a reason', () {
      final HealthScoreResult unknown = HealthScore.compute(
        nutriscoreGrade: 'unknown',
      );
      expect(unknown.score, isNull);
      expect(unknown.band, isNull);
      expect(unknown.missingReason, contains('nutrition facts'));
      final HealthScoreResult beer = HealthScore.compute(
        nutriscoreGrade: 'not-applicable',
      );
      expect(beer.missingReason, contains('alcohol'));
      expect(HealthScore.compute(nutriscoreGrade: null).score, isNull);
    });

    test('nutrient notes and EU claim thresholds', () {
      final HealthScoreResult r = HealthScore.compute(
        nutriscoreGrade: 'd',
        nutrientLevels: const <String, String>{
          'sugars': 'high',
          'salt': 'low',
          'fat': 'moderate',
        },
        per100g: const <String, double?>{
          'sugars': 56.3,
          'salt': 0.1,
          'fiber': 6.5,
          'proteins': 6.3,
          'energy-kcal': 539,
        },
      );
      expect(r.negatives.single.title, 'High in sugar');
      expect(r.negatives.single.detail, '56 g per 100 g');
      expect(
        r.positives.map((ScoreFactor f) => f.title),
        <String>['Low in salt', 'High in fibre'],
      );
      expect(r.positives.first.detail, '0.1 g per 100 g');
    });

    test('protein claim uses share of energy', () {
      final HealthScoreResult skyr = HealthScore.compute(
        nutriscoreGrade: 'a',
        per100g: const <String, double?>{'proteins': 11, 'energy-kcal': 62},
      );
      expect(skyr.positives.single.title, 'High in protein');
      final HealthScoreResult bread = HealthScore.compute(
        nutriscoreGrade: 'a',
        per100g: const <String, double?>{'proteins': 8, 'energy-kcal': 250},
      );
      expect(bread.positives.single.title, 'Source of protein');
    });
  });

  test('fromProduct reads the OFF fields', () {
    final Product product = Product(
      barcode: '1',
      nutriscore: 'e',
      additives: Additives(<String>['en:e322'], <String>['E322']),
      ingredientsText: 'sugar, palm oil, hazelnuts',
      labelsTags: const <String>[],
      nutrientLevels: NutrientLevels(<String, NutrientLevel>{
        'sugars': NutrientLevel.HIGH,
      }),
    );
    product.novaGroup = 4;
    final HealthScoreResult r = HealthScore.fromProduct(product);
    // 0 + 20 + 0 + 0 = 20/100
    expect(r.score, 20);
    expect(r.negatives.single.title, 'High in sugar');
  });

  test('fromProduct without ingredients ignores the additive part', () {
    final HealthScoreResult r = HealthScore.fromProduct(
      Product(barcode: '2', nutriscore: 'a'),
    );
    expect(r.factors.length, 2);
    expect(r.score, (60 * 100 / 70).round());
  });
}
