import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/pages/navigator/app_navigator.dart';
import 'package:smooth_app/pages/product/product_page/overview/owner_section.dart';
import 'package:smooth_app/pages/product/product_page/overview/score_ring.dart';
import 'package:smooth_app/pages/search/search_hit_tile.dart';
import 'package:smooth_app/query/product_query.dart';
import 'package:smooth_app/services/avoided_owners.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/owner_directory.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/ownership_norm.dart';
import 'package:smooth_app/services/product_search_service.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/company_logo.dart';

/// Suggestions shown while the user types in the product search:
/// matching products (with owner), brands, food categories and
/// earlier searches. Updates ~250 ms after the last keystroke.
class LiveSearchSuggestions extends StatefulWidget {
  const LiveSearchSuggestions({
    required this.text,
    required this.history,
    required this.onSearch,
    required this.onCategory,
    this.service,
  });

  final String text;

  /// Earlier queries, newest first.
  final List<String> history;

  /// Run a normal search for this text.
  final void Function(String query) onSearch;

  /// Show all products in a category.
  final void Function(CategorySuggestion category) onCategory;

  final ProductSearchService? service;

  @override
  State<LiveSearchSuggestions> createState() => _LiveSearchSuggestionsState();
}

class _LiveSearchSuggestionsState extends State<LiveSearchSuggestions> {
  static const Duration _debounce = Duration(milliseconds: 250);

  late final ProductSearchService _service =
      widget.service ?? ProductSearchService();
  Timer? _timer;
  int _requestId = 0;

  /// The text the current results belong to.
  String? _resultText;
  List<SearchHit> _products = const <SearchHit>[];
  List<String> _brands = const <String>[];
  List<CategorySuggestion> _categories = const <CategorySuggestion>[];
  bool _loading = false;
  bool _failed = false;
  OwnershipLocalDb? _ownerDb;
  EthicsDb? _ethicsDb;
  OwnerDirectory? _directory;

  /// Companies matching the text, from the offline data (instant).
  List<OwnerRef> _owners(final String text) {
    if (_ownerDb == null && _ethicsDb == null) {
      return const <OwnerRef>[];
    }
    _directory ??= OwnerDirectory(_ownerDb, _ethicsDb);
    return _directory!.search(text);
  }

  @override
  void initState() {
    super.initState();
    unawaited(
      OwnershipLocalDb.load().then((OwnershipLocalDb db) {
        if (mounted) {
          setState(() {
            _ownerDb = db;
            _directory = null;
          });
        }
      }, onError: (_) {}),
    );
    unawaited(
      EthicsDb.load().then((EthicsDb db) {
        if (mounted) {
          setState(() {
            _ethicsDb = db;
            _directory = null;
          });
        }
      }, onError: (_) {}),
    );
    _schedule();
  }

  @override
  void didUpdateWidget(covariant LiveSearchSuggestions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text.trim() != widget.text.trim()) {
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(_debounce, _fetch);
  }

  Future<void> _fetch() async {
    if (!mounted) {
      return;
    }
    final String text = widget.text.trim();
    final int id = ++_requestId;
    if (text.length < 2) {
      setState(() {
        _resultText = text;
        _products = const <SearchHit>[];
        _brands = const <String>[];
        _categories = const <CategorySuggestion>[];
        _loading = false;
        _failed = false;
      });
      return;
    }
    setState(() => _loading = true);
    final String? country = userCountryTag();
    final List<String> langs = userSearchLangs();
    try {
      final List<Object> results = await Future.wait(<Future<Object>>[
        _service.search(
          ProductSearchService.buildTypeaheadQuery(text, langs: langs)!,
          pageSize: 30,
          langs: langs,
          sortBy: '-popularity_key',
        ),
        _service
            .categories(text, lang: langs.first)
            .catchError((_) => const <CategorySuggestion>[]),
      ]);
      if (!mounted || id != _requestId) {
        return;
      }
      final SearchHitsPage page = results[0] as SearchHitsPage;
      final List<SearchHit> ranked = ProductSearchService.rerank(
        page.hits,
        countryTag: country,
      );
      setState(() {
        _resultText = text;
        _products = ProductSearchService.dedupe(ranked).take(6).toList();
        _brands = ProductSearchService.brandsFrom(page.hits, text);
        _categories = results[1] as List<CategorySuggestion>;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || id != _requestId) {
        return;
      }
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AvoidedOwners.instance,
    builder: (BuildContext context, _) => _build(context),
  );

  /// Products to suggest: those from avoided companies left out when the
  /// user chose so in the search results.
  List<SearchHit> get _shownProducts {
    if (!AvoidedOwners.instance.hideInSearch) {
      return _products;
    }
    return <SearchHit>[
      for (final SearchHit hit in _products)
        if (!AvoidedOwners.instance.isAvoided(SearchHitTile.ownerInfo(hit, _ownerDb, _ethicsDb)?.names ?? const <String>[]))
          hit,
    ];
  }

  /// The owner when the typed text is a brand the offline data knows
  /// ("kitkat" -> Nestlé); null for anything else, and when the owner only
  /// repeats the text (the company rows below cover that).
  LocalOwnerResult? _brandOwner(final String text) {
    final OwnershipLocalDb? db = _ownerDb;
    final String key = OwnershipNorm.normCore(text);
    if (db == null || key.length < 2 || !db.knowsBrand(key)) {
      return null;
    }
    List<String> countries = const <String>[];
    try {
      countries = <String>[ProductQuery.getCountry().offTag];
    } catch (_) {
      // Country not chosen yet: the brand table still answers.
    }
    final LocalOwnerResult? hit = db.lookup(barcode: '', brands: text, countryTags: countries);
    if (hit == null || OwnershipNorm.normCore(hit.owner) == key) {
      return null;
    }
    return hit;
  }

  Widget _build(final BuildContext context) {
    final List<SearchHit> products = _shownProducts;
    final ThemeData theme = Theme.of(context);
    final String text = widget.text.trim();
    final String lower = text.toLowerCase();
    final List<String> history = widget.history
        .where(
          (String q) =>
              q.toLowerCase().startsWith(lower) && q.toLowerCase() != lower,
        )
        .take(3)
        .toList();
    final bool stale = _resultText != text;

    final LocalOwnerResult? brandOwner = _brandOwner(text);
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsetsDirectional.only(bottom: VERY_LARGE_SPACE),
      children: <Widget>[
        if (brandOwner != null)
          BrandOwnerAnswer(brand: text, result: brandOwner, ethicsDb: _ethicsDb),
        ListTile(
          leading: const Icon(Icons.search),
          title: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                const TextSpan(text: 'Search for '),
                TextSpan(
                  text: '"$text"',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          trailing: _loading || stale
              ? const SizedBox.square(
                  dimension: 18.0,
                  child: CircularProgressIndicator(strokeWidth: 2.0),
                )
              : const Icon(Icons.north_west, size: 18.0),
          onTap: () => widget.onSearch(text),
        ),
        for (final OwnerRef owner in _owners(text))
          ListTile(
            leading: OwnerAvatar(name: owner.name, size: 36.0),
            title: Text(owner.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              owner.company == null
                  ? 'Company · see its brands'
                  : 'Company · Ethics ${EthicsScore.compute(owner.company!).score}/100',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => openOwnerPage(context, name: owner.name, dbName: owner.dbName, company: owner.company),
          ),
        for (final String q in history)
          ListTile(
            dense: true,
            leading: const Icon(Icons.history),
            title: Text(q),
            onTap: () => widget.onSearch(q),
          ),
        if (_brands.isNotEmpty || _categories.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              LARGE_SPACE,
              SMALL_SPACE,
              LARGE_SPACE,
              SMALL_SPACE,
            ),
            child: Wrap(
              spacing: SMALL_SPACE,
              runSpacing: SMALL_SPACE,
              children: <Widget>[
                for (final String brand in _brands)
                  ActionChip(
                    avatar: const Icon(Icons.sell_outlined, size: 18.0),
                    label: Text(brand),
                    onPressed: () => widget.onSearch(brand),
                  ),
                for (final CategorySuggestion c in _categories)
                  ActionChip(
                    avatar: const Icon(Icons.category_outlined, size: 18.0),
                    label: Text(c.name),
                    onPressed: () => widget.onCategory(c),
                  ),
              ],
            ),
          ),
        if (products.isNotEmpty) ...<Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              LARGE_SPACE,
              MEDIUM_SPACE,
              LARGE_SPACE,
              VERY_SMALL_SPACE,
            ),
            child: Text(
              'Products',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final SearchHit hit in products)
            SearchHitTile(
              hit: hit,
              dense: true,
              ownerDb: _ownerDb,
              ethicsDb: _ethicsDb,
              onTap: () => AppNavigator.of(
                context,
              ).push(AppRoutes.PRODUCT_LOADER(hit.barcode)),
            ),
          ListTile(
            title: Text(
              'Show all results',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            trailing: Icon(
              Icons.arrow_forward,
              color: theme.colorScheme.primary,
            ),
            onTap: () => widget.onSearch(text),
          ),
        ] else if (!_loading && !stale && text.length >= 2)
          Padding(
            padding: const EdgeInsetsDirectional.all(LARGE_SPACE),
            child: Text(
              _failed
                  ? 'Could not load suggestions right now. Tap search to try again.'
                  : 'No suggestions yet. Tap search for a wider search.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// The instant answer at the top of the search when the text is a brand:
/// "KitKat is owned by Nestlé", with the logo and the moral score, as one
/// Cal AI card. A tap opens the company.
class BrandOwnerAnswer extends StatelessWidget {
  const BrandOwnerAnswer({required this.brand, required this.result, this.ethicsDb, super.key});

  final String brand;
  final LocalOwnerResult result;
  final EthicsDb? ethicsDb;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final EthicsCompany? company = ethicsDb?.forOwner(result.owner, chain: result.ethicsChain);
    final String owner = EthicsDb.displayName(result.owner, company);
    final int? score = company == null ? null : EthicsScore.compute(company).score;
    final String shown = brand.isEmpty ? brand : brand[0].toUpperCase() + brand.substring(1);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16.0, 8.0, 16.0, 6.0),
      child: Semantics(
        button: true,
        label: '$shown is owned by $owner${score == null ? '' : ', moral score $score'}',
        excludeSemantics: true,
        child: CalCard(
          radius: 20.0,
          padding: const EdgeInsetsDirectional.fromSTEB(12.0, 12.0, 12.0, 12.0),
          onTap: () {
            Haptics.select();
            openOwnerPage(
              context,
              name: owner,
              dbName: result.owner,
              company: company,
              controlledBy: result.controlledBy,
            );
          },
          child: Row(
            children: <Widget>[
              CompanyLogo(names: <String?>[owner, result.owner, ...result.ethicsChain], size: 52.0, radius: 14.0),
              const SizedBox(width: 12.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '$shown is owned by',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14.0,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      owner,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: 22.0,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (score != null) ...<Widget>[
                const SizedBox(width: 8.0),
                ScoreRing(score: score, size: 40.0),
              ],
              const SizedBox(width: 6.0),
              Icon(CupertinoIcons.chevron_right, size: 16.0, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
