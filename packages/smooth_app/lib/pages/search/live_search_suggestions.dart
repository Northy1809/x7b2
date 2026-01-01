import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/helpers/string_extension.dart';
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
import 'package:smooth_app/widgets/cal_ui.dart';
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
  LocalOwnerResult? _brandOwner(final String text) => lookupBrandOwner(_ownerDb, text);

  Widget _build(final BuildContext context) {
    final List<SearchHit> products = _shownProducts;
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
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
      padding: EdgeInsetsDirectional.only(top: 4.0, bottom: MediaQuery.paddingOf(context).bottom + 120.0),
      children: <Widget>[
        if (brandOwner != null)
          BrandOwnerAnswer(brand: text, result: brandOwner, ethicsDb: _ethicsDb),
        _SuggestionRow(
          leading: Icon(CupertinoIcons.search, size: 19.0, color: theme.colorScheme.onSurface),
          title: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                const TextSpan(text: 'Search for '),
                TextSpan(text: '"$text"', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          trailing: _loading || stale
              ? const CalLoader(size: 18.0, stroke: 2.0)
              : Icon(CupertinoIcons.arrow_up_left, size: 16.0, color: muted),
          onTap: () => widget.onSearch(text),
        ),
        for (final OwnerRef owner in _owners(text))
          _SuggestionRow(
            leading: OwnerAvatar(name: owner.name, size: 36.0),
            title: Text(owner.name.capFirst(), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: owner.company == null
                ? 'Company · see its brands'
                : 'Company · moral score ${EthicsScore.compute(owner.company!).score}',
            trailing: Icon(CupertinoIcons.chevron_right, size: 15.0, color: muted),
            onTap: () => openOwnerPage(context, name: owner.name, dbName: owner.dbName, company: owner.company),
          ),
        for (final String q in history)
          _SuggestionRow(
            leading: Icon(CupertinoIcons.clock, size: 19.0, color: muted),
            title: Text(q.capFirst()),
            onTap: () => widget.onSearch(q),
          ),
        if (_brands.isNotEmpty || _categories.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(kCalSide, 6.0, kCalSide, 8.0),
            child: Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: <Widget>[
                for (final String brand in _brands)
                  CalPill(icon: CupertinoIcons.tag, label: brand, onTap: () => widget.onSearch(brand)),
                for (final CategorySuggestion c in _categories)
                  CalPill(icon: CupertinoIcons.square_grid_2x2, label: c.name, onTap: () => widget.onCategory(c)),
              ],
            ),
          ),
        if (products.isNotEmpty) ...<Widget>[
          const Padding(
            padding: EdgeInsetsDirectional.fromSTEB(kCalSide, 18.0, kCalSide, 12.0),
            child: CalSectionTitle('Products'),
          ),
          for (final SearchHit hit in products)
            SearchHitTile(
              hit: hit,
              dense: true,
              ownerDb: _ownerDb,
              ethicsDb: _ethicsDb,
              onTap: () => openSearchHit(context, hit),
            ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(kCalSide, 6.0, kCalSide, 0.0),
            child: OutlinedButton(
              onPressed: () => widget.onSearch(text),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50.0)),
              child: const Text('Show all results'),
            ),
          ),
        ] else if (!_loading && !stale && text.length >= 2)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(kCalSide + 4.0, 12.0, kCalSide + 4.0, 0.0),
            child: Text(
              _failed
                  ? 'Could not load suggestions right now. Tap search to try again.'
                  : 'No suggestions yet. Tap search for a wider search.',
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15.0, color: muted),
            ),
          ),
      ],
    );
  }
}

/// A plain suggestion: icon, words (and a grey line), something on the
/// right. White with a grey press, as rows in Cal AI's lists.
class _SuggestionRow extends StatefulWidget {
  const _SuggestionRow({required this.leading, required this.title, required this.onTap, this.subtitle, this.trailing});

  final Widget leading;
  final Widget title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  State<_SuggestionRow> createState() => _SuggestionRowState();
}

class _SuggestionRowState extends State<_SuggestionRow> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: () {
          Haptics.tap();
          widget.onTap();
        },
        child: AnimatedContainer(
          duration: CalMotion.select,
          margin: const EdgeInsetsDirectional.symmetric(horizontal: kCalSide - 10.0),
          padding: const EdgeInsetsDirectional.fromSTEB(10.0, 11.0, 10.0, 11.0),
          decoration: BoxDecoration(
            color: _down ? calFill(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(14.0),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(width: 36.0, child: Center(child: widget.leading)),
              const SizedBox(width: 12.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    DefaultTextStyle.merge(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16.0, letterSpacing: -0.3),
                      child: widget.title,
                    ),
                    if (widget.subtitle != null)
                      Text(
                        widget.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 13.0,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.trailing != null) ...<Widget>[const SizedBox(width: 8.0), widget.trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// The owner of [text] when the offline data knows it as a brand
/// ("kitkat" -> Nestlé), in the user's country when chosen. Null for
/// anything else, and (unless [allowSame]) when the owner only repeats the
/// text.
LocalOwnerResult? lookupBrandOwner(final OwnershipLocalDb? db, final String text, {final bool allowSame = false}) {
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
  if (hit == null || (!allowSame && OwnershipNorm.normCore(hit.owner) == key)) {
    return null;
  }
  return hit;
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
      padding: const EdgeInsetsDirectional.fromSTEB(kCalSide, 4.0, kCalSide, 10.0),
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
