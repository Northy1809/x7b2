import 'package:flutter_test/flutter_test.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/owner_insights.dart';
import 'package:smooth_app/services/ownership_local_db.dart';

void main() {
  final OwnershipLocalDb db = OwnershipLocalDb.fromJson(<String, dynamic>{
    'strings': <String>['Nestlé', 'Nestle', 'Fromagerie X'],
    'brands': <String, dynamic>{
      'kitkat': <dynamic>[0, 'w'],
      'nesquik': <dynamic>[1, 'w'],
    },
    'by_country': <String, dynamic>{},
    'prefix': <String, dynamic>{},
    'emb': <String, dynamic>{
      'fr-56-178-001-ec': <dynamic>[2, 'h'],
    },
    'companies': <String, dynamic>{},
  });

  test('groups spellings of one owner and finds owners by health mark', () {
    final OwnerInsights i = OwnerInsights.compute(<Product>[
      Product(barcode: '1', brands: 'KitKat'),
      Product(barcode: '2', brands: 'Nesquik'),
      Product(barcode: '3')..embCodes = 'FR 56.178.001 CE',
      Product(barcode: '4', brands: 'Zzqx'),
    ], db);
    expect(i.owners.first.count, 2);
    expect(i.owners.map((OwnerTally t) => t.owner), contains('Fromagerie X'));
    expect(i.unknown.length, 1);
    expect(i.total, 4);
  });

  test('turns free-text health marks into database tags', () {
    expect(OwnershipLocalDb.embCodeTags('FR 56.178.001 CE, DK M123 EF'), <String>['fr-56-178-001-ec', 'dk-m123-ef']);
  });

  test('average ethics weighs each company by how many of its products were scanned', () {
    final EthicsDb ethics = EthicsDb.fromJson(<String, dynamic>{
      'companies': <Map<String, dynamic>>[
        <String, dynamic>{'id': 'n', 'name': 'Nestlé', 'about': ''},
      ],
    });
    final OwnerInsights i = OwnerInsights.compute(<Product>[
      Product(barcode: '1', brands: 'KitKat'),
      Product(barcode: '2', brands: 'Nesquik'),
      Product(barcode: '3')..embCodes = 'FR 56.178.001 CE',
    ], db, ethics: ethics);
    // Nestlé (2 products) has no cases: 70; Fromagerie X is not rated.
    expect(i.averageEthics, 70);
    expect(OwnerInsights.compute(<Product>[Product(barcode: '4', brands: 'Zzqx')], db).averageEthics, isNull);
  });
}
