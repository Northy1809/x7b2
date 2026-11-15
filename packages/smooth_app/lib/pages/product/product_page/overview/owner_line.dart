import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:smooth_app/pages/product/product_page/tabs/ownership/ownership_provider.dart';
import 'package:smooth_app/services/avoided_owners.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/owner_overrides.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/themes/brand_colors.dart';

/// One line with the gold dot: "Owned by Nestlé". Offline data only, so it
/// is cheap enough for every row of a list. Shows nothing while unknown.
class OwnerLine extends StatefulWidget {
  const OwnerLine({required this.product, this.big = false, super.key});

  final Product product;

  /// Cal AI's big row line: a building and the owner at 18 pt, no
  /// "Owned by" (used in list rows).
  final bool big;

  @override
  State<OwnerLine> createState() => _OwnerLineState();
}

class _OwnerLineState extends State<OwnerLine> {
  String? _owner;

  /// Every name the owner goes by, to check against the avoid list.
  List<String> _names = const <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    OwnerOverrides.instance.addListener(_onCorrection);
  }

  @override
  void dispose() {
    OwnerOverrides.instance.removeListener(_onCorrection);
    super.dispose();
  }

  void _onCorrection() => unawaited(_load());

  Future<void> _load() async {
    try {
      final OwnershipLocalDb db = await OwnershipLocalDb.load();
      final Product p = widget.product;
      final LocalOwnerResult? hit = db.lookup(
        barcode: p.barcode ?? '',
        brands: p.brands,
        countryTags: p.countriesTags ?? const <String>[],
        embCodeTags: OwnershipProvider.embCodeTags(p.embCodes),
      );
      if (hit == null) {
        if (mounted && _owner != null) {
          setState(() => _owner = null);
        }
        return;
      }
      final EthicsDb ethics = await EthicsDb.load();
      final String name =
          EthicsDb.displayName(hit.owner, ethics.forOwner(hit.owner, chain: hit.ethicsChain));
      if (mounted) {
        setState(() {
          _owner = name;
          _names = <String>[name, hit.owner, ...hit.ethicsChain];
        });
      }
    } catch (_) {
      // No offline data: the row simply has no owner line.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_owner == null) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    return ListenableBuilder(
      listenable: AvoidedOwners.instance,
      builder: (BuildContext context, _) => AvoidedOwners.instance.isAvoided(_names)
          ? Row(
              children: <Widget>[
                Icon(Icons.block_rounded, size: 14.0, color: theme.colorScheme.error),
                const SizedBox(width: 6.0),
                Expanded(
                  child: Text(
                    'You avoid $_owner',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            )
          : _ownedBy(theme),
    );
  }

  Widget _ownedBy(final ThemeData theme) {
    if (widget.big) {
      return Row(
        children: <Widget>[
          Icon(CupertinoIcons.building_2_fill, size: 16.0, color: theme.colorScheme.onSurface),
          const SizedBox(width: 6.0),
          Expanded(
            child: Text(
              _owner ?? 'Owner unknown',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 18.0,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.4,
              ),
            ),
          ),
        ],
      );
    }
    return Row(
      children: <Widget>[
        Container(
          width: 10.0,
          height: 10.0,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: BrandColors.gold,
          ),
        ),
        const SizedBox(width: 6.0),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                const TextSpan(text: 'Owned by '),
                TextSpan(
                  text: _owner,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
