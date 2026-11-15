import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_app/pages/owner/owner_page.dart';

void main() {
  test('share text names up to three brands', () {
    expect(ownerShareText('Nestlé', null, const <String>[]), 'Nestlé. Found with Owned.');
    expect(ownerShareText('Arla', null, const <String>['Lurpak']), 'Arla owns Lurpak. Found with Owned.');
    expect(
      ownerShareText('Nestlé', null, const <String>['Maggi', 'Nescafé', 'KitKat', 'Nesquik']),
      'Nestlé owns Maggi, Nescafé and KitKat. Found with Owned.',
    );
  });
}
