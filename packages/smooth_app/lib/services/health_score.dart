import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:smooth_app/services/additive_risks.dart';
import 'package:smooth_app/services/nutriscore_estimate.dart';
import 'package:smooth_app/services/score_types.dart';

/// Result of [HealthScore.compute]. [score] is null when there is not
/// enough data; [missingReason] then says why.
class HealthScoreResult {
  const HealthScoreResult({
    required this.score,
    required this.factors,
    this.missingReason,
    this.notApplicable = false,
    this.positives = const <ScoreFactor>[],
    this.negatives = const <ScoreFactor>[],
  });

  final int? score;

  /// The parts of the score sum, in the order they are weighted.
  final List<ScoreFactor> factors;
  final String? missingReason;

  /// No score because Nutri-Score does not apply to this kind of product,
  /// not because data is missing.
  final bool notApplicable;

  /// Nutrient facts worth knowing (not part of the sum): "Low salt", ...
  final List<ScoreFactor> positives;
  final List<ScoreFactor> negatives;

  ScoreBand? get band => score == null ? null : ScoreBand.of(score!);
}

/// A transparent 0-100 health score, weighted like the public description
/// of Yuka's method (nutrition first, then additives, then organic), but
/// built only on open data with a source for each part:
///
/// * Nutri-Score (Santé publique France): 60 points
/// * Additives with an EFSA overexposure risk (OFF taxonomy): 20 points
/// * Processing, NOVA group (Monteiro et al.): 10 points
/// * Organic label (EU organic logo): 10 points
///
/// Parts without data are left out and the rest is scaled to 100. Without a
/// Nutri-Score there is no score at all: nutrition is most of the answer.
class HealthScore {
  const HealthScore._();

  static const SourceLink nutriscoreSource = SourceLink(
    title: 'Nutri-Score (Santé publique France)',
    url: 'https://www.santepubliquefrance.fr/en/nutri-score',
  );
  static const SourceLink novaSource = SourceLink(
    title: 'NOVA classification (Monteiro et al., Public Health Nutrition 2019)',
    url: 'https://doi.org/10.1017/S1368980018003762',
  );
  static const SourceLink organicSource = SourceLink(
    title: 'EU organic logo (European Commission)',
    url: 'https://agriculture.ec.europa.eu/farming/organic-farming/organic-logo_en',
  );
  static const SourceLink nutrientLevelSource = SourceLink(
    title: 'Low/high thresholds (UK Food Standards Agency, used by Open Food Facts)',
    url: 'https://www.gov.uk/government/publications/front-of-pack-nutrition-labelling-guidance',
  );
  static const SourceLink claimsSource = SourceLink(
    title: 'EU rules for nutrition claims (Regulation 1924/2006)',
    url: 'https://food.ec.europa.eu/food-safety/labelling-and-nutrition/nutrition-and-health-claims/nutrition-claims_en',
  );

  static const int nutritionMax = 60;
  static const int additivesMax = 20;
  static const int processingMax = 10;
  static const int organicMax = 10;

  static const Map<String, int> _nutriscorePoints = <String, int>{
    'a': 60,
    'b': 45,
    'c': 30,
    'd': 15,
    'e': 0,
  };

  static const Map<int, int> _novaPoints = <int, int>{1: 10, 2: 8, 3: 5, 4: 0};

  static const Set<String> organicLabels = <String>{
    'en:organic',
    'en:eu-organic',
    'en:dk-organic',
    'en:ab-agriculture-biologique',
    'en:bio-siegel',
    'en:krav',
    'en:demeter',
  };

  static HealthScoreResult fromProduct(final Product product) {
    final List<String>? additives = product.additives?.ids;
    final bool ingredientsKnown =
        (product.ingredientsText?.trim().isNotEmpty ?? false) ||
        (product.ingredientsTextInLanguages?.values.any(
              (String t) => t.trim().isNotEmpty,
            ) ??
            false) ||
        (additives?.isNotEmpty ?? false);
    final Map<String, String> levels = <String, String>{
      for (final MapEntry<String, NutrientLevel> e
          in product.nutrientLevels?.levels.entries ??
              const <MapEntry<String, NutrientLevel>>[])
        e.key: e.value.offTag,
    };
    final Nutriments? n = product.nutriments;
    double? per100(final Nutrient nutrient) =>
        n?.getValue(nutrient, PerSize.oneHundredGrams);
    String? grade = product.nutriscore?.trim().toLowerCase();
    bool estimated = false;
    if (!_nutriscorePoints.containsKey(grade) && grade != 'not-applicable') {
      final String? estimate = NutriScoreEstimate.fromProduct(product);
      if (estimate != null) {
        grade = estimate;
        estimated = true;
      }
    }
    return compute(
      nutriscoreGrade: grade,
      nutriscoreEstimated: estimated,
      novaGroup: product.novaGroup,
      additiveTags: ingredientsKnown ? (additives ?? const <String>[]) : null,
      labelsTags: product.labelsTags ?? const <String>[],
      nutrientLevels: levels,
      per100g: <String, double?>{
        'sugars': per100(Nutrient.sugars),
        'fat': per100(Nutrient.fat),
        'saturated-fat': per100(Nutrient.saturatedFat),
        'salt': per100(Nutrient.salt),
        'fiber': per100(Nutrient.fiber),
        'proteins': per100(Nutrient.proteins),
        // Many labels only give kJ.
        'energy-kcal': per100(Nutrient.energyKCal) ?? _kcalFromKj(per100(Nutrient.energyKJ)),
      },
    );
  }

  /// [additiveTags] null means the ingredients are unknown (not "none").
  /// [nutriscoreEstimated]: the grade was worked out by the app
  /// ([NutriScoreEstimate]) because Open Food Facts has none.
  static HealthScoreResult compute({
    required final String? nutriscoreGrade,
    final bool nutriscoreEstimated = false,
    final int? novaGroup,
    final List<String>? additiveTags,
    final List<String> labelsTags = const <String>[],
    final Map<String, String> nutrientLevels = const <String, String>{},
    final Map<String, double?> per100g = const <String, double?>{},
  }) {
    final String? grade = nutriscoreGrade?.trim().toLowerCase();
    final List<ScoreFactor> negatives = _nutrientNotes(
      nutrientLevels,
      per100g,
      negative: true,
    );
    final List<ScoreFactor> positives = <ScoreFactor>[
      ..._nutrientNotes(nutrientLevels, per100g, negative: false),
      ..._claims(per100g),
    ];

    final int? nutrition = grade == null ? null : _nutriscorePoints[grade];
    if (nutrition == null) {
      return HealthScoreResult(
        score: null,
        factors: const <ScoreFactor>[],
        missingReason: grade == 'not-applicable'
            ? 'Nutri-Score does not apply to this kind of product (for '
                  'example alcohol, coffee, tea, spices or infant formula), '
                  'so there is no health score.'
            : 'The nutrition facts for this product are missing, so we '
                  'cannot give it a health score yet.',
        notApplicable: grade == 'not-applicable',
        positives: positives,
        negatives: negatives,
      );
    }

    final List<ScoreFactor> factors = <ScoreFactor>[
      ScoreFactor(
        title: 'Nutri-Score ${grade!.toUpperCase()}${nutriscoreEstimated ? ' (estimated)' : ''}',
        detail: nutriscoreEstimated
            ? 'Open Food Facts has no Nutri-Score for this product, so Owned worked it out from '
                  'the nutrition facts with the official 2023 formula. Sugar, saturated fat, salt and '
                  'energy pull it down; fibre, protein, fruit and vegetables pull it up.'
            : 'Nutrition profile: sugar, saturated fat, salt and energy '
                  'pull it down; fibre, protein, fruit and vegetables pull it up.',
        tone: nutrition >= 45
            ? FactorTone.positive
            : nutrition >= 30
            ? FactorTone.neutral
            : FactorTone.negative,
        points: nutrition,
        maxPoints: nutritionMax,
        sources: const <SourceLink>[nutriscoreSource],
      ),
    ];
    int sum = nutrition;
    int max = nutritionMax;

    if (additiveTags != null) {
      final List<AdditiveRisk> high = <AdditiveRisk>[];
      final List<AdditiveRisk> moderate = <AdditiveRisk>[];
      for (final String tag in additiveTags.toSet()) {
        final AdditiveRisk? risk = additiveRisks[tag];
        if (risk == null) {
          continue;
        }
        (risk.level == AdditiveRiskLevel.high ? high : moderate).add(risk);
      }
      final int points = (additivesMax - 8 * high.length - 4 * moderate.length)
          .clamp(0, additivesMax);
      sum += points;
      max += additivesMax;
      final List<AdditiveRisk> risky = <AdditiveRisk>[...high, ...moderate];
      factors.add(
        ScoreFactor(
          title: risky.isEmpty
              ? (additiveTags.isEmpty
                    ? 'No additives'
                    : 'No risky additives')
              : '${risky.length} risky additive${risky.length == 1 ? '' : 's'}',
          detail: risky.isEmpty
              ? (additiveTags.isEmpty
                    ? null
                    : '${additiveTags.length} additive${additiveTags.length == 1 ? '' : 's'}, '
                          'none with a known overexposure risk (EFSA).')
              : <String>[
                  for (final AdditiveRisk r in high) '${r.name} (high risk)',
                  for (final AdditiveRisk r in moderate) '${r.name} (moderate risk)',
                ].join('\n'),
          tone: risky.isEmpty
              ? FactorTone.positive
              : high.isNotEmpty
              ? FactorTone.negative
              : FactorTone.neutral,
          points: points,
          maxPoints: additivesMax,
          sources: <SourceLink>[
            for (final AdditiveRisk r in risky)
              if (r.sourceUrl.isNotEmpty)
                SourceLink(title: 'EFSA on ${r.name}', url: r.sourceUrl),
            const SourceLink(
              title: 'Open Food Facts: additives and EFSA risk',
              url: 'https://world.openfoodfacts.org/additives',
            ),
          ],
        ),
      );
    }

    final int? processing = novaGroup == null ? null : _novaPoints[novaGroup];
    if (processing != null) {
      sum += processing;
      max += processingMax;
      factors.add(
        ScoreFactor(
          title: switch (novaGroup) {
            1 => 'Unprocessed (NOVA 1)',
            2 => 'Cooking ingredient (NOVA 2)',
            3 => 'Processed (NOVA 3)',
            _ => 'Ultra-processed (NOVA 4)',
          },
          detail: novaGroup == 4
              ? 'Industrial ingredients or additives you would not use '
                    'in a home kitchen.'
              : null,
          tone: novaGroup! <= 2
              ? FactorTone.positive
              : novaGroup == 3
              ? FactorTone.neutral
              : FactorTone.negative,
          points: processing,
          maxPoints: processingMax,
          sources: const <SourceLink>[novaSource],
        ),
      );
    }

    final bool organic = labelsTags.any(organicLabels.contains);
    sum += organic ? organicMax : 0;
    max += organicMax;
    factors.add(
      ScoreFactor(
        title: organic ? 'Organic' : 'Not organic',
        tone: organic ? FactorTone.positive : FactorTone.neutral,
        points: organic ? organicMax : 0,
        maxPoints: organicMax,
        sources: const <SourceLink>[organicSource],
      ),
    );

    return HealthScoreResult(
      score: (sum * 100 / max).round(),
      factors: factors,
      positives: positives,
      negatives: negatives,
    );
  }

  static const Map<String, (String, String)> _nutrientNames =
      <String, (String, String)>{
        'sugars': ('High in sugar', 'Low in sugar'),
        'saturated-fat': ('High in saturated fat', 'Low in saturated fat'),
        'fat': ('High in fat', 'Low in fat'),
        'salt': ('High in salt', 'Low in salt'),
      };

  static List<ScoreFactor> _nutrientNotes(
    final Map<String, String> levels,
    final Map<String, double?> per100g, {
    required final bool negative,
  }) {
    final List<ScoreFactor> out = <ScoreFactor>[];
    for (final MapEntry<String, (String, String)> e in _nutrientNames.entries) {
      final String? level = levels[e.key];
      if (level != (negative ? 'high' : 'low')) {
        continue;
      }
      final double? value = per100g[e.key];
      out.add(
        ScoreFactor(
          title: negative ? e.value.$1 : e.value.$2,
          detail: value == null ? null : '${_fmt(value)} g per 100 g',
          tone: negative ? FactorTone.negative : FactorTone.positive,
          sources: const <SourceLink>[nutrientLevelSource],
        ),
      );
    }
    return out;
  }

  /// EU nutrition-claim thresholds (Regulation 1924/2006, Annex).
  static List<ScoreFactor> _claims(final Map<String, double?> per100g) {
    final List<ScoreFactor> out = <ScoreFactor>[];
    final double? fiber = per100g['fiber'];
    if (fiber != null && fiber >= 3) {
      out.add(
        ScoreFactor(
          title: fiber >= 6 ? 'High in fibre' : 'Source of fibre',
          detail: '${_fmt(fiber)} g per 100 g',
          tone: FactorTone.positive,
          sources: const <SourceLink>[claimsSource],
        ),
      );
    }
    final double? protein = per100g['proteins'];
    final double? kcal = per100g['energy-kcal'];
    if (protein != null && kcal != null && kcal > 0) {
      final double share = protein * 4 / kcal;
      if (share >= 0.12) {
        out.add(
          ScoreFactor(
            title: share >= 0.20 ? 'High in protein' : 'Source of protein',
            detail: '${_fmt(protein)} g per 100 g',
            tone: FactorTone.positive,
            sources: const <SourceLink>[claimsSource],
          ),
        );
      }
    }
    return out;
  }

  static double? _kcalFromKj(final double? kj) => kj == null ? null : kj / 4.184;

  static String _fmt(final double v) {
    final String s = v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return s.replaceAll(RegExp(r'\.0$'), '');
  }
}
