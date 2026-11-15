import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_app/services/brand_text_matcher.dart';
import 'package:smooth_app/services/label_ocr.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/ownership_service.dart';
import 'package:smooth_app/services/photo_analyzer.dart';

OwnershipLocalDb _db() => OwnershipLocalDb.fromJson(<String, dynamic>{
  'strings': <String>['Ferrero SpA', 'Nutella', 'Nestlé', 'Nesquik', 'ARGE Heumilch', 'Lurpak', 'Arla Foods', 'Kinder'],
  'brands': <String, dynamic>{
    'nutella': <dynamic>[0, 'w', <int>[1, 0], ''],
    'kinder': <dynamic>[0, 'w', <int>[7, 0], ''],
    'nesquik': <dynamic>[2, 'w', <int>[3, 2], ''],
    // A real DB oddity: "lait" (milk) is a brand of some small company.
    'lait': <dynamic>[4, 'w', <int>[4], ''],
    'lurpak': <dynamic>[6, 'w', <int>[5, 6], ''],
  },
  'by_country': <String, dynamic>{},
  'prefix': <String, dynamic>{},
  'emb': <String, dynamic>{},
  'companies': <String, dynamic>{'arla foods': 6, 'arla foods amba': 6},
});

class _FakeOcr implements LabelOcr {
  const _FakeOcr(this.lines);

  final List<PackTextLine> lines;

  @override
  Future<LabelText> readLines(String imagePath) async =>
      LabelText(lines.map((PackTextLine l) => l.text).join('\n'), lines);

  @override
  Future<String> readText(String imagePath) async => (await readLines(imagePath)).text;
}

void main() {
  group('BrandTextMatcher', () {
    test('finds the brand in the biggest text', () {
      final List<BrandCandidate> c = BrandTextMatcher(_db(), const <String>{}).match(const <PackTextLine>[
        PackTextLine('pâte à tartiner aux noisettes', 20.0),
        PackTextLine('NUTELLA', 110.0),
        PackTextLine('Nesquik inside', 12.0),
      ]);
      expect(c.first.name, 'Nutella');
      expect(c.first.owner.owner, 'Ferrero SpA');
      expect(c.map((BrandCandidate b) => b.owner.owner), contains('Nestlé'));
    });

    test('skips pack words, even when the DB has them as a brand', () {
      final BrandTextMatcher m = BrandTextMatcher(_db(), const <String>{'lait'});
      expect(m.match(const <PackTextLine>[PackTextLine('LAIT', 100.0)]), isEmpty);
      // Without the list, "lait" would have been taken for a brand.
      expect(BrandTextMatcher(_db(), const <String>{}).match(const <PackTextLine>[PackTextLine('LAIT', 100.0)]), isNotEmpty);
    });

    test('one candidate per owner', () {
      final List<BrandCandidate> c = BrandTextMatcher(_db(), const <String>{}).match(const <PackTextLine>[
        PackTextLine('Kinder', 80.0),
        PackTextLine('Nutella', 40.0),
      ]);
      expect(c, hasLength(1));
      expect(c.single.name, 'Kinder');
    });

    test('nothing to read', () {
      expect(BrandTextMatcher(_db(), const <String>{}).match(const <PackTextLine>[]), isEmpty);
      expect(
        BrandTextMatcher(_db(), const <String>{}).match(const <PackTextLine>[PackTextLine('400 g', 50.0)]),
        isEmpty,
      );
    });

    test('the bundled pack-word list loads and blocks known traps', () {
      final Set<String> words = BrandTextMatcher.parsePackWords(
        File(BrandTextMatcher.packWordsAsset).readAsStringSync(),
      );
      expect(words, containsAll(<String>['lait', 'pesto', 'nutri', 'chips']));
      expect(words, isNot(contains('nutella')));
      expect(words.any((String w) => w.startsWith('#')), isFalse);
    });
  });

  group('PhotoAnalyzer', () {
    PhotoAnalyzer analyzer(final List<PackTextLine> lines, {String? barcode, BrandOwnerResult? online}) => PhotoAnalyzer(
      ocr: _FakeOcr(lines),
      readBarcode: (_) async => barcode,
      localDb: () async => _db(),
      packWords: () async => const <String>{},
      online: (_) async => online,
    );

    test('a barcode in the photo is read, and the brand too (for an unknown barcode)', () async {
      final PhotoAnalysis a = await analyzer(const <PackTextLine>[PackTextLine('Nutella', 9.0)], barcode: '3017620422003')
          .analyze('x.jpg');
      expect(a.barcode, '3017620422003');
      expect(a.brands.single.owner.owner, 'Ferrero SpA');
    });

    test('a barcode with no brand on the photo: nothing guessed online', () async {
      final PhotoAnalysis a = await analyzer(
        const <PackTextLine>[PackTextLine('Gillette', 90.0)],
        barcode: '3017620422003',
        online: BrandOwnerResult(
          ownerCompany: 'Procter & Gamble',
          ownerChain: const <String>['Gillette', 'Procter & Gamble'],
          source: BrandOwnerSource.wikidata,
        ),
      ).analyze('x.jpg');
      expect(a.barcode, '3017620422003');
      expect(a.brands, isEmpty);
    });

    test('brand on the front, then the company named on the label', () async {
      final List<int> steps = <int>[];
      final PhotoAnalysis a = await analyzer(const <PackTextLine>[
        PackTextLine('Nesquik', 90.0),
        PackTextLine('Fremstillet for: Arla Foods amba', 10.0),
        PackTextLine('Sønderhøj 14, 8260 Viby J', 10.0),
      ]).analyze('x.jpg', onStep: steps.add);
      expect(a.brands.first.owner.owner, 'Nestlé');
      expect(a.brands.map((BrandCandidate b) => b.owner.owner), contains('Arla Foods'));
      expect(steps, <int>[0, 1, 2, 3]);
    });

    test('nothing offline: asks Wikidata about the biggest words', () async {
      final PhotoAnalysis a = await analyzer(
        const <PackTextLine>[PackTextLine('Gillette', 90.0)],
        online: BrandOwnerResult(
          ownerCompany: 'Procter & Gamble',
          ownerChain: const <String>['Gillette', 'Procter & Gamble'],
          source: BrandOwnerSource.wikidata,
        ),
      ).analyze('x.jpg');
      expect(a.brands.single.owner.owner, 'Procter & Gamble');
      expect(a.brands.single.name, 'Gillette');
    });

    test('a failing reader never throws', () async {
      final PhotoAnalysis a = await PhotoAnalyzer(
        ocr: const _FakeOcr(<PackTextLine>[]),
        readBarcode: (_) async => throw Exception('no camera'),
        localDb: () async => throw Exception('no db'),
        packWords: () async => const <String>{},
        online: (_) async => null,
      ).analyze('x.jpg');
      expect(a.isEmpty, isTrue);
    });
  });
}
