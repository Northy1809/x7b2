import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/l10n/app_localizations.dart';
import 'package:smooth_app/pages/product/common/search_helper.dart';
import 'package:smooth_app/pages/product/common/search_preloaded_item.dart';
import 'package:smooth_app/pages/search/search_product_helper.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/cal_ui.dart';

/// What the search shows before anything is typed (16/11, Cal AI): the
/// recent searches as grey rows (tap to search again, × to forget, hold to
/// edit), "Clear" for all of them, and popular brands as pills to try.
class SearchHistoryView extends StatefulWidget {
  const SearchHistoryView({
    required this.onTap,
    required this.focusNode,
    required this.searchHelper,
    required this.preloadedList,
  });

  final void Function(String) onTap;
  final FocusNode focusNode;
  final SearchHelper searchHelper;
  final List<SearchPreloadedItem> preloadedList;

  /// Well-known brands with a surprising owner, to show what the search does.
  static const List<String> popularBrands = <String>[
    'KitKat',
    'Coca-Cola',
    'Nutella',
    'Oreo',
    'Pringles',
    "Ben & Jerry's",
    'Lipton',
    'Magnum',
  ];

  @override
  State<SearchHistoryView> createState() => _SearchHistoryViewState();
}

class _SearchHistoryViewState extends State<SearchHistoryView> {
  List<String> _queries = <String>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fetchQueries();
  }

  void _fetchQueries() {
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool products = widget.searchHelper is SearchProductHelper;
    final List<Widget> children = <Widget>[];
    int i = 0;

    if (widget.preloadedList.isNotEmpty) {
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
    }

    if (_queries.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 8.0, bottom: 10.0),
          child: CalSectionTitle('Recent', action: 'Clear', onAction: () => unawaited(_clear())),
        ),
      );
      for (final String q in _queries.take(12)) {
        children.add(
          Padding(
            key: ValueKey<String>(q),
            padding: const EdgeInsetsDirectional.only(bottom: 8.0),
            child: FadeUpIn(
              index: i++,
              child: _RecentRow(
                query: q,
                onTap: () => widget.onTap(q),
                onEdit: () => _edit(q),
                onRemove: () => unawaited(_remove(q)),
              ),
            ),
          ),
        );
      }
    }

    if (products) {
      children.add(
        Padding(
          padding: EdgeInsetsDirectional.only(top: _queries.isEmpty ? 8.0 : 22.0, bottom: 12.0),
          child: const CalSectionTitle('Popular brands'),
        ),
      );
      children.add(
        FadeUpIn(
          index: i++,
          child: Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: <Widget>[
              for (final String b in SearchHistoryView.popularBrands)
                CalPill(label: b, onTap: () => widget.onTap(b)),
            ],
          ),
        ),
      );
      if (_queries.isEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 18.0),
            child: Text(
              'Type a brand to see who owns it, or a product name or barcode.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 15.0,
                height: 1.35,
                color: theme.colorScheme.onSurfaceVariant,
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
      padding: EdgeInsetsDirectional.fromSTEB(
        kCalSide,
        4.0,
        kCalSide,
        MediaQuery.paddingOf(context).bottom + 120.0,
      ),
      children: children,
    );
  }
}

/// One earlier search: a clock, the words, and × to forget it.
class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.query, required this.onTap, required this.onEdit, required this.onRemove});

  final String query;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      label: 'Search again for $query',
      onLongPressHint: 'Edit',
      child: PressScale(
        scale: 0.98,
        onTap: onTap,
        onLongPress: onEdit,
        child: Container(
          height: 54.0,
          padding: const EdgeInsetsDirectional.only(start: 16.0, end: 4.0),
          decoration: calRowDecoration(context, radius: 16.0),
          child: Row(
            children: <Widget>[
              Icon(CupertinoIcons.clock, size: 19.0, color: muted),
              const SizedBox(width: 12.0),
              Expanded(
                child: Text(
                  query,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16.0, letterSpacing: -0.3),
                ),
              ),
              Semantics(
                button: true,
                label: 'Remove $query from recent searches',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRemove,
                  child: SizedBox(
                    width: 44.0,
                    height: 44.0,
                    child: Icon(CupertinoIcons.xmark, size: 15.0, color: muted),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
