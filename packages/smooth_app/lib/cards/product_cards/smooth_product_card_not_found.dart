import 'package:flutter/material.dart';
import 'package:smooth_app/cards/product_cards/smooth_product_base_card.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/pages/navigator/app_navigator.dart';
import 'package:smooth_app/pages/product/product_page/tabs/ownership/barcode_owner_hint.dart';
import 'package:smooth_app/themes/smooth_theme_colors.dart';

class ScanProductCardNotFound extends StatelessWidget {
  ScanProductCardNotFound({
    required this.barcode,
    this.onAddProduct,
    this.onRemoveProduct,
  }) : assert(barcode.isNotEmpty);

  final String barcode;
  final Future<void> Function()? onAddProduct;
  final OnRemoveCallback? onRemoveProduct;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SmoothColorsThemeExtension colors = context
        .extension<SmoothColorsThemeExtension>();

    return ScanProductBaseCard(
      headerLabel: 'Not in our databases yet',
      headerIndicatorColor: colors.secondaryNormal,
      onRemove: onRemoveProduct,
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const ScanProductBaseCardTitle(
              title: "We don't know this product yet",
              padding: EdgeInsetsDirectional.only(top: 5.0, end: 25.0),
            ),
            const SizedBox(height: MEDIUM_SPACE),
            BarcodeOwnerHint(barcode: barcode),
            const SizedBox(height: MEDIUM_SPACE),
            Text(
              'Snap the back of the pack or type the brand, and we will find '
              'who owns it.',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
            const SizedBox(height: MEDIUM_SPACE),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => AppNavigator.of(
                      context,
                    ).push(AppRoutes.PRODUCT_LOADER(barcode)),
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('Find the owner'),
                  ),
                ),
              ],
            ),
            Center(
              child: TextButton(
                onPressed: () => _onTap(context),
                child: const Text('Add it to Open Food Facts'),
              ),
            ),
            Text(
              barcode,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onTap(BuildContext context) async {
    await AppNavigator.of(context).push(AppRoutes.PRODUCT_CREATOR(barcode));
    await onAddProduct?.call();
  }
}
