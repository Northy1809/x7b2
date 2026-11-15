import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/ownership_norm.dart';

void main() {
  group('OwnershipNorm matches research/prefix/norm.py', () {
    final Map<String, dynamic> vectors = jsonDecode(
      File('test/services/fixtures/norm_vectors.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    test('all exported vectors', () {
      final List<String> mismatches = <String>[];
      vectors.forEach((String raw, dynamic expected) {
        final String got = OwnershipNorm.normCore(raw);
        if (got != expected) {
          mismatches.add('$raw -> $got (expected $expected)');
        }
      });
      expect(mismatches, isEmpty);
    });
  });

  group('OwnershipLocalDb', () {
    late OwnershipLocalDb db;

    setUpAll(() {
      final List<int> bytes = File('assets/ownership/ownership_db.json.gz').readAsBytesSync();
      db = OwnershipLocalDb.fromJson(
        jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>,
      );
    });

    test('resolves a well-known brand through Wikidata', () {
      final LocalOwnerResult? r = db.lookup(barcode: '7622210449283', brands: 'Prince, LU');
      expect(r, isNotNull);
      expect(r!.owner, contains('Mondelez'));
    });

    test('store brand from the verified list', () {
      final LocalOwnerResult? r = db.lookup(barcode: '0000000000000', brands: 'Hacendado');
      expect(r, isNotNull);
    });

    test('Lidl own-label barcode prefix resolves unknown sub-brands', () {
      final LocalOwnerResult? r = db.lookup(barcode: '4056489685579', brands: 'Brand that does not exist xyz');
      expect(r, isNotNull);
      expect(r!.source, LocalOwnerSource.barcodePrefix);
    });

    test('stop words are not treated as brands', () {
      expect(db.lookup(barcode: '0000000000000', brands: 'bio'), isNull);
    });

    test('embKeys port matches packager_map.tag_keys', () {
      expect(OwnershipLocalDb.embKeys('es-40-020984-to-ec'), <String>['es-40-020984-to-ec', 'n:es:40.20984.to']);
      expect(OwnershipLocalDb.embKeys('dk-m198-ec'), <String>['dk-m198-ec', 'n:dk:m.198']);
    });

    test('legalCompanyName matches build_db.legal_company', () {
      final Map<String, dynamic> vectors = jsonDecode(
        File('test/services/fixtures/legal_company_vectors.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final List<String> mismatches = <String>[];
      vectors.forEach((String raw, dynamic expected) {
        final String? got = OwnershipLocalDb.legalCompanyName(raw);
        if (got != expected) {
          mismatches.add('$raw -> $got (expected $expected)');
        }
      });
      expect(mismatches, isEmpty);
    });

    test('company name in the brand field is the owner, the bare name is not', () {
      final LocalOwnerResult? r = db.lookup(barcode: '0000000000017', brands: 'Zzqx Konserven GmbH');
      expect(r, isNotNull);
      expect(r!.owner, 'Zzqx Konserven GmbH');
      expect(r.source, LocalOwnerSource.labelCompany);
      expect(db.lookup(barcode: '0000000000017', brands: 'Zzqx Konserven'), isNull);
    });

    test('unknown everything returns null instead of guessing', () {
      expect(db.lookup(barcode: '0000000000017', brands: 'zzzz qqqq unknown brand'), isNull);
    });

    // 2026-11-08 audit of the most scanned products.
    test('a controlling person is shown as "controlled by", not as the owner', () {
      final LocalOwnerResult? r = db.lookup(barcode: '0000000000017', brands: 'Président');
      expect(r!.owner, 'Lactalis');
      expect(r.controlledBy, 'Emmanuel Besnier');
      expect(r.ethicsChain.first, 'Emmanuel Besnier');
    });

    test('name collisions with non-food companies are gone', () {
      expect(db.lookup(barcode: '0000000000017', brands: 'BG')?.owner, isNot('Shell'));
      expect(db.lookup(barcode: '5701111000001', brands: 'Kohberg')?.owner, 'Koff A/S');
    });

    test('research notes are stripped from owner names', () {
      expect(db.lookup(barcode: '0000000000017', brands: 'Cointreau')!.owner, 'Rémy Cointreau SA');
    });

    test('a local company name falls back to its brand', () {
      final LocalOwnerResult? r = db.lookup(barcode: '0000000000017', brands: "L'OREAL NORGE AS");
      expect(r?.owner, contains('Oréal'));
      expect(r!.source, LocalOwnerSource.companyName);
    });

    test('Coop Danmark is owned by Coop amba', () {
      expect(db.lookup(barcode: '0000000000017', brands: 'Kvickly')!.owner, 'Coop amba');
    });
  });

  test('a brand that is its own owner loses to a group named on the pack', () {
    final OwnershipLocalDb db = OwnershipLocalDb.fromJson(<String, dynamic>{
      'strings': <String>['Maizena', 'Unilever'],
      'brands': <String, dynamic>{
        'maizena': <dynamic>[0, 'w', <int>[0], ''],
        'unilever': <dynamic>[1, 'w', <int>[1], ''],
      },
      'by_country': <String, dynamic>{},
      'prefix': <String, dynamic>{},
      'emb': <String, dynamic>{},
      'companies': <String, dynamic>{},
      'top': <String, dynamic>{
        '1': <String>['Knorr'],
      },
    });
    expect(db.lookup(barcode: '0', brands: 'MAIZENA, Unilever')!.owner, 'Unilever');
    expect(db.lookup(barcode: '0', brands: 'Maizena')!.owner, 'Maizena');
  });

  test('a legal company on the pack is followed up to its parent', () {
    final OwnershipLocalDb db = OwnershipLocalDb.fromJson(<String, dynamic>{
      'strings': <String>['Associated British Foods'],
      'brands': <String, dynamic>{},
      'by_country': <String, dynamic>{},
      'prefix': <String, dynamic>{},
      'emb': <String, dynamic>{},
      'companies': <String, dynamic>{'jordans ryvita company': 0},
    });
    final LocalOwnerResult r = db.lookup(barcode: '0', brands: 'Jordans Ryvita Company Ltd')!;
    expect(r.owner, 'Associated British Foods');
    expect(r.chain, <String>['Jordans Ryvita Company Ltd', 'Associated British Foods']);
  });

  test('topBrandsOf finds the owner by normalised name', () {
    final OwnershipLocalDb db = OwnershipLocalDb.fromJson(<String, dynamic>{
      'strings': <String>['Nestlé', 'Ferrero SpA'],
      'brands': <String, dynamic>{},
      'by_country': <String, dynamic>{},
      'prefix': <String, dynamic>{},
      'emb': <String, dynamic>{},
      'companies': <String, dynamic>{},
      'top': <String, dynamic>{
        '0': <String>['Maggi', 'Nescafe', 'KitKat'],
      },
    });
    expect(db.topBrandsOf('Nestlé'), <String>['Maggi', 'Nescafe', 'KitKat']);
    expect(db.topBrandsOf('NESTLE'), <String>['Maggi', 'Nescafe', 'KitKat']);
    expect(db.topBrandsOf('Ferrero SpA'), isEmpty);
  });
}
