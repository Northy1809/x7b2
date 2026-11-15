import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:smooth_app/services/ownership_norm.dart';
import 'package:smooth_app/services/score_types.dart';

/// The three things the ethics score looks at.
enum EthicsCategory {
  climate('climate', 'Climate & environment', 'Emissions, deforestation, plastic and water'),
  people(
    'people',
    'People & workers',
    'Child labour, forced labour and conditions for workers and farmers',
  ),
  conduct(
    'conduct',
    'Honesty & responsibility',
    'Unethical marketing, misleading claims, food safety, animal welfare and corruption',
  );

  const EthicsCategory(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  static EthicsCategory? fromKey(final String? key) {
    for (final EthicsCategory c in values) {
      if (c.key == key) {
        return c;
      }
    }
    return null;
  }
}

/// A documented case (bad) or practice (good) for a company, always with
/// at least one source.
class EthicsItem {
  const EthicsItem({
    required this.category,
    required this.title,
    required this.text,
    required this.sources,
    this.severity = 0,
    this.year,
  });

  /// [severity] comes from the JSON for issues; good practices get 0 and
  /// neutral notes -1.
  factory EthicsItem.fromJson(final Map<String, dynamic> json, {required final int? severity}) =>
      EthicsItem(
        category: EthicsCategory.fromKey(json['cat'] as String?) ?? EthicsCategory.conduct,
        title: json['title'] as String,
        text: json['text'] as String? ?? '',
        severity: severity ?? ((json['sev'] as num?)?.toInt() ?? 1).clamp(1, 3),
        year: (json['year'] as num?)?.toInt(),
        sources: (json['sources'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(SourceLink.fromJson)
            .toList(),
      );

  final EthicsCategory category;
  final String title;
  final String text;

  /// 1 = minor, 2 = serious, 3 = very serious. 0 for good practices,
  /// -1 for neutral notes (e.g. a middling benchmark score).
  final int severity;

  /// Latest year the case was documented as ongoing (or happened).
  final int? year;
  final List<SourceLink> sources;

  bool get isGood => severity == 0;

  bool get isNote => severity < 0;

  String get severityLabel => switch (severity) {
    3 => 'Very serious',
    2 => 'Serious',
    1 => 'Minor',
    0 => 'Good practice',
    _ => 'For information',
  };
}

class EthicsCompany {
  const EthicsCompany({
    required this.id,
    required this.name,
    required this.about,
    required this.issues,
    required this.good,
    this.notes = const <EthicsItem>[],
    this.matchNames = const <String>[],
  });

  factory EthicsCompany.fromJson(final Map<String, dynamic> json) => EthicsCompany(
    id: json['id'] as String,
    name: json['name'] as String,
    about: json['about'] as String? ?? '',
    matchNames: (json['match'] as List<dynamic>? ?? const <dynamic>[]).whereType<String>().toList(),
    issues: (json['issues'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> j) => EthicsItem.fromJson(j, severity: null))
        .where((EthicsItem i) => i.sources.isNotEmpty)
        .toList(),
    good: (json['good'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> j) => EthicsItem.fromJson(j, severity: 0))
        .where((EthicsItem i) => i.sources.isNotEmpty)
        .toList(),
    notes: (json['notes'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> j) => EthicsItem.fromJson(j, severity: -1))
        .where((EthicsItem i) => i.sources.isNotEmpty)
        .toList(),
  );

  final String id;
  final String name;
  final String about;
  final List<String> matchNames;
  final List<EthicsItem> issues;
  final List<EthicsItem> good;
  final List<EthicsItem> notes;
}

class EthicsCategoryScore {
  const EthicsCategoryScore({
    required this.category,
    required this.score,
    required this.issues,
    required this.good,
    this.notes = const <EthicsItem>[],
  });

  final EthicsCategory category;
  final int score;
  final List<EthicsItem> issues;
  final List<EthicsItem> good;
  final List<EthicsItem> notes;

  /// Nothing documented either way in this category.
  bool get isEmpty => issues.isEmpty && good.isEmpty && notes.isEmpty;
}

class EthicsScoreResult {
  const EthicsScoreResult({required this.company, required this.score, required this.categories});

  final EthicsCompany company;
  final int score;
  final List<EthicsCategoryScore> categories;

  ScoreBand get band => ScoreBand.of(score);
}

/// Transparent ethics score from documented, sourced cases.
///
/// Every category starts at [baseline] (a company we researched without
/// finding documented problems). Each problem subtracts by severity, less
/// for old cases; each good practice adds [goodBonus]. The total is the
/// average of the three categories.
class EthicsScore {
  const EthicsScore._();

  static const int baseline = 70;
  static const int goodBonus = 15;
  static const Map<int, int> deduction = <int, int>{1: 15, 2: 30, 3: 45};

  /// Full weight for cases in the last 10 years, then less.
  static double ageFactor(final int? year, final int currentYear) {
    if (year == null) {
      return 1.0;
    }
    final int age = currentYear - year;
    if (age <= 10) {
      return 1.0;
    }
    if (age <= 25) {
      return 0.6;
    }
    return 0.3;
  }

  static EthicsScoreResult compute(final EthicsCompany company, {final int? currentYear}) {
    final int now = currentYear ?? DateTime.now().year;
    final List<EthicsCategoryScore> categories = <EthicsCategoryScore>[];
    for (final EthicsCategory c in EthicsCategory.values) {
      final List<EthicsItem> issues = company.issues.where((EthicsItem i) => i.category == c).toList()
        ..sort((EthicsItem a, EthicsItem b) {
          final int bySeverity = b.severity - a.severity;
          return bySeverity != 0 ? bySeverity : (b.year ?? 0) - (a.year ?? 0);
        });
      final List<EthicsItem> good = company.good.where((EthicsItem i) => i.category == c).toList();
      final List<EthicsItem> notes = company.notes.where((EthicsItem i) => i.category == c).toList();
      double score = baseline.toDouble() + goodBonus * good.length;
      for (final EthicsItem i in issues) {
        score -= (deduction[i.severity] ?? 15) * ageFactor(i.year, now);
      }
      categories.add(
        EthicsCategoryScore(
          category: c,
          score: score.round().clamp(0, 100),
          issues: issues,
          good: good,
          notes: notes,
        ),
      );
    }
    final int total =
        (categories.fold<int>(0, (int sum, EthicsCategoryScore c) => sum + c.score) / categories.length).round();
    return EthicsScoreResult(company: company, score: total, categories: categories);
  }
}

/// Bundled, hand-checked ethics data (assets/ethics/ethics_db.json, built
/// from research/ethics/companies/*.json). Every item links to its sources.
class EthicsDb {
  EthicsDb._(this.companies, this.updated) {
    for (final EthicsCompany c in companies) {
      for (final String name in <String>[c.name, ...c.matchNames]) {
        _byName.putIfAbsent(OwnershipNorm.normCore(name), () => c);
      }
    }
  }

  static const String assetPath = 'assets/ethics/ethics_db.json';
  static Future<EthicsDb>? _instance;

  final List<EthicsCompany> companies;
  final String updated;
  final Map<String, EthicsCompany> _byName = <String, EthicsCompany>{};

  static Future<EthicsDb> load() => _instance ??= rootBundle
      .loadString(assetPath)
      .then((String s) => compute(_decode, s))
      .then(EthicsDb.fromJson);

  static Map<String, dynamic> _decode(final String s) => jsonDecode(s) as Map<String, dynamic>;

  @visibleForTesting
  static EthicsDb fromJson(final Map<String, dynamic> json) => EthicsDb._(
    (json['companies'] as List<dynamic>).whereType<Map<String, dynamic>>().map(EthicsCompany.fromJson).toList(),
    json['updated'] as String? ?? '',
  );

  EthicsCompany? byName(final String name) => _byName[OwnershipNorm.normCore(name)];

  /// The company to rate for an ownership answer: the owner itself, or the
  /// nearest company in the chain we have data on (top owner first).
  EthicsCompany? forOwner(final String owner, {final List<String> chain = const <String>[]}) {
    final EthicsCompany? direct = byName(owner);
    if (direct != null) {
      return direct;
    }
    for (final String name in chain.reversed) {
      final EthicsCompany? c = byName(name);
      if (c != null) {
        return c;
      }
    }
    // "Aldi Nord / Aldi Süd": two separate companies, and the data cannot tell
    // which one made the product. Rate it by the lower of the two.
    final List<String> parts = splitOwner(owner);
    if (parts.length > 1) {
      final List<EthicsCompany> found = <EthicsCompany>[
        for (final String p in parts) ?byName(p),
      ];
      if (found.length == parts.length) {
        found.sort(
          (EthicsCompany a, EthicsCompany b) => EthicsScore.compute(a).score.compareTo(EthicsScore.compute(b).score),
        );
        return found.first;
      }
    }
    return null;
  }

  /// "Aldi Nord / Aldi Süd" -> both names; a normal owner -> itself.
  static List<String> splitOwner(final String owner) =>
      owner.split(' / ').map((String s) => s.trim()).where((String s) => s.isNotEmpty).toList();

  /// The name to show for an owner: the researched company's name, except
  /// for a two-company owner, which keeps both names.
  static String displayName(final String owner, final EthicsCompany? company) =>
      company == null || splitOwner(owner).length > 1 ? owner : company.name;
}
