import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:smooth_app/helpers/launch_url_helper.dart';
import 'package:smooth_app/pages/product/product_page/overview/product_overview.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/cal_ui.dart';

/// "All product details" as a Cal AI page (16/11): ingredients, allergens,
/// nutrition per 100 g and labels from Open Food Facts, in white cards.
/// Replaces Open Food Facts' tabbed product page.
class ProductFactsPage extends StatelessWidget {
  const ProductFactsPage(this.product, {super.key});

  final Product product;

  static Future<void> open(final BuildContext context, final Product product) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(builder: (_) => ProductFactsPage(product)),
  );

  /// "en:milk" -> "Milk".
  static String tagName(final String tag) {
    final String t = tag.contains(':') ? tag.substring(tag.indexOf(':') + 1) : tag;
    final String words = t.replaceAll('-', ' ').trim();
    return words.isEmpty ? words : words[0].toUpperCase() + words.substring(1);
  }

  String? get _ingredients {
    final String? text = product.ingredientsText?.trim();
    if (text != null && text.isNotEmpty) {
      return text;
    }
    for (final String t in product.ingredientsTextInLanguages?.values ?? const <String>[]) {
      if (t.trim().isNotEmpty) {
        return t.trim();
      }
    }
    return null;
  }

  static String _num(final double v) {
    if (v >= 100) {
      return v.round().toString();
    }
    // Two decimals under 1 g (salt 0.12 g), one above.
    String s = v.toStringAsFixed(v < 1 ? 2 : 1);
    while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  List<(String, String, bool)> get _nutrition {
    final Nutriments? n = product.nutriments;
    if (n == null) {
      return const <(String, String, bool)>[];
    }
    const PerSize per = PerSize.oneHundredGrams;
    final List<(String, String, bool)> rows = <(String, String, bool)>[];
    void add(final String label, final double? value, final String unit, {bool sub = false}) {
      if (value != null) {
        rows.add((label, '${_num(value)} $unit', sub));
      }
    }

    final double? kcal = n.getValue(Nutrient.energyKCal, per);
    final double? kj = n.getComputedKJ(per);
    if (kcal != null || kj != null) {
      rows.add((
        'Energy',
        <String>[if (kcal != null) '${_num(kcal)} kcal', if (kj != null) '${_num(kj)} kJ'].join(' · '),
        false,
      ));
    }
    add('Fat', n.getValue(Nutrient.fat, per), 'g');
    add('of which saturates', n.getValue(Nutrient.saturatedFat, per), 'g', sub: true);
    add('Carbohydrates', n.getValue(Nutrient.carbohydrates, per), 'g');
    add('of which sugars', n.getValue(Nutrient.sugars, per), 'g', sub: true);
    add('Fibre', n.getValue(Nutrient.fiber, per), 'g');
    add('Protein', n.getValue(Nutrient.proteins, per), 'g');
    add('Salt', n.getValue(Nutrient.salt, per), 'g');
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final String name = productDisplayName(product) ?? product.barcode ?? '';
    final String subtitle = <String?>[
      product.brands?.split(',').first.trim(),
      displayQuantity(product.quantity),
    ].whereType<String>().where((String s) => s.isNotEmpty).join(' · ');
    final String? ingredients = _ingredients;
    final List<String> allergens = <String>[
      for (final String a in product.allergens?.ids ?? const <String>[]) tagName(a),
    ];
    final List<String> labels = <String>[
      for (final String l in product.labelsTags ?? const <String>[]) tagName(l),
    ];
    final List<(String, String, bool)> nutrition = _nutrition;
    final TextStyle? body = theme.textTheme.bodyMedium?.copyWith(fontSize: 15.0, height: 1.45);
    final TextStyle? cardTitle = theme.textTheme.titleMedium?.copyWith(
      fontSize: 17.0,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
    );

    Widget card(final int index, final String title, final Widget child) => Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 14.0),
      child: FadeUpIn(
        index: index,
        child: CalCard(
          padding: const EdgeInsetsDirectional.fromSTEB(18.0, 16.0, 18.0, 18.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: cardTitle),
              const SizedBox(height: 10.0),
              child,
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      appBar: const CalTopBar(title: 'Product details'),
      body: ListView(
        padding: EdgeInsetsDirectional.fromSTEB(kCalSide, 8.0, kCalSide, MediaQuery.paddingOf(context).bottom + 32.0),
        children: <Widget>[
          FadeUpIn(
            child: Text(
              name,
              style: theme.textTheme.titleLarge?.copyWith(fontSize: 24.0, fontWeight: FontWeight.w700, letterSpacing: -0.6),
            ),
          ),
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 4.0),
              child: Text(subtitle, style: body?.copyWith(color: muted)),
            ),
          const SizedBox(height: 18.0),
          card(
            1,
            'Ingredients',
            Text(ingredients ?? 'Not listed yet in Open Food Facts.', style: ingredients == null ? body?.copyWith(color: muted) : body),
          ),
          if (allergens.isNotEmpty)
            card(
              2,
              'Allergens',
              Wrap(spacing: 8.0, runSpacing: 8.0, children: <Widget>[for (final String a in allergens) CalPill(label: a)]),
            ),
          card(
            3,
            'Nutrition per 100 g',
            nutrition.isEmpty
                ? Text('Not listed yet in Open Food Facts.', style: body?.copyWith(color: muted))
                : Column(
                    children: <Widget>[
                      for (int i = 0; i < nutrition.length; i++) ...<Widget>[
                        if (i > 0) Container(height: 1.0, color: calHairline(context)),
                        Padding(
                          padding: EdgeInsetsDirectional.fromSTEB(nutrition[i].$3 ? 14.0 : 0.0, 10.0, 0.0, 10.0),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  nutrition[i].$1,
                                  style: body?.copyWith(color: nutrition[i].$3 ? muted : null),
                                ),
                              ),
                              Text(
                                nutrition[i].$2,
                                style: body?.copyWith(
                                  fontWeight: nutrition[i].$3 ? FontWeight.w400 : FontWeight.w600,
                                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          if (labels.isNotEmpty)
            card(
              4,
              'Labels',
              Wrap(spacing: 8.0, runSpacing: 8.0, children: <Widget>[for (final String l in labels.take(12)) CalPill(label: l)]),
            ),
          if (product.barcode != null) ...<Widget>[
            const SizedBox(height: 6.0),
            Center(
              child: CalPill(
                icon: CupertinoIcons.arrow_up_right,
                label: 'See it on Open Food Facts',
                onTap: () => LaunchUrlHelper.launchURL('https://world.openfoodfacts.org/product/${product.barcode}'),
              ),
            ),
            const SizedBox(height: 14.0),
            Text(
              'Barcode ${product.barcode} · data from Open Food Facts (ODbL)',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12.0, color: muted),
            ),
          ],
        ],
      ),
    );
  }
}
