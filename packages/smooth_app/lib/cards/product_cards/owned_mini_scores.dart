import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/pages/product/product_page/overview/score_ring.dart';
import 'package:smooth_app/pages/product/product_page/tabs/ownership/ownership_provider.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/health_score.dart';
import 'package:smooth_app/services/owner_overrides.dart';
import 'package:smooth_app/services/ownership_local_db.dart';

/// The app's two scores as small rings, for product rows (history, lists).
class OwnedMiniScores extends StatefulWidget {
  const OwnedMiniScores({required this.product, super.key});

  final Product product;

  @override
  State<OwnedMiniScores> createState() => _OwnedMiniScoresState();
}

class _OwnedMiniScoresState extends State<OwnedMiniScores> {
  int? _ethics;

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
    int? score;
    try {
      final OwnershipLocalDb db = await OwnershipLocalDb.load();
      final Product p = widget.product;
      final LocalOwnerResult? hit = db.lookup(
        barcode: p.barcode ?? '',
        brands: p.brands,
        countryTags: p.countriesTags ?? const <String>[],
        embCodeTags: OwnershipProvider.embCodeTags(p.embCodes),
      );
      if (hit != null) {
        final EthicsCompany? company = (await EthicsDb.load()).forOwner(hit.owner, chain: hit.ethicsChain);
        score = company == null ? null : EthicsScore.compute(company).score;
      }
    } catch (_) {
      // No offline data: the ethics ring stays empty.
    }
    if (mounted && score != _ethics) {
      setState(() => _ethics = score);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool food = (widget.product.productType ?? ProductType.food) == ProductType.food;
    return Row(
      children: <Widget>[
        if (food) ...<Widget>[
          _Mini(title: 'Health', score: HealthScore.fromProduct(widget.product).score),
          const SizedBox(width: LARGE_SPACE),
        ],
        _Mini(title: 'Moral', score: _ethics),
      ],
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.title, required this.score});

  final String title;
  final int? score;

  // Read as one item: "Score 35 out of 100, Health".
  @override
  Widget build(BuildContext context) => MergeSemantics(child: _row(context));

  Widget _row(final BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      ScoreRing(score: score, size: 32.0),
      const SizedBox(width: SMALL_SPACE),
      Text(
        title,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    ],
  );
}
