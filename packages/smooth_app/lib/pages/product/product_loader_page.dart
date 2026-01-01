import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/data_models/fetched_product.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/pages/navigator/app_navigator.dart';
import 'package:smooth_app/pages/product/common/product_refresher.dart';
import 'package:smooth_app/pages/product/product_page/tabs/ownership/barcode_owner_hint.dart';
import 'package:smooth_app/pages/product/product_page/tabs/ownership/unknown_barcode_ownership_card.dart';
import 'package:smooth_app/widgets/cal_ui.dart';

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

    return Scaffold(
      appBar: CalTopBar(title: _state == _ProductLoaderState.productNotFound ? 'Find the owner' : null),
      body: Center(child: SingleChildScrollView(child: child)),
    );
  }
}

class _ProductLoaderLoadingState extends StatelessWidget {
  const _ProductLoaderLoadingState();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsetsDirectional.only(bottom: 56.0),
    child: CalLoader(size: 34.0, label: 'Looking up the product…'),
  );
}

/// Not in any database: say so calmly, then what Owned can still tell
/// from the barcode, and the ways to find the owner.
class _ProductLoaderNotFoundState extends StatelessWidget {
  const _ProductLoaderNotFoundState({required this.barcode});

  final String barcode;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(bottom: 24.0),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CalEmpty(
          icon: CupertinoIcons.barcode,
          title: "We don't know this product yet",
          body: 'Barcode $barcode is not in Open Food Facts or the other open databases we check.',
        ),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: kCalSide),
          child: BarcodeOwnerHint(barcode: barcode),
        ),
        UnknownBarcodeOwnershipCard(barcode: barcode),
      ],
    ),
  );
}

class _ProductLoaderNetworkErrorState extends StatelessWidget {
  const _ProductLoaderNetworkErrorState({required this.barcode, required this.onRetry});

  final String barcode;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      CalEmpty(
        icon: CupertinoIcons.wifi_slash,
        title: 'Could not load the product',
        body: 'Check your connection and try again. What Owned knows without the internet:',
        action: 'Try again',
        onAction: onRetry,
      ),
      Padding(
        // The barcode alone can name the company that registered it, offline.
        padding: const EdgeInsetsDirectional.symmetric(horizontal: kCalSide),
        child: BarcodeOwnerHint(barcode: barcode),
      ),
    ],
  );
}

enum _ProductLoaderState { loading, productNotFound, serverError }

enum ProductLoaderMode { viewProduct, editProduct }
