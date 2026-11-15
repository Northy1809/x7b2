import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/helpers/gs1_code.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/themes/brand_colors.dart';

/// What the barcode alone says when no database knows the product: the
/// company that registered the barcode prefix (from the offline ownership
/// database), the country of registration, or that it is a shop's own code.
class BarcodeOwnerHint extends StatefulWidget {
  const BarcodeOwnerHint({required this.barcode, this.onDark = false, super.key});

  final String barcode;

  /// White text, for the dark hero blocks.
  final bool onDark;

  @override
  State<BarcodeOwnerHint> createState() => _BarcodeOwnerHintState();
}

class _BarcodeOwnerHintState extends State<BarcodeOwnerHint> {
  String? _owner;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    String? owner;
    try {
      final OwnershipLocalDb db = await OwnershipLocalDb.load();
      final LocalOwnerResult? hit = db.lookup(barcode: widget.barcode);
      if (hit != null) {
        final EthicsDb ethics = await EthicsDb.load();
        owner = EthicsDb.displayName(hit.owner, ethics.forOwner(hit.owner, chain: hit.ethicsChain));
      }
    } catch (_) {
      // No offline data: fall back to the country line.
    }
    if (mounted) {
      setState(() {
        _owner = owner;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color text = widget.onDark ? Colors.white : theme.colorScheme.onSurface;
    final Color muted = widget.onDark
        ? Colors.white.withValues(alpha: 0.75)
        : theme.colorScheme.onSurfaceVariant;
    if (!_loaded) {
      return const SizedBox(height: 24.0);
    }
    final String code = widget.barcode;
    final Widget dot;
    final InlineSpan line;
    if (_owner != null) {
      dot = _dot(BrandColors.gold);
      line = TextSpan(
        children: <InlineSpan>[
          const TextSpan(text: 'Barcode registered to '),
          TextSpan(
            text: _owner,
            style: TextStyle(color: text, fontWeight: FontWeight.w800),
          ),
          const TextSpan(text: ', the likely owner.'),
        ],
      );
    } else if (Gs1Code.isInStoreCode(code)) {
      dot = _dot(theme.colorScheme.outline);
      line = const TextSpan(
        text: "This is a shop's own barcode (for example weighed fresh "
            'food), so it does not name the product. Look for the brand on '
            'the label instead.',
      );
    } else {
      final String? country = Gs1Code.registrationCountry(code);
      if (country == null) {
        return const SizedBox.shrink();
      }
      dot = _dot(theme.colorScheme.outline);
      line = TextSpan(text: 'Barcode registered in $country.');
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(padding: const EdgeInsetsDirectional.only(top: 4.0), child: dot),
        const SizedBox(width: SMALL_SPACE),
        Expanded(
          child: Text.rich(
            line,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted, height: 1.35),
          ),
        ),
      ],
    );
  }

  Widget _dot(final Color color) => Container(
    width: 12.0,
    height: 12.0,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
  );
}
