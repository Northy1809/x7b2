import 'package:openfoodfacts/openfoodfacts.dart';

/// Nutri-Score (2023 algorithm) worked out from the nutrition facts, for
/// products where Open Food Facts has the facts but no grade (it skips
/// products with some data-quality flags, e.g. Nutella in Nov 2026).
///
/// Port of openfoodfacts-server lib/ProductOpener/Nutriscore.pm
/// (compute_nutriscore_score_2023, compute_nutriscore_grade_2023) and the
/// category rules in Food.pm / Config_off.pm. Simplified: nuts are
/// recognised by category instead of customs codes, red meat by category
/// instead of ingredient share.
class NutriScoreEstimate {
  const NutriScoreEstimate._();

  static const List<double> _energy = <double>[335, 670, 1005, 1340, 1675, 2010, 2345, 2680, 3015, 3350];
  static const List<double> _energyBeverages = <double>[30, 90, 150, 210, 240, 270, 300, 330, 360, 390];
  static const List<double> _sugars = <double>[3.4, 6.8, 10, 14, 17, 20, 24, 27, 31, 34, 37, 41, 44, 48, 51];
  static const List<double> _sugarsBeverages = <double>[0.5, 2, 3.5, 5, 6, 7, 8, 9, 10, 11];
  static const List<double> _saturatedFat = <double>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  static const List<double> _salt = <double>[
    0.2, 0.4, 0.6, 0.8, 1, 1.2, 1.4, 1.6, 1.8, 2, 2.2, 2.4, 2.6, 2.8, 3, 3.2, 3.4, 3.6, 3.8, 4,
  ];
  static const List<double> _energyFromSaturatedFat = <double>[120, 240, 360, 480, 600, 720, 840, 960, 1080, 1200];
  static const List<double> _saturatedFatRatio = <double>[10, 16, 22, 28, 34, 40, 46, 52, 58, 64];
  static const List<double> _fvl = <double>[40, 60, 80, 80, 80];
  static const List<double> _fvlBeverages = <double>[40, 40, 60, 60, 80, 80];
  static const List<double> _fiber = <double>[3.0, 4.1, 5.2, 6.3, 7.4];
  static const List<double> _proteins = <double>[2.4, 4.8, 7.2, 9.6, 12, 14, 17];
  static const List<double> _proteinsBeverages = <double>[1.2, 1.5, 1.8, 2.1, 2.4, 2.7, 3.0];

  /// Config_off.pm categories_exempted_from_nutriscore.
  static const Set<String> exempt = <String>{
    'en:alcoholic-beverages', 'en:baby-foods', 'en:baby-milks', 'en:chewing-gum', 'en:food-additives',
    'en:dietary-supplements', 'en:meal-replacements', 'en:salts', 'en:spices', 'en:sugar-substitutes',
    'en:vinegars', 'en:non-food-products',
  };
  static const Set<String> _beverageAnyway = <String>{
    'en:milks', 'en:plant-based-milk-alternatives', 'en:dairy-drinks', 'en:plant-based-beverages',
    'en:tea-based-beverages', 'en:iced-teas', 'en:herbal-tea-beverages', 'en:coffee-beverages',
    'en:coffee-drinks', 'en:coffees', 'en:herbal-teas', 'en:teas',
  };
  static const Set<String> _notBeverage = <String>{'en:meal-replacement', 'en:soups'};
  static const Set<String> _redMeat = <String>{
    'en:beef', 'en:veal', 'en:pork', 'en:lamb-meat', 'en:mutton', 'en:hams', 'en:bacon', 'en:horse-meat',
  };

  /// Where fruit, vegetables and legumes weigh a lot: without a known share
  /// the estimate would be too harsh, so none is given.
  static const Set<String> _fruitVegetableHeavy = <String>{
    'en:fruits-and-vegetables-based-foods', 'en:fruits-based-foods', 'en:vegetables-based-foods',
    'en:legumes-and-their-products', 'en:fruit-juices', 'en:fruits-based-beverages', 'en:vegetable-juices',
    'en:compotes', 'en:jams', 'en:soups',
  };

  /// Non-nutritive sweeteners: 4 extra negative points for beverages.
  static const Set<String> _sweeteners = <String>{
    'en:e950', 'en:e951', 'en:e952', 'en:e954', 'en:e955', 'en:e957', 'en:e959', 'en:e960', 'en:e960a',
    'en:e961', 'en:e962', 'en:e969',
  };

  static String? fromProduct(final Product product) {
    final Nutriments? n = product.nutriments;
    if (n == null) {
      return null;
    }
    double? v(final Nutrient nutrient) => n.getValue(nutrient, PerSize.oneHundredGrams);
    double? salt = v(Nutrient.salt);
    final double? sodium = v(Nutrient.sodium);
    if (salt == null && sodium != null) {
      salt = sodium * 2.5;
    }
    return grade(
      categories: product.categoriesTags ?? const <String>[],
      additives: product.additives?.ids ?? const <String>[],
      energyKJ: n.getComputedKJ(PerSize.oneHundredGrams),
      // Nutriscore.pm: no sugars listed but 0 g carbohydrates means 0 g sugars.
      sugars: v(Nutrient.sugars) ?? (v(Nutrient.carbohydrates) == 0 ? 0 : null),
      fat: v(Nutrient.fat),
      saturatedFat: v(Nutrient.saturatedFat),
      salt: salt,
      fiber: v(Nutrient.fiber),
      proteins: v(Nutrient.proteins),
      fruitsVegetablesLegumes: v(Nutrient.fruitsVegetablesNuts) ?? v(Nutrient.fruitsVegetablesNutsEstimate),
    );
  }

  /// The grade a-e, or null when the product is exempt, its category is
  /// unknown, or the needed facts are missing.
  static String? grade({
    required final List<String> categories,
    final List<String> additives = const <String>[],
    final double? energyKJ,
    final double? sugars,
    final double? fat,
    final double? saturatedFat,
    final double? salt,
    final double? fiber,
    final double? proteins,
    final double? fruitsVegetablesLegumes,
  }) {
    final Set<String> c = categories.toSet();
    if (c.isEmpty || c.any(exempt.contains)) {
      return null;
    }
    final double? satFat = saturatedFat ?? (fat == 0 ? 0 : null);
    if (energyKJ == null || sugars == null || satFat == null || salt == null || proteins == null) {
      return null;
    }
    if (fruitsVegetablesLegumes == null && c.any(_fruitVegetableHeavy.contains)) {
      return null;
    }
    bool beverage = (c.contains('en:beverages') || c.contains('en:beverage-preparations')) && !c.any(_notBeverage.contains);
    if (c.any(_beverageAnyway.contains)) {
      beverage = true;
    }
    // Plain water of any kind is A; flavoured water is scored as a drink.
    final bool water = (c.contains('en:waters') || c.contains('en:spring-waters') || c.contains('en:mineral-waters')) &&
        !c.contains('en:flavored-waters') &&
        !c.contains('en:flavoured-waters');
    final bool cheese = c.contains('en:cheeses') && !c.contains('fr:fromages-blancs');
    final bool fatsNuts = !c.contains('en:chestnuts') &&
        (c.contains('en:fats') || c.contains('en:creams') || c.contains('en:seeds') || c.contains('en:nuts') ||
            c.contains('en:peanuts'));

    int points(final double value, final List<double> thresholds, {final bool orEqual = false}) =>
        thresholds.where((double t) => orEqual ? value >= t : value > t).length;

    final int energyPoints = fatsNuts
        ? points(satFat * 37, _energyFromSaturatedFat)
        : points(energyKJ, beverage ? _energyBeverages : _energy);
    final int satFatPoints = fatsNuts
        ? (fat != null && fat > 0 ? points(satFat / fat * 100, _saturatedFatRatio, orEqual: true) : 0)
        : points(satFat, _saturatedFat);
    int negative = energyPoints +
        points(sugars, beverage ? _sugarsBeverages : _sugars) +
        satFatPoints +
        points(salt, _salt);
    if (beverage && additives.any(_sweeteners.contains)) {
      negative += 4;
    }

    int proteinPoints = points(proteins, beverage ? _proteinsBeverages : _proteins);
    if (c.any(_redMeat.contains) && proteinPoints > 2) {
      proteinPoints = 2;
    }
    final bool countProteins = beverage || cheese || (fatsNuts ? negative < 7 : negative < 11);
    final int positive = (countProteins ? proteinPoints : 0) +
        points(fiber ?? 0, _fiber) +
        points(fruitsVegetablesLegumes ?? 0, beverage ? _fvlBeverages : _fvl);
    final int score = negative - positive;

    if (beverage) {
      if (water) {
        return 'a';
      }
      return score <= 2 ? 'b' : score <= 6 ? 'c' : score <= 9 ? 'd' : 'e';
    }
    if (fatsNuts) {
      return score <= -6 ? 'a' : score <= 2 ? 'b' : score <= 10 ? 'c' : score <= 18 ? 'd' : 'e';
    }
    return score <= 0 ? 'a' : score <= 2 ? 'b' : score <= 10 ? 'c' : score <= 18 ? 'd' : 'e';
  }
}
