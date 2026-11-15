import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_app/pages/product/product_page/overview/product_overview.dart';

void main() {
  test('the estimated-quantity mark is dropped, words are kept', () {
    expect(displayQuantity('400 g e'), '400 g');
    expect(displayQuantity('400g e'), '400g');
    expect(displayQuantity('1 kg ℮'), '1 kg');
    expect(displayQuantity('330 ml'), '330 ml');
    expect(displayQuantity('1 pièce'), '1 pièce');
    expect(displayQuantity('6 x 22 g'), '6 x 22 g');
    expect(displayQuantity('  '), isNull);
    expect(displayQuantity(null), isNull);
  });

  test('brands typed in lower case get capitals, others keep their own casing', () {
    expect(displayBrand('carrefour bio, Carrefour'), 'Carrefour Bio');
    expect(displayBrand('LINDT SPRUNGLI SAS'), 'LINDT SPRUNGLI SAS');
    expect(displayBrand('dm Bio'), 'dm Bio');
    expect(displayBrand(' '), isNull);
  });
}
