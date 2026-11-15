import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/score_types.dart';

Map<String, dynamic> _src() => <String, dynamic>{'title': 'Kilde', 'url': 'https://example.org/a'};

Map<String, dynamic> _company({
  final List<Map<String, dynamic>> issues = const <Map<String, dynamic>>[],
  final List<Map<String, dynamic>> good = const <Map<String, dynamic>>[],
  final List<Map<String, dynamic>> notes = const <Map<String, dynamic>>[],
}) => <String, dynamic>{
  'id': 'acme',
  'name': 'Acme Foods',
  'match': <String>['Acme Foods A/S', 'Acme'],
  'about': 'Testfirma',
  'issues': issues,
  'good': good,
  'notes': notes,
};

Map<String, dynamic> _issue(final String cat, final int sev, final int year) => <String, dynamic>{
  'cat': cat,
  'sev': sev,
  'year': year,
  'title': 'Sag $cat $sev',
  'text': 'Tekst',
  'sources': <dynamic>[_src()],
};

void main() {
  group('EthicsScore', () {
    test('a researched company without cases scores the baseline', () {
      final EthicsScoreResult r = EthicsScore.compute(
        EthicsCompany.fromJson(_company()),
        currentYear: 2026,
      );
      expect(r.score, EthicsScore.baseline);
      expect(r.categories.every((EthicsCategoryScore c) => c.isEmpty), isTrue);
    });

    test('severity and age decide the deduction', () {
      final EthicsScoreResult r = EthicsScore.compute(
        EthicsCompany.fromJson(
          _company(
            issues: <Map<String, dynamic>>[
              _issue('people', 3, 2024), // -45
              _issue('climate', 2, 2010), // -30 * 0.6 = -18
              _issue('conduct', 1, 1990), // -15 * 0.3 = -4.5
            ],
          ),
        ),
        currentYear: 2026,
      );
      final Map<EthicsCategory, int> by = <EthicsCategory, int>{
        for (final EthicsCategoryScore c in r.categories) c.category: c.score,
      };
      expect(by[EthicsCategory.people], 25);
      expect(by[EthicsCategory.climate], 52);
      expect(by[EthicsCategory.conduct], 66); // 65.5 rounds up
      expect(r.score, ((25 + 52 + 66) / 3).round());
      expect(r.band, ScoreBand.mediocre);
    });

    test('good practice adds, notes change nothing, scores stay in 0-100', () {
      final EthicsScoreResult r = EthicsScore.compute(
        EthicsCompany.fromJson(
          _company(
            issues: <Map<String, dynamic>>[
              for (int i = 0; i < 4; i++) _issue('people', 3, 2025),
            ],
            good: <Map<String, dynamic>>[
              for (int i = 0; i < 3; i++)
                <String, dynamic>{'cat': 'climate', 'title': 'God $i', 'sources': <dynamic>[_src()]},
            ],
            notes: <Map<String, dynamic>>[
              <String, dynamic>{'cat': 'conduct', 'title': 'Note', 'sources': <dynamic>[_src()]},
            ],
          ),
        ),
        currentYear: 2026,
      );
      final Map<EthicsCategory, EthicsCategoryScore> by = <EthicsCategory, EthicsCategoryScore>{
        for (final EthicsCategoryScore c in r.categories) c.category: c,
      };
      expect(by[EthicsCategory.people]!.score, 0);
      expect(by[EthicsCategory.climate]!.score, 100);
      expect(by[EthicsCategory.conduct]!.score, EthicsScore.baseline);
      expect(by[EthicsCategory.conduct]!.notes.single.isNote, isTrue);
    });

    test('items without sources are dropped, severity is clamped', () {
      final EthicsCompany c = EthicsCompany.fromJson(
        _company(
          issues: <Map<String, dynamic>>[
            <String, dynamic>{'cat': 'people', 'sev': 3, 'year': 2025, 'title': 'Uden kilde', 'sources': <dynamic>[]},
            <String, dynamic>{'cat': 'people', 'sev': 9, 'year': 2025, 'title': 'For høj', 'sources': <dynamic>[_src()]},
          ],
        ),
      );
      expect(c.issues.single.title, 'For høj');
      expect(c.issues.single.severity, 3);
    });

    test('issues are sorted most serious and newest first', () {
      final EthicsScoreResult r = EthicsScore.compute(
        EthicsCompany.fromJson(
          _company(
            issues: <Map<String, dynamic>>[
              _issue('people', 1, 2025),
              _issue('people', 3, 2015),
              _issue('people', 3, 2022),
            ],
          ),
        ),
        currentYear: 2026,
      );
      final List<EthicsItem> issues = r.categories
          .firstWhere((EthicsCategoryScore c) => c.category == EthicsCategory.people)
          .issues;
      expect(issues.map((EthicsItem i) => '${i.severity}/${i.year}'), <String>['3/2022', '3/2015', '1/2025']);
    });
  });

  group('EthicsDb lookup', () {
    final EthicsDb db = EthicsDb.fromJson(<String, dynamic>{
      'companies': <dynamic>[_company()],
    });

    test('matches the name and aliases after normalisation', () {
      expect(db.byName('Acme Foods')?.id, 'acme');
      expect(db.byName('ACME FOODS A/S')?.id, 'acme');
      expect(db.byName('acme')?.id, 'acme');
      expect(db.byName('Other'), isNull);
    });

    test('falls back to the chain, top owner first', () {
      expect(db.forOwner('Unknown Brand Co', chain: <String>['Brand', 'Acme'])?.id, 'acme');
      expect(db.forOwner('Unknown', chain: <String>['Nope']), isNull);
    });
  });

  test('the bundled database is valid', () {
    final Map<String, dynamic> json =
        jsonDecode(File('assets/ethics/ethics_db.json').readAsStringSync()) as Map<String, dynamic>;
    final EthicsDb db = EthicsDb.fromJson(json);
    expect(db.companies.length, greaterThanOrEqualTo(40));
    final Set<String> ids = <String>{};
    for (final EthicsCompany c in db.companies) {
      expect(ids.add(c.id), isTrue, reason: 'duplicate id ${c.id}');
      expect(c.about, isNotEmpty, reason: c.id);
      for (final EthicsItem i in <EthicsItem>[...c.issues, ...c.good, ...c.notes]) {
        expect(i.sources, isNotEmpty, reason: '${c.id}: ${i.title}');
        for (final SourceLink s in i.sources) {
          expect(s.url, startsWith('https://'), reason: '${c.id}: ${i.title}');
        }
        if (!i.isGood && !i.isNote) {
          expect(i.year, isNotNull, reason: '${c.id}: ${i.title}');
        }
      }
      final EthicsScoreResult r = EthicsScore.compute(c, currentYear: 2026);
      expect(r.score, inInclusiveRange(0, 100));
    }
    // Known owners from the ownership database resolve.
    expect(db.forOwner('Nestlé')?.id, 'nestle');
    expect(db.forOwner('Ferrero SpA')?.id, 'ferrero');
    expect(db.forOwner('Schwarz Group')?.id, 'schwarz');
    expect(db.forOwner('Mars, Incorporated')?.id, 'mars');
    // Two separate companies: rated by the lower score, both names shown.
    final EthicsCompany? aldi = db.forOwner('Aldi Nord / Aldi Süd');
    expect(aldi?.id, anyOf('aldi-nord', 'aldi-sud'));
    final int nord = EthicsScore.compute(db.forOwner('Aldi Nord')!).score;
    final int sud = EthicsScore.compute(db.forOwner('Aldi Süd')!).score;
    expect(EthicsScore.compute(aldi!).score, nord < sud ? nord : sud);
    expect(EthicsDb.displayName('Aldi Nord / Aldi Süd', aldi), 'Aldi Nord / Aldi Süd');
    expect(EthicsDb.displayName('Nestlé S.A.', db.forOwner('Nestlé')), 'Nestlé');
  });
}
