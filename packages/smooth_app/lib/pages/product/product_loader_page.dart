import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/data_models/fetched_product.dart';
import 'package:smooth_app/database/dao_product.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/pages/navigator/app_navigator.dart';
import 'package:smooth_app/pages/product/common/product_refresher.dart';
import 'package:smooth_app/pages/product/product_page/tabs/ownership/barcode_owner_hint.dart';
import 'package:smooth_app/pages/product/product_page/tabs/ownership/unknown_barcode_ownership_card.dart';
import 'package:smooth_app/query/product_query.dart';
import 'package:smooth_app/widgets/cal_ui.dart';

/// Opens a product by barcode: from the phone's cache at once, else from
/// Open Food Facts. When the server says no (not found, or 429 "Too Many
/// Requests", which Open Food Facts answers after a handful of quick
/// lookups) and the caller already knows something about the product (a
/// search hit's name, brand and photo: [fallback]), that opens instead of
/// an error page (17/11). The full data then arrives in the background.
class ProductLoaderPage extends StatefulWidget {
  const ProductLoaderPage({
    required this.barcode,
    required this.mode,
    this.fallback,
    this.fetch,
    this.onOpen,
    super.key,
  }) : assert(barcode != '');

  final String barcode;
  final ProductLoaderMode mode;

  /// What the caller knows already (a search hit), shown if the server fails.
  final Product? fallback;

  /// For tests: replaces the cache + server lookup.
  final Future<FetchedProduct> Function(String barcode)? fetch;

  /// For tests: replaces opening the product page.
  final void Function(Product product)? onOpen;

  @override
  State<ProductLoaderPage> createState() => _ProductLoaderPageState();
}

class _ProductLoaderPageState extends State<ProductLoaderPage> {
  _ProductLoaderState _state = _ProductLoaderState.loading;

  /// One quiet retry after a "Too Many Requests" or a network hiccup.
  static const Duration _retryAfter = Duration(milliseconds: 1500);

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProduct();
    });
  }

  Future<FetchedProduct> _fetchOnce() async {
    if (widget.fetch != null) {
      return widget.fetch!(widget.barcode);
    }
    try {
      return await ProductRefresher()
          .silentFetchAndRefresh(barcode: widget.barcode, localDatabase: context.read<LocalDatabase>())
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      return FetchedProduct.error(exceptionString: e.toString(), isConnected: true);
    }
  }

  void _open(final Product product) {
    if (widget.onOpen != null) {
      widget.onOpen!(product);
      return;
    }
    final AppNavigator navigator = AppNavigator.of(context);
    if (widget.mode == ProductLoaderMode.editProduct) {
      navigator.pushReplacement(AppRoutes.PRODUCT_EDITOR(widget.barcode), extra: product);
      return;
    }
    navigator.pushReplacement(
      AppRoutes.PRODUCT(widget.barcode, heroTag: 'product_${widget.barcode}'),
      extra: product,
    );
  }

  Future<void> _loadProduct() async {
    setState(() {
      _state = _ProductLoaderState.loading;
    });

    // Seen before: open at once (the product page refreshes it quietly).
    if (widget.fetch == null && widget.mode == ProductLoaderMode.viewProduct) {
      Product? cached;
      try {
        cached = await DaoProduct(context.read<LocalDatabase>()).get(widget.barcode);
      } catch (_) {}
      if (!mounted) {
        return;
      }
      if (cached != null) {
        _open(cached);
        return;
      }
    }

    FetchedProduct fetched = await _fetchOnce();
    if (fetched.product == null && fetched.status == FetchedProductStatus.internetError) {
      await Future<void>.delayed(_retryAfter);
      if (!mounted) {
        return;
      }
      fetched = await _fetchOnce();
    }
    if (!mounted) {
      return;
    }
    if (fetched.product != null) {
      _open(fetched.product!);
      return;
    }
    final Product? fallback = widget.mode == ProductLoaderMode.viewProduct ? widget.fallback : null;
    if (fallback != null) {
      // Kept, so it shows in "Recently scanned"; the product page fills in
      // the rest from the server later.
      if (widget.fetch == null) {
        try {
          await DaoProduct(
            context.read<LocalDatabase>(),
          ).put(fallback, ProductQuery.getLanguage(), productType: fallback.productType ?? ProductType.food);
        } catch (_) {}
      }
      if (mounted) {
        _open(fallback);
      }
      return;
    }
    setState(() {
      _state = fetched.status == FetchedProductStatus.internetNotFound
          ? _ProductLoaderState.productNotFound
          : _ProductLoaderState.serverError;
    });
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
        body: 'The product database did not answer. Try again in a moment. What Owned knows without it:',
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
