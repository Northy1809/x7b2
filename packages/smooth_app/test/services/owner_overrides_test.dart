import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_app/services/owner_overrides.dart';
import 'package:smooth_app/services/ownership_local_db.dart';

void main() {
  late OwnershipLocalDb db;

  setUpAll(() {
    final List<int> bytes = File('assets/ownership/ownership_db.json.gz').readAsBytesSync();
    db = OwnershipLocalDb.fromJson(jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    OwnerOverrides.instance.resetForTest();
  });

  tearDown(OwnerOverrides.instance.resetForTest);

  test('a correction wins over the database for any brand on the pack', () async {
    expect(db.lookup(barcode: '7622210449283', brands: 'Prince, LU')!.owner, contains('Mondelez'));
    await OwnerOverrides.instance.set(barcode: '7622210449283', brands: 'Prince, LU', owner: ' Someone Else ');
    final LocalOwnerResult r = db.lookup(barcode: '7622210449283', brands: 'Prince, LU')!;
    expect(r.owner, 'Someone Else');
    expect(r.source, LocalOwnerSource.user);
    // Same brand, other product and spelling.
    expect(db.lookup(barcode: '7622210000000', brands: 'PRINCE')!.owner, 'Someone Else');
    await OwnerOverrides.instance.remove(barcode: '7622210449283', brands: 'Prince, LU');
    expect(db.lookup(barcode: '7622210449283', brands: 'Prince, LU')!.owner, contains('Mondelez'));
  });

  test('without a brand the barcode is the key; saved on the phone', () async {
    await OwnerOverrides.instance.set(barcode: '5701234567890', brands: null, owner: 'Arla Foods');
    expect(OwnerOverrides.instance.ownerFor(barcode: '5701234567899'), isNull);
    OwnerOverrides.instance.resetForTest();
    await OwnerOverrides.instance.load();
    expect(OwnerOverrides.instance.ownerFor(barcode: '5701234567890'), 'Arla Foods');
  });

  test('lists corrections newest first with the brand as typed; undo puts one back', () async {
    final OwnerOverrides o = OwnerOverrides.instance;
    await o.set(barcode: '1', brands: 'bio, Prince', owner: 'A');
    await o.set(barcode: '2', brands: null, owner: 'B');
    expect(o.all.map((OwnerCorrection c) => '${c.label}=${c.owner}'), <String>['2=B', 'Prince=A']);
    expect(o.all.first.isBarcode, isTrue);
    final OwnerCorrection prince = o.all.last;
    await o.removeCorrection(prince);
    expect(o.ownerFor(barcode: '9', brands: 'PRINCE'), isNull);
    await o.restore(prince);
    o.resetForTest();
    await o.load();
    expect(o.ownerFor(barcode: '9', brands: 'PRINCE'), 'A');
  });

  test('an empty name removes the correction', () async {
    await OwnerOverrides.instance.set(barcode: '1', brands: 'Foo', owner: 'Bar');
    await OwnerOverrides.instance.set(barcode: '1', brands: 'Foo', owner: '  ');
    expect(OwnerOverrides.instance.isEmpty, isTrue);
  });

  test('a corrected subsidiary is followed up to its owner', () async {
    expect(db.ownerOfCompany('Nestlé Suisse'), 'Nestlé');
    expect(db.ownerOfCompany('Mondelez Danmark ApS'), contains('Mondelez'));
    await OwnerOverrides.instance.set(barcode: '1', brands: 'Foo', owner: 'Nestlé Suisse');
    final LocalOwnerResult r = db.lookup(barcode: '1', brands: 'Foo')!;
    expect(r.source, LocalOwnerSource.user);
    expect(r.owner, 'Nestlé');
    expect(r.chain, <String>['Nestlé Suisse', 'Nestlé']);
    // A name the data does not know stays as typed.
    await OwnerOverrides.instance.set(barcode: '1', brands: 'Foo', owner: 'Zzqx Holding');
    expect(db.lookup(barcode: '1', brands: 'Foo')!.owner, 'Zzqx Holding');
  });
}
