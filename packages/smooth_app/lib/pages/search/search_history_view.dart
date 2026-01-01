import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/l10n/app_localizations.dart';
import 'package:smooth_app/pages/product/common/search_helper.dart';
import 'package:smooth_app/pages/product/common/search_preloaded_item.dart';
import 'package:smooth_app/pages/search/live_search_suggestions.dart';
import 'package:smooth_app/pages/search/search_product_helper.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/cal_ui.dart';

/// What the search shows before anything is typed, as Cal AI's food
/// search (16/11): "Recently searched" and "Suggestions" as grey two-line
/// rows (bold name; the owner and its moral score under it, from the
/// offline data), a button on the right. Tap = search again; × forgets a
/// recent search; hold = edit it.
class SearchHistoryView extends StatefulWidget {
  const SearchHistoryView({
    required this.onTap,
    required this.focusNode,
    required this.searchHelper,
    required this.preloadedList,
    this.localDb,
    this.ethicsDb,
  });

  final void Function(String) onTap;
  final FocusNode focusNode;
  final SearchHelper searchHelper;
  final List<SearchPreloadedItem> preloadedList;

  /// For tests: the bundled databases.
  final Future<OwnershipLocalDb> Function()? localDb;
  final Future<EthicsDb> Function()? ethicsDb;

  /// Well-known brands with a surprising owner, to show what the search does.
  static const List<String> popularBrands = <String>[
    'KitKat',
    'Nesquik',
    "Ben & Jerry's",
    'Pringles',
    'Lipton',
    'Oreo',
  ];

  @override
  State<SearchHistoryView> createState() => _SearchHistoryViewState();
}

class _SearchHistoryViewState extends State<SearchHistoryView> {
  List<String> _queries = <String>[];
  OwnershipLocalDb? _db;
  EthicsDb? _ethics;

  @override
  void initState() {
    super.initState();
    unawaited(
      (widget.localDb ?? OwnershipLocalDb.load)().then((OwnershipLocalDb db) {
        if (mounted) {
          setState(() => _db = db);
        }
      }, onError: (_) {}),
    );
    unawaited(
      (widget.ethicsDb ?? EthicsDb.load)().then((EthicsDb db) {
        if (mounted) {
          setState(() => _ethics = db);
        }
      }, onError: (_) {}),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final LocalDatabase localDatabase = context.watch<LocalDatabase>();
    setState(() => _queries = widget.searchHelper.getAllQueries(localDatabase));
  }

  Future<void> _remove(final String query) async {
    Haptics.remove();
    setState(() => _queries.remove(query));
    await widget.searchHelper.removeQuery(context.read<LocalDatabase>(), query);
  }

  Future<void> _clear() async {
    Haptics.remove();
    final LocalDatabase db = context.read<LocalDatabase>();
    final List<String> all = List<String>.of(_queries);
    setState(() => _queries = <String>[]);
    for (final String q in all) {
      await widget.searchHelper.removeQuery(db, q);
    }
  }

  void _edit(final String query) {
    final TextEditingController controller = Provider.of<TextEditingController>(context, listen: false);
    controller.text = query;
    controller.selection = TextSelection.fromPosition(TextPosition(offset: query.length));
    widget.focusNode.requestFocus();
  }

  /// "Nestlé · 13": who owns [text] and its moral score, when known.
  ({String owner, int? score})? _ownerOf(final String text) {
    final LocalOwnerResult? r = lookupBrandOwner(_db, text, allowSame: true);
    if (r == null) {
      return null;
    }
    final EthicsCompany? company = _ethics?.forOwner(r.owner, chain: r.ethicsChain);
    return (
      owner: EthicsDb.displayName(r.owner, company),
      score: company == null ? null : EthicsScore.compute(company).score,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool products = widget.searchHelper is SearchProductHelper;
    final List<Widget> children = <Widget>[];
    int i = 0;

    for (int k = 0; k < widget.preloadedList.length; k++) {
      final SearchPreloadedItem item = widget.preloadedList[k];
      children.add(
        item.getWidget(
          context,
          onDismissItem: () async {
            widget.preloadedList.removeAt(k);
            await item.delete(context);
            setState(() {});
          },
        ),
      );
    }

    if (_queries.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 8.0, bottom: 12.0),
          child: CalSectionTitle('Recently searched', action: 'Clear', onAction: () => unawaited(_clear())),
        ),
      );
      for (final String q in _queries.take(8)) {
        children.add(
          Padding(
            key: ValueKey<String>('recent-$q'),
            padding: const EdgeInsetsDirectional.only(bottom: 10.0),
            child: FadeUpIn(
              index: i++,
              child: _QueryRow(
                title: q,
                owner: products ? _ownerOf(q) : null,
                leading: CupertinoIcons.clock,
                onTap: () => widget.onTap(q),
                onLongPress: () => _edit(q),
                action: CupertinoIcons.xmark,
                actionLabel: 'Remove $q from recent searches',
                onAction: () => unawaited(_remove(q)),
              ),
            ),
          ),
        );
      }
    }

    if (products) {
      children.add(
        Padding(
          padding: EdgeInsetsDirectional.only(top: _queries.isEmpty ? 8.0 : 20.0, bottom: 12.0),
          child: const CalSectionTitle('Suggestions'),
        ),
      );
      for (final String b in SearchHistoryView.popularBrands) {
        if (_queries.any((String q) => q.toLowerCase() == b.toLowerCase())) {
          continue;
        }
        children.add(
          Padding(
            key: ValueKey<String>('suggest-$b'),
            padding: const EdgeInsetsDirectional.only(bottom: 10.0),
            child: FadeUpIn(
              index: i++,
              child: _QueryRow(
                title: b,
                owner: _ownerOf(b),
                onTap: () => widget.onTap(b),
                action: CupertinoIcons.arrow_right,
                actionLabel: 'Who owns $b',
                onAction: () => widget.onTap(b),
              ),
            ),
          ),
        );
      }
    } else if (_queries.isEmpty && widget.preloadedList.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 8.0),
          child: Text(
            widget.searchHelper.getHelpText(AppLocalizations.of(context)),
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15.0, color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsetsDirectional.fromSTEB(kCalSide, 4.0, kCalSide, MediaQuery.paddingOf(context).bottom + 120.0),
      children: children,
    );
  }
}

/// Cal AI's food row: a bold name, a grey line under it (here the owner
/// and its moral score), and a round button on the right.
class _QueryRow extends StatelessWidget {
  const _QueryRow({
    required this.title,
    required this.owner,
    required this.onTap,
    required this.action,
    required this.actionLabel,
    required this.onAction,
    this.leading,
    this.onLongPress,
  });

  final String title;
  final ({String owner, int? score})? owner;
  final IconData? leading;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final IconData action;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final ({String owner, int? score})? o = owner;
    return Semantics(
      button: true,
      label: o == null ? 'Search for $title' : '$title, owned by ${o.owner}',
      child: PressScale(
        scale: 0.98,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64.0),
          padding: const EdgeInsetsDirectional.fromSTEB(16.0, 11.0, 10.0, 11.0),
          decoration: calRowDecoration(context, radius: 16.0),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 15.0,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3.0),
                    Row(
                      children: <Widget>[
                        Icon(
                          o == null ? (leading ?? CupertinoIcons.search) : CupertinoIcons.building_2_fill,
                          size: 13.0,
                          color: theme.colorScheme.onSurface,
                        ),
                        const SizedBox(width: 5.0),
                        Flexible(
                          child: Text(
                            o == null ? 'Search again' : o.owner,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 13.0, color: muted),
                          ),
                        ),
                        if (o?.score != null) ...<Widget>[
                          Text(' · ', style: theme.textTheme.bodySmall?.copyWith(fontSize: 13.0, color: muted)),
                          Icon(Icons.balance_rounded, size: 12.0, color: theme.colorScheme.onSurface),
                          const SizedBox(width: 3.0),
                          Text(
                            '${o!.score}',
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 13.0, color: muted),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8.0),
              CalRoundButton(icon: action, tooltip: actionLabel, size: 32.0, onTap: onAction, onWhite: true),
            ],
          ),
        ),
      ),
    );
  }
}
