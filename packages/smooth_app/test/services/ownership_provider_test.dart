import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_app/database/dao_ownership_scan.dart';
import 'package:smooth_app/pages/product/product_page/tabs/ownership/ownership_provider.dart';
import 'package:smooth_app/services/owner_overrides.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/ownership_service.dart';

class _FakeScanDao implements DaoOwnershipScan {
  int inserts = 0;

  @override
  Future<int> insertScan({
    required String? barcode,
    required String countryCode,
    required OwnershipScanSource source,
    required OwnershipScanStatus status,
    double? confidence,
    String? guessedName,
  }) async => ++inserts;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final OwnershipLocalDb db = OwnershipLocalDb.fromJson(<String, dynamic>{
    'strings': <String>['Nestlé', 'Mondelez International'],
    'brands': <String, dynamic>{
      'nesquik': <dynamic>[0, 'w'],
      'milka': <dynamic>[1, 'w'],
    },
    'by_country': <String, dynamic>{},
    'prefix': <String, dynamic>{},
    'emb': <String, dynamic>{},
    'companies': <String, dynamic>{},
  });

  late _FakeScanDao dao;

  setUp(() => dao = _FakeScanDao());

  OwnershipProvider provider({final bool askUser = false}) => OwnershipProvider(
    product: Product(barcode: '1', brands: 'Nesquik'),
    countryCode: 'dk',
    // No network in tests: every online step answers nothing.
    service: OwnershipService(
      supabaseUrl: '',
      supabaseAnonKey: '',
      anthropicApiKey: '',
      client: MockClient((_) async => http.Response('', 500)),
    ),
    scanDao: dao,
    localDb: () async => db,
    askUser: askUser,
  );

  test('"Not right?" asks for the brand instead of showing the same answer', () async {
    final OwnershipProvider p = provider(askUser: true);
    expect(p.status, OwnershipStatus.unresolved);
    expect(p.result, isNull);
  });

  test('a typed brand is looked up offline first and marked as typed', () async {
    final OwnershipProvider p = provider(askUser: true);
    await p.lookupManualBrand('Milka');
    expect(p.status, OwnershipStatus.resolved);
    expect(p.result!.ownerCompany, 'Mondelez International');
    expect(p.fromTypedBrand, isTrue);
  });

  test('a normal scan resolves from the product', () async {
    final OwnershipProvider p = provider();
    await pumpEventQueue();
    expect(p.result?.ownerCompany, 'Nestlé');
    expect(p.fromTypedBrand, isFalse);
  });

  test('a correction made elsewhere updates an open product', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    OwnerOverrides.instance.resetForTest();
    final OwnershipProvider p = provider();
    await pumpEventQueue();
    expect(p.result?.ownerCompany, 'Nestlé');
    await OwnerOverrides.instance.set(barcode: '1', brands: 'Nesquik', owner: 'Someone');
    await pumpEventQueue();
    expect(p.result?.ownerCompany, 'Someone');
    await OwnerOverrides.instance.remove(barcode: '1', brands: 'Nesquik');
    await pumpEventQueue();
    expect(p.result?.ownerCompany, 'Nestlé');
    // One scan, logged once: looking again after a correction is no new scan.
    expect(dao.inserts, 1);
    p.dispose();
    OwnerOverrides.instance.resetForTest();
  });
}
