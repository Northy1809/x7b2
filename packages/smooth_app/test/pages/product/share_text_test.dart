import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_app/pages/product/product_page/overview/product_overview.dart';

void main() {
  test('share text names the owner, the moral score and the open data page', () {
    expect(
      shareText('KitKat', 'Nestlé', 13, '7613035833449'),
      'KitKat is owned by Nestlé (moral score 13/100). Found with Owned. '
      'https://world.openfoodfacts.org/product/7613035833449',
    );
    expect(shareText('Pen', 'STABILO', null, null), 'Pen is owned by STABILO. Found with Owned.');
  });
}
