import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/pages/navigator/app_navigator.dart';
import 'package:smooth_app/pages/product/product_page/overview/overview_card.dart';
import 'package:smooth_app/pages/search/search_hit_tile.dart';
import 'package:smooth_app/services/avoided_owners.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/nutriscore_estimate.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/ownership_norm.dart';
import 'package:smooth_app/services/product_search_service.dart';
import 'package:smooth_app/widgets/cal_ui.dart';

/// Picks better products in the same category: a better Nutri-Score first,
/// then a better ethics score for the owner, then popularity.
class AlternativesFinder {
  AlternativesFinder({
    required this.service,
    this.ownerDb,
    this.ethicsDb,
  });

  final ProductSearchService service;
  final OwnershipLocalDb? ownerDb;
  final EthicsDb? ethicsDb;

  static const List<String> grades = <String>['a', 'b', 'c', 'd', 'e'];

  static final RegExp _canonical = RegExp(r'^en:[a-z0-9]+(-[a-z0-9]+)*$');

  /// Most specific category first, skipping very broad ones.
  static List<String> candidateCategories(final List<String>? tags) {
    // Only canonical taxonomy tags; user-typed ones ("en:Pâtes à tartiner")
    // match nothing in the search index.
    final List<String> t = (tags ?? const <String>[])
        .where(_canonical.hasMatch)
        .toList();
    if (t.isEmpty) {
      return const <String>[];
    }
    // OFF lists categories from broad to specific.
    final List<String> specificFirst = t.reversed.toList();
    return specificFirst.take(3).toList();
  }

  Future<List<SearchHit>> find(
    final Product product, {
    final int limit = 5,
    final String? countryTag,
    final List<String> langs = const <String>['en'],
  }) async {
    final String? official = product.nutriscore?.toLowerCase();
    if (official == 'not-applicable') {
      // No Nutri-Score for this kind of product (e.g. alcohol).
      return const <SearchHit>[];
    }
    final String? grade = grades.contains(official) ? official : NutriScoreEstimate.fromProduct(product);
    final int current = grade == null ? -1 : grades.indexOf(grade);
    final LocalOwnerResult? owner = ownerDb?.lookup(
      barcode: product.barcode ?? '',
      brands: product.brands,
      countryTags: product.countriesTags ?? const <String>[],
    );
    final EthicsCompany? company = owner == null ? null : ethicsDb?.forOwner(owner.owner, chain: owner.ethicsChain);
    final List<String> ownerNames = owner == null
        ? const <String>[]
        : <String>[owner.owner, ...owner.ethicsChain, ?company?.name];
    final int? currentEthics = company == null ? null : EthicsScore.compute(company).score;
    if (current == 0 && currentEthics == null) {
      // Already A, and nothing to compare the owner with.
      return const <SearchHit>[];
    }
    for (final String category in candidateCategories(product.categoriesTags)) {
      final SearchHitsPage page = await service.search(
        ProductSearchService.categoryQuery(category),
        pageSize: 60,
        langs: langs,
        sortBy: '-popularity_key',
      );
      final List<SearchHit> better = pick(
        page.hits,
        barcode: product.barcode,
        currentGrade: current,
        countryTag: countryTag,
        limit: limit,
        currentOwnerNames: ownerNames,
        currentEthics: currentEthics,
        isAvoided: (List<String> names) => AvoidedOwners.instance.isAvoided(names),
      );
      if (better.length >= 2) {
        return better;
      }
    }
    return const <SearchHit>[];
  }

  /// Pure ranking step, kept separate so it can be tested without HTTP.
  ///
  /// A candidate is either healthier (a better Nutri-Score), or as healthy
  /// and made by a clearly better-rated company. Never the same owner as the
  /// product, and never an owner on the user's avoid list.
  List<SearchHit> pick(
    final List<SearchHit> hits, {
    required final String? barcode,
    required final int currentGrade,
    final String? countryTag,
    final int limit = 5,
    final List<String> currentOwnerNames = const <String>[],
    final int? currentEthics,
    final bool Function(List<String> ownerNames)? isAvoided,
  }) {
    final Set<String> sameOwner = currentOwnerNames.map(OwnershipNorm.normCore).toSet();
    final Map<SearchHit, OwnerInfo?> info = <SearchHit, OwnerInfo?>{};
    OwnerInfo? ownerOf(final SearchHit h) =>
        info.putIfAbsent(h, () => SearchHitTile.ownerInfo(h, ownerDb, ethicsDb));
    final List<SearchHit> candidates = ProductSearchService.dedupe(
      hits.where((SearchHit h) {
        if (h.barcode == barcode || h.nutriscoreGrade == null) {
          return false;
        }
        final OwnerInfo? o = ownerOf(h);
        if (o != null) {
          if (o.names.any((String n) => sameOwner.contains(OwnershipNorm.normCore(n)))) {
            return false;
          }
          if (isAvoided?.call(o.names) ?? false) {
            return false;
          }
        }
        final int g = grades.indexOf(h.nutriscoreGrade!);
        // Unknown current grade: anything A or B is a fair suggestion.
        final bool healthier = currentGrade < 0 ? g <= 1 : g < currentGrade;
        final bool fairer = currentEthics != null &&
            (o?.ethicsScore ?? -1) >= currentEthics + 15 &&
            (currentGrade < 0 ? g <= 2 : g <= currentGrade);
        return healthier || fairer;
      }),
    );
    final Map<SearchHit, int> ethicsCache = <SearchHit, int>{
      for (final SearchHit h in candidates) h: ownerOf(h)?.ethicsScore ?? 50,
    };
    final List<MapEntry<int, SearchHit>> indexed = candidates.asMap().entries.toList()
      ..sort((MapEntry<int, SearchHit> a, MapEntry<int, SearchHit> b) {
        final int byGrade =
            grades.indexOf(a.value.nutriscoreGrade!) - grades.indexOf(b.value.nutriscoreGrade!);
        if (byGrade != 0) {
          return byGrade;
        }
        final bool aLocal = countryTag != null && a.value.countriesTags.contains(countryTag);
        final bool bLocal = countryTag != null && b.value.countriesTags.contains(countryTag);
        if (aLocal != bLocal) {
          return aLocal ? -1 : 1;
        }
        final int byEthics = ethicsCache[b.value]! - ethicsCache[a.value]!;
        return byEthics != 0 ? byEthics : a.key - b.key;
      });
    return indexed.map((MapEntry<int, SearchHit> e) => e.value).take(limit).toList();
  }
}

/// "Better alternatives" on the product overview.
class AlternativesSection extends StatefulWidget {
  const AlternativesSection({
    required this.product,
    this.service,
    this.onLoaded,
    super.key,
  });

  final Product product;
  final ProductSearchService? service;

  /// Called once the search is done: true when there is something to show.
  final ValueChanged<bool>? onLoaded;

  @override
  State<AlternativesSection> createState() => _AlternativesSectionState();
}

class _AlternativesSectionState extends State<AlternativesSection> {
  List<SearchHit>? _hits;
  OwnershipLocalDb? _ownerDb;
  EthicsDb? _ethicsDb;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final List<Object?> dbs = await Future.wait(<Future<Object?>>[
        OwnershipLocalDb.load().then<Object?>((OwnershipLocalDb d) => d, onError: (_) => null),
        EthicsDb.load().then<Object?>((EthicsDb d) => d, onError: (_) => null),
      ]);
      _ownerDb = dbs[0] as OwnershipLocalDb?;
      _ethicsDb = dbs[1] as EthicsDb?;
      final List<SearchHit> hits = await AlternativesFinder(
        service: widget.service ?? ProductSearchService(),
        ownerDb: _ownerDb,
        ethicsDb: _ethicsDb,
      ).find(widget.product, countryTag: userCountryTag(), langs: userSearchLangs());
      if (mounted) {
        setState(() => _hits = hits);
        widget.onLoaded?.call(hits.isNotEmpty);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _failed = true);
        widget.onLoaded?.call(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<SearchHit>? hits = _hits;
    if (_failed || (hits != null && hits.isEmpty)) {
      return EMPTY_WIDGET;
    }
    final String? official = widget.product.nutriscore;
    final String? grade = AlternativesFinder.grades.contains(official)
        ? official
        : NutriScoreEstimate.fromProduct(widget.product);
    final bool knownGrade = grade != null;
    return OverviewCard(
      padding: const EdgeInsetsDirectional.only(top: LARGE_SPACE, bottom: SMALL_SPACE),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: LARGE_SPACE),
            child: OverviewHeading(
              title: 'Better alternatives',
              subtitle: knownGrade
                  ? 'Healthier than Nutri-Score ${grade.toUpperCase()}, or from a better-rated company'
                  : 'Healthier, or from a better-rated company',
            ),
          ),
          const SizedBox(height: SMALL_SPACE),
          if (hits == null)
            const Padding(
              padding: EdgeInsetsDirectional.all(LARGE_SPACE),
              child: Center(child: CalLoader()),
            )
          else
            for (final SearchHit hit in hits)
              SearchHitTile(
                hit: hit,
                dense: true,
                ownerDb: _ownerDb,
                ethicsDb: _ethicsDb,
                onTap: () => AppNavigator.of(context).push(AppRoutes.PRODUCT_LOADER(hit.barcode)),
              ),
        ],
      ),
    );
  }
}
