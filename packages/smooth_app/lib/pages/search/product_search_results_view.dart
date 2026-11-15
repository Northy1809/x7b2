import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/pages/navigator/app_navigator.dart';
import 'package:smooth_app/pages/search/search_hit_tile.dart';
import 'package:smooth_app/services/avoided_owners.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/product_search_service.dart';

/// One query feeding the result list. Sources run in order: when the first
/// runs out of pages, the next one continues the list under its [title].
class _Source {
  _Source(this.query, {this.sortBy, this.title});

  final String query;
  final String? sortBy;
  final String? title;
  int nextPage = 1;
  bool exhausted = false;
  int count = 0;
}

/// Full product search results from search-a-licious, with infinite scroll
/// and more sources after the exact matches (prefix matches, then the
/// matching food category), so a search rarely ends after a handful of hits.
class ProductSearchResultsView extends StatefulWidget {
  const ProductSearchResultsView({
    required this.query,
    required this.legacyBuilder,
    super.key,
    this.category,
    this.service,
    this.localDb,
  });

  /// What the user searched for (shown in the header).
  final String query;

  /// When set, list this category instead of a text search.
  final CategorySuggestion? category;

  /// The classic OFF search, used if search-a-licious is unreachable.
  final Future<Widget> Function() legacyBuilder;

  final ProductSearchService? service;

  /// For tests; normally the bundled ownership database.
  final Future<OwnershipLocalDb> Function()? localDb;

  @override
  State<ProductSearchResultsView> createState() =>
      _ProductSearchResultsViewState();
}

class _ProductSearchResultsViewState extends State<ProductSearchResultsView> {
  static const int _pageSize = 30;

  late final ProductSearchService _service =
      widget.service ?? ProductSearchService();
  final List<_Source> _sources = <_Source>[];
  final List<Object> _items = <Object>[];
  final Set<String> _seen = <String>{};
  int _sourceIndex = 0;
  bool _loading = false;
  bool _initialised = false;
  Future<Widget>? _legacy;
  OwnershipLocalDb? _ownerDb;
  EthicsDb? _ethicsDb;

  @override
  void initState() {
    super.initState();
    unawaited(
      (widget.localDb ?? OwnershipLocalDb.load)().then((OwnershipLocalDb db) {
        if (mounted) {
          setState(() => _ownerDb = db);
        }
      }, onError: (_) {}),
    );
    unawaited(
      EthicsDb.load().then((EthicsDb db) {
        if (mounted) {
          setState(() => _ethicsDb = db);
        }
      }, onError: (_) {}),
    );
    unawaited(_init());
  }

  Future<void> _init() async {
    final CategorySuggestion? category = widget.category;
    if (category != null) {
      _sources.add(
        _Source(
          ProductSearchService.categoryQuery(category.tag),
          sortBy: '-popularity_key',
        ),
      );
    } else {
      final String? full = ProductSearchService.buildFullQuery(widget.query);
      if (full == null) {
        setState(() => _initialised = true);
        return;
      }
      _sources.add(_Source(full));
      final String? prefix = ProductSearchService.buildTypeaheadQuery(
        widget.query,
        langs: userSearchLangs(),
      );
      if (prefix != null && prefix != full) {
        _sources.add(
          _Source(prefix, sortBy: '-popularity_key', title: 'More suggestions'),
        );
      }
      try {
        final List<CategorySuggestion> categories = await _service.categories(
          widget.query,
          lang: userSearchLangs().first,
        );
        final String lower = widget.query.trim().toLowerCase();
        for (final CategorySuggestion c in categories) {
          if (c.name.toLowerCase() == lower) {
            _sources.add(
              _Source(
                ProductSearchService.categoryQuery(c.tag),
                sortBy: '-popularity_key',
                title: 'More in ${c.name}',
              ),
            );
            break;
          }
        }
      } catch (_) {
        // Categories are a bonus; the text search still works without them.
      }
    }
    if (!mounted) {
      return;
    }
    setState(() => _initialised = true);
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _sourceIndex >= _sources.length) {
      return;
    }
    setState(() => _loading = true);
    final _Source source = _sources[_sourceIndex];
    try {
      final SearchHitsPage page = await _service.search(
        source.query,
        page: source.nextPage,
        pageSize: _pageSize,
        langs: userSearchLangs(),
        sortBy: source.sortBy,
      );
      if (!mounted) {
        return;
      }
      final List<SearchHit> ranked = ProductSearchService.rerank(
        page.hits,
        countryTag: userCountryTag(),
      );
      setState(() {
        if (source.nextPage == 1) {
          source.count = page.count;
        }
        final List<SearchHit> fresh = <SearchHit>[
          for (final SearchHit hit in ranked)
            if (hit.name != null && _seen.add(hit.barcode)) hit,
        ];
        // A section title only when the section has something new to show.
        if (fresh.isNotEmpty &&
            source.title != null &&
            !_items.contains(source.title)) {
          _items.add(source.title!);
        }
        _items.addAll(fresh);
        source.nextPage++;
        if (!page.hasMore || page.hits.isEmpty) {
          source.exhausted = true;
          _sourceIndex++;
        }
        _loading = false;
      });
      // A source that added nothing new should not stall the list.
      if (_hitCount < 12 && _sourceIndex < _sources.length) {
        await _loadMore();
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        if (_hitCount == 0 && _sourceIndex == 0) {
          _legacy = widget.legacyBuilder();
        } else {
          // Skip a failing extra source instead of retrying it forever.
          _sourceIndex++;
        }
      });
    }
  }

  int get _hitCount => _items.whereType<SearchHit>().length;

  bool get _hasMore => _sourceIndex < _sources.length;

  @override
  Widget build(BuildContext context) {
    if (_legacy != null) {
      return FutureBuilder<Widget>(
        future: _legacy,
        builder: (BuildContext context, AsyncSnapshot<Widget> snapshot) =>
            snapshot.data ?? const Center(child: CircularProgressIndicator()),
      );
    }
    final ThemeData theme = Theme.of(context);
    if (!_initialised || (_items.isEmpty && _loading)) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return _EmptyResults(query: widget.query);
    }
    final int total = _sources.isEmpty ? 0 : _sources.first.count;
    return ListenableBuilder(
      listenable: AvoidedOwners.instance,
      builder: (BuildContext context, _) => _list(theme, total),
    );
  }

  bool _fromAvoided(final SearchHit hit) {
    final OwnerInfo? info = SearchHitTile.ownerInfo(hit, _ownerDb, _ethicsDb);
    return info != null && AvoidedOwners.instance.isAvoided(info.names);
  }

  Widget _list(final ThemeData theme, final int total) {
    final AvoidedOwners avoided = AvoidedOwners.instance;
    final bool canHide = !avoided.isEmpty;
    final List<Object> kept = canHide && avoided.hideInSearch
        ? <Object>[for (final Object o in _items) if (o is! SearchHit || !_fromAvoided(o)) o]
        : _items;
    final int hidden = _items.length - kept.length;
    // A section title whose products were all hidden goes too.
    final List<Object> items = <Object>[
      for (int i = 0; i < kept.length; i++)
        if (kept[i] is! String || (i + 1 < kept.length && kept[i + 1] is SearchHit)) kept[i],
    ];
    final bool allHidden = hidden > 0 && !items.any((Object o) => o is SearchHit);
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification n) {
        if (n.metrics.extentAfter < 600 && _hasMore && !_loading) {
          unawaited(_loadMore());
        }
        return false;
      },
      child: ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsetsDirectional.only(bottom: VERY_LARGE_SPACE),
        itemCount: items.length + 2,
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            final Widget count = Text(
                widget.category != null
                    ? '${widget.category!.name}: ${_formatCount(total)} products'
                    : total > 0
                    ? '${_formatCount(total)} products match "${widget.query}"'
                    : 'Suggestions for "${widget.query}"',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              );
            return Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(LARGE_SPACE, MEDIUM_SPACE, LARGE_SPACE, VERY_SMALL_SPACE),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  count,
                  if (canHide)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(top: SMALL_SPACE),
                      child: FilterChip(
                        avatar: const Icon(Icons.block_rounded, size: 18.0),
                        label: Text(
                          avoided.hideInSearch && hidden > 0
                              ? 'Hiding $hidden from companies you avoid'
                              : 'Hide companies you avoid',
                        ),
                        selected: avoided.hideInSearch,
                        showCheckmark: false,
                        onSelected: (bool on) => unawaited(avoided.setHideInSearch(on)),
                      ),
                    ),
                ],
              ),
            );
          }
          if (index == items.length + 1) {
            if (_hasMore) {
              return const Padding(
                padding: EdgeInsetsDirectional.all(LARGE_SPACE),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return Padding(
              padding: const EdgeInsetsDirectional.all(LARGE_SPACE),
              child: Text(
                allHidden
                    ? 'Every product here is from a company you avoid. '
                          'Turn off the filter above to see them.'
                    : 'Not what you were looking for? Try a brand or another word, '
                          'or snap the product.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }
          final Object item = items[index - 1];
          if (item is String) {
            return Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                LARGE_SPACE,
                VERY_LARGE_SPACE,
                LARGE_SPACE,
                VERY_SMALL_SPACE,
              ),
              child: Text(
                item,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }
          final SearchHit hit = item as SearchHit;
          return SearchHitTile(
            hit: hit,
            ownerDb: _ownerDb,
              ethicsDb: _ethicsDb,
            onTap: () => AppNavigator.of(
              context,
            ).push(AppRoutes.PRODUCT_LOADER(hit.barcode)),
          );
        },
      ),
    );
  }

  static String _formatCount(final int n) {
    final String s = n.toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) {
        out.write(',');
      }
      out.write(s[i]);
    }
    return out.toString();
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.all(VERY_LARGE_SPACE),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.search_off,
            size: 48.0,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: MEDIUM_SPACE),
          Text(
            'No products found for "$query"',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: SMALL_SPACE),
          Text(
            'Check the spelling, try fewer words, or snap the product.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
