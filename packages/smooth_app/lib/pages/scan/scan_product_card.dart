import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:smooth_app/cards/product_cards/smooth_product_base_card.dart';
import 'package:smooth_app/cards/product_cards/smooth_product_image.dart';
import 'package:smooth_app/generic_lib/widgets/smooth_back_button.dart';
import 'package:smooth_app/pages/navigator/app_navigator.dart';
import 'package:smooth_app/pages/product/product_page/new_product_header.dart';
import 'package:smooth_app/pages/product/product_page/overview/scan_quick_summary.dart';

class ScanProductCardFound extends StatelessWidget {
  ScanProductCardFound({required this.product, required this.onRemoveProduct})
    : assert(product.barcode!.isNotEmpty),
      super(key: Key(product.barcode!));

  final Product product;
  final OnRemoveCallback? onRemoveProduct;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openProductPage(context),
      onVerticalDragEnd: (DragEndDetails details) {
        if (details.primaryVelocity == null) {
          return;
        }
        if (details.primaryVelocity! < 0) {
          _openProductPage(context);
        }
      },
      child: ScanProductBaseCard(
        headerLabel: 'Tap to see why',
        headerIndicatorColor: Colors.white,
        headerBackgroundColor: Theme.of(context).colorScheme.primary,
        childPadding: EdgeInsets.zero,
        onRemove: onRemoveProduct,
        child: ScanQuickSummary(product: product, heroTag: _heroTag),
      ),
    );
  }

  String get _heroTag =>
      ProductPicture.generateHeroTag(product.barcode!, ImageField.FRONT);

  void _openProductPage(BuildContext context) {
    AppNavigator.of(context).push(
      AppRoutes.PRODUCT(
        product.barcode!,
        heroTag: _heroTag,
        backButtonType: BackButtonType.minimize,
        transition: ProductPageTransition.slideUp,
      ),
      extra: product,
    );
  }
}
