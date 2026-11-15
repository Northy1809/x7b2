import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:smooth_app/cards/product_cards/owned_mini_scores.dart';
import 'package:smooth_app/cards/product_cards/smooth_product_image.dart';
import 'package:smooth_app/helpers/product_cards_helper.dart';
import 'package:smooth_app/l10n/app_localizations.dart';
import 'package:smooth_app/pages/navigator/app_navigator.dart';
import 'package:smooth_app/pages/product/product_page/overview/owner_line.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';

class SmoothProductCardItemFound extends StatelessWidget {
  const SmoothProductCardItemFound({
    required this.product,
    required this.heroTag,
    this.backgroundColor,
    this.onLongPress,
    this.onTap,
  });

  final Product product;
  final String heroTag;
  static const double elevation = 4.0;
  final Color? backgroundColor;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations appLocalizations = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Widget placeholder = ColoredBox(
      color: dark ? BrandColors.hairlineDark : const Color(0xFFEFEEF4),
      child: Icon(CupertinoIcons.cart, size: 30.0, color: dark ? BrandColors.mutedDark : BrandColors.faint),
    );

    // Cal AI's "Recently uploaded" row, as on the home page: photo on the
    // left, the product, the owner as the big line, the two scores.
    final Widget row = Container(
      height: 118.0,
      decoration: BoxDecoration(
        color: backgroundColor ?? (dark ? BrandColors.fillDark : BrandColors.row),
        borderRadius: BorderRadius.circular(18.0),
        border: Border.all(color: dark ? BrandColors.hairlineDark : const Color(0xFFF1F0F6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 116.0,
            child: ProductPicture.fromProduct(
              product: product,
              imageField: ImageField.FRONT,
              fallbackUrl: product.imageFrontUrl,
              allowAlternativeLanguage: true,
              size: const Size(116.0, 118.0),
              borderRadius: BorderRadius.zero,
              noImageBuilder: (_) => placeholder,
              blurFilter: false,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16.0, 10.0, 12.0, 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    getProductName(product, appLocalizations),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15.0, letterSpacing: -0.2),
                  ),
                  const SizedBox(height: 5.0),
                  OwnerLine(product: product, big: true),
                  const SizedBox(height: 6.0),
                  OwnedMiniScores(product: product),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return MultiProvider(
      providers: <SingleChildWidget>[
        Provider<Product>(create: (_) => product),
        Provider<String>.value(value: heroTag),
      ],
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 20.0, vertical: 6.0),
        child: PressScale(
          scale: 0.97,
          onTap:
              onTap ??
              () => AppNavigator.of(context).push(
                AppRoutes.PRODUCT(product.barcode!, heroTag: heroTag),
                extra: product,
              ),
          onLongPress: onLongPress,
          child: row,
        ),
      ),
    );
  }
}
