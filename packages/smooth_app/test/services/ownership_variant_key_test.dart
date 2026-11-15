import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_app/services/ownership_local_db.dart';

OwnershipLocalDb _db() => OwnershipLocalDb.fromJson(<String, dynamic>{
  'strings': <String>['Savencia', 'Elle & Vire', 'Isigny Sainte-Mère', 'The Coca-Cola Company', 'Fuze Tea', 'Dame'],
  'brands': <String, dynamic>{
    'elle and vire': <dynamic>[0, 'w', <int>[1, 0], ''],
    'isigny sainte mere': <dynamic>[2, 'w', <int>[2], ''],
    'fuze tea': <dynamic>[3, 'w', <int>[4, 3], ''],
    'dame': <dynamic>[5, 'w', <int>[5], ''],
  },
  'by_country': <String, dynamic>{},
  'prefix': <String, dynamic>{},
  'emb': <String, dynamic>{},
  'companies': <String, dynamic>{},
});

void main() {
  test('a brand spelled another way still finds its owner', () {
    final OwnershipLocalDb db = _db();
    expect(db.lookup(barcode: '', brands: 'Elle et Vire')?.owner, 'Savencia');
    expect(db.lookup(barcode: '', brands: 'Isigny Ste Mère')?.owner, 'Isigny Sainte-Mère');
    expect(db.lookup(barcode: '', brands: 'FuzeTea')?.owner, 'The Coca-Cola Company');
  });

  test('no guessing: plurals and short run-together names stay unknown', () {
    final OwnershipLocalDb db = _db();
    expect(db.lookup(barcode: '', brands: 'Dames'), isNull);
    expect(db.variantKey('elle and vire'), isNull);
  });
}
