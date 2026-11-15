import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_app/services/avoided_owners.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/owner_directory.dart';
import 'package:smooth_app/services/ownership_local_db.dart';

void main() {
  group('AvoidedOwners', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      AvoidedOwners.instance.resetForTest();
    });

    test('matches any of the names an owner goes by, normalised', () async {
      final AvoidedOwners a = AvoidedOwners.instance;
      await a.load();
      expect(a.isAvoided(<String>['Nestlé']), isFalse);
      await a.add('Nestlé');
      expect(a.isAvoided(<String>['NESTLE']), isTrue);
      expect(a.avoidedName(<String?>[null, 'Nesquik', 'Nestle']), 'Nestlé');
      expect(a.isAvoided(<String>['Unilever']), isFalse);
      await a.toggle('nestle');
      expect(a.isEmpty, isTrue);
    });

    test('the "hide in search" choice is saved too', () async {
      await AvoidedOwners.instance.load();
      expect(AvoidedOwners.instance.hideInSearch, isFalse);
      await AvoidedOwners.instance.setHideInSearch(true);
      AvoidedOwners.instance.resetForTest();
      await AvoidedOwners.instance.load();
      expect(AvoidedOwners.instance.hideInSearch, isTrue);
    });

    test('is saved on the phone', () async {
      await AvoidedOwners.instance.add('Coca-Cola');
      AvoidedOwners.instance.resetForTest();
      await AvoidedOwners.instance.load();
      expect(AvoidedOwners.instance.names, <String>['Coca-Cola']);
    });
  });

  group('OwnerDirectory', () {
    late OwnerDirectory dir;

    setUpAll(() {
      final OwnershipLocalDb db = OwnershipLocalDb.fromJson(
        jsonDecode(utf8.decode(gzip.decode(File(OwnershipLocalDb.assetPath).readAsBytesSync())))
            as Map<String, dynamic>,
      );
      final EthicsDb ethics = EthicsDb.fromJson(
        jsonDecode(File(EthicsDb.assetPath).readAsStringSync()) as Map<String, dynamic>,
      );
      dir = OwnerDirectory(db, ethics);
    });

    test('finds companies by the start of their name or a word in it', () {
      expect(dir.search('nestl').first.name, 'Nestlé');
      expect(dir.search('unilev').first.name, 'Unilever');
      expect(dir.search('cola').map((OwnerRef r) => r.name), contains('The Coca-Cola Company'));
    });

    test('a known brand name of a company finds the company', () {
      expect(dir.search('twinings').map((OwnerRef r) => r.name), contains('Associated British Foods'));
    });

    test('short or unknown text finds nothing', () {
      expect(dir.search('ne'), isEmpty);
      expect(dir.search('zzqxw'), isEmpty);
    });
  });
}
