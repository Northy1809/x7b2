import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:smooth_app/helpers/product_cards_helper.dart';
import 'package:smooth_app/l10n/app_localizations.dart';

void main() {
  final AppLocalizations l10n = lookupAppLocalizations(const Locale('en'));

  test('falls back to the plain name, then to any language with a name', () {
    // Outside lookups (UPCitemdb) only fill the plain name.
    expect(getProductName(Product(barcode: '1', productName: ' Oat drink '), l10n), 'Oat drink');
    expect(
      getProductName(
        Product(barcode: '2')
          ..productNameInLanguages = <OpenFoodFactsLanguage, String>{
            OpenFoodFactsLanguage.GERMAN: ' ',
            OpenFoodFactsLanguage.FRENCH: 'Pâte à tartiner',
          },
        l10n,
      ),
      'Pâte à tartiner',
    );
    expect(getProductName(Product(barcode: '3'), l10n), l10n.unknownProductName);
  });
}
