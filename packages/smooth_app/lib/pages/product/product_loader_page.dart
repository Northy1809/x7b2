import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/data_models/fetched_product.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/pages/navigator/app_navigator.dart';
import 'package:smooth_app/pages/product/common/product_refresher.dart';
import 'package:smooth_app/pages/product/product_page/tabs/ownership/barcode_owner_hint.dart';
import 'package:smooth_app/pages/product/product_page/tabs/ownership/unknown_barcode_ownership_card.dart';
import 'package:smooth_app/widgets/smooth_scaffold.dart';

/// A page to show when a [Product] is not in the database
/// This page shouldn't be opened directly, it's only for deep links
class ProductLoaderPage extends StatefulWidget {
  const ProductLoaderPage({
    required this.barcode,
    required this.mode,
    super.key,
  }) : assert(barcode != '');

  final String barcode;
  final ProductLoaderMode mode;

  @override
  State<ProductLoaderPage> createState() => _ProductLoaderPageState();
}

class _ProductLoaderPageState extends State<ProductLoaderPage> {
  _ProductLoaderState _state = _ProductLoaderState.loading;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProduct();
    });
  }

  Future<void> _loadProduct() async {
    final AppNavigator navigator = AppNavigator.of(context);
    setState(() {
      _state = _ProductLoaderState.loading;
    });

    final FetchedProduct fetchedProduct = await ProductRefresher()
        .silentFetchAndRefresh(
          barcode: widget.barcode,
          localDatabase: context.read<LocalDatabase>(),
        );

    if (mounted) {
      if (fetchedProduct.product != null) {
        if (widget.mode == ProductLoaderMode.viewProduct) {
          navigator.pushReplacement(
            AppRoutes.PRODUCT(
              widget.barcode,
              heroTag: 'product_${widget.barcode}',
            ),
            extra: fetchedProduct.product,
          );
        } else if (widget.mode == ProductLoaderMode.editProduct) {
          navigator.pushReplacement(
            AppRoutes.PRODUCT_EDITOR(widget.barcode),
            extra: fetchedProduct.product,
          );
        }
        return;
      }
      if (fetchedProduct.status == FetchedProductStatus.internetNotFound) {
        setState(() {
          _state = _ProductLoaderState.productNotFound;
        });
        return;
      }
      setState(() {
        // TODO(monsieurtanuki): put more details from FetchedProduct?
        _state = _ProductLoaderState.serverError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget child;

    switch (_state) {
      case _ProductLoaderState.loading:
        child = const _ProductLoaderLoadingState();
        break;
      case _ProductLoaderState.productNotFound:
        child = _ProductLoaderNotFoundState(barcode: widget.barcode);
        break;
      case _ProductLoaderState.serverError:
        child = _ProductLoaderNetworkErrorState(barcode: widget.barcode, onRetry: () => _loadProduct());
        break;
    }

    return SmoothScaffold(
      appBar: _state == _ProductLoaderState.productNotFound
          ? AppBar(title: const Text('Find the owner'))
          : null,
      body: Center(child: SingleChildScrollView(child: child)),
    );
  }
}

class _ProductLoaderLoadingState extends StatelessWidget {
  const _ProductLoaderLoadingState();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      const CircularProgressIndicator.adaptive(),
      const SizedBox(height: MEDIUM_SPACE),
      Text(
        'Looking up the product…',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _ProductLoaderNotFoundState extends StatelessWidget {
  const _ProductLoaderNotFoundState({required this.barcode});

  final String barcode;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.all(LARGE_SPACE),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: ROUNDED_BORDER_RADIUS,
              border: Border.all(color: theme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.all(LARGE_SPACE),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.manage_search_rounded, color: theme.colorScheme.onSurface, size: 36.0),
                  const SizedBox(height: MEDIUM_SPACE),
                  Text(
                    "We don't know this product yet",
                    style: theme.textTheme.displaySmall,
                  ),
                  const SizedBox(height: SMALL_SPACE),
                  Text(
                    'Barcode $barcode is not in Open Food Facts or the other '
                    'open databases we check.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: MEDIUM_SPACE),
                  BarcodeOwnerHint(barcode: barcode),
                ],
              ),
            ),
          ),
          UnknownBarcodeOwnershipCard(barcode: barcode),
          const SizedBox(height: MEDIUM_SPACE),
          Center(
            child: TextButton.icon(
              onPressed: () => AppNavigator.of(
                context,
              ).pushReplacement(AppRoutes.PRODUCT_CREATOR(barcode)),
              icon: const Icon(Icons.add),
              label: const Text('Add it to Open Food Facts'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductLoaderNetworkErrorState extends StatelessWidget {
  const _ProductLoaderNetworkErrorState({required this.barcode, required this.onRetry});

  final String barcode;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.all(VERY_LARGE_SPACE),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 72.0,
            height: 72.0,
            decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, shape: BoxShape.circle),
            child: Icon(Icons.cloud_off_rounded, size: 36.0, color: theme.colorScheme.onPrimaryContainer),
          ),
          const SizedBox(height: LARGE_SPACE),
          Text(
            'Could not load the product',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: SMALL_SPACE),
          Text(
            'Check your connection and try again. What Owned knows without the internet:',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: MEDIUM_SPACE),
          // The barcode alone can name the company that registered it, offline.
          BarcodeOwnerHint(barcode: barcode),
          const SizedBox(height: LARGE_SPACE),
          FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
        ],
      ),
    );
  }
}

enum _ProductLoaderState { loading, productNotFound, serverError }

enum ProductLoaderMode { viewProduct, editProduct }
