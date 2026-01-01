import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/data_models/continuous_scan_model.dart';
import 'package:smooth_app/database/dao_product.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/pages/owner/owner_page.dart';
import 'package:smooth_app/pages/product/product_page/overview/overview_card.dart';
import 'package:smooth_app/pages/product/product_page/overview/product_facts_page.dart';
import 'package:smooth_app/pages/product/product_page/overview/product_overview.dart';
import 'package:smooth_app/pages/product/product_page/tabs/ownership/barcode_owner_hint.dart';
import 'package:smooth_app/pages/product/product_page/tabs/ownership/unknown_barcode_ownership_card.dart';
import 'package:smooth_app/pages/scan/result/result_sheet_parts.dart';
import 'package:smooth_app/pages/scan/result/scan_sheet_scaffold.dart';
import 'package:smooth_app/query/product_query.dart';
import 'package:smooth_app/services/brand_text_matcher.dart';
import 'package:smooth_app/services/photo_analyzer.dart';
import 'package:smooth_app/widgets/cal_ui.dart';

/// What a barcode scan opens: the frame it was read from, with the answer
/// popping up over it as a sheet. While the product loads the sheet says so;
/// an unknown code gets the owner hint from the barcode and ways to help.
class ScanResultPage extends StatelessWidget {
  const ScanResultPage({required this.barcode, this.photo, super.key});

  final String barcode;
  final Uint8List? photo;

  /// [instant]: replaces a page that already shows the same photo.
  static Route<void> route({
    required final String barcode,
    final Uint8List? photo,
    final bool instant = false,
  }) => PageRouteBuilder<void>(
    transitionDuration: instant
        ? Duration.zero
        : const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => ScanResultPage(barcode: barcode, photo: photo),
    transitionsBuilder: (_, Animation<double> a, _, Widget child) =>
        FadeTransition(opacity: a, child: child),
  );

  @override
  Widget build(BuildContext context) {
    final ContinuousScanModel model = context.watch<ContinuousScanModel>();
    final ScannedProductState? state = model.getBarcodeState(barcode);
    switch (state) {
      case ScannedProductState.FOUND:
      case ScannedProductState.CACHED:
        return _Loaded(barcode: barcode, photo: photo);
      case ScannedProductState.NOT_FOUND:
      case ScannedProductState.FOUND_BUT_CONSIDERED_AS_NOT_FOUND:
        return _Unknown(barcode: barcode, photo: photo);
      case ScannedProductState.ERROR_INTERNET:
        return _Unknown(
          barcode: barcode,
          photo: photo,
          offline: true,
          onRetry: () => model.retryBarcodeFetch(barcode),
        );
      case ScannedProductState.LOADING:
      case null:
        return _Analyzing(photo: photo);
    }
  }
}

ImageProvider? _image(final Uint8List? photo) =>
    photo == null ? null : MemoryImage(photo);

Widget _close(final BuildContext context) => GlassIconButton(
  icon: Icons.close_rounded,
  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
  onPressed: () => Navigator.of(context).maybePop(),
);

class _Loaded extends StatefulWidget {
  const _Loaded({required this.barcode, required this.photo});

  final String barcode;
  final Uint8List? photo;

  @override
  State<_Loaded> createState() => _LoadedState();
}

class _LoadedState extends State<_Loaded> {
  late final Future<Product?> _product = DaoProduct(
    context.read<LocalDatabase>(),
  ).get(widget.barcode);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Product?>(
      future: _product,
      builder: (BuildContext context, AsyncSnapshot<Product?> snapshot) {
        final Product? product = snapshot.data;
        if (product == null) {
          return _Analyzing(photo: widget.photo);
        }
        return Scaffold(
          body: ProductOverview(
            product: product,
            photo: widget.photo,
            leading: const _CloseIcon(),
            onShowDetails: () => ProductFactsPage.open(context, product),
          ),
        );
      },
    );
  }
}

class _CloseIcon extends StatelessWidget {
  const _CloseIcon();

  @override
  Widget build(BuildContext context) => CalRoundButton(
    icon: CupertinoIcons.xmark,
    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
    onTap: () => Navigator.of(context).maybePop(),
  );
}

class _Analyzing extends StatelessWidget {
  const _Analyzing({required this.photo});

  final Uint8List? photo;

  @override
  Widget build(BuildContext context) {
    return ScanSheetScaffold(
      photo: ScanPhoto(image: _image(photo)),
      leading: _close(context),
      analyzing: true,
      slivers: const <Widget>[],
    );
  }
}

class _Unknown extends StatelessWidget {
  const _Unknown({
    required this.barcode,
    required this.photo,
    this.offline = false,
    this.onRetry,
  });

  final String barcode;
  final Uint8List? photo;
  final bool offline;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ScanSheetScaffold(
      photo: ScanPhoto(image: _image(photo)),
      leading: _close(context),
      title: offline ? 'No connection' : 'New product',
      bottomBar: const SheetActions(),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              LARGE_SPACE,
              SMALL_SPACE,
              LARGE_SPACE,
              0.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  offline
                      ? 'You are offline'
                      : "We don't know this product yet",
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: 4.0),
                Text(
                  offline
                      ? 'The product could not be loaded. Here is what the barcode tells us.'
                      : 'Here is what the barcode tells us. Snap the pack and we will read the brand.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (onRetry != null) ...<Widget>[
                  const SizedBox(height: SMALL_SPACE),
                  OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try again'),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (photo != null)
          SliverToBoxAdapter(child: _BrandOnPhoto(photo: photo!)),
        SliverToBoxAdapter(
          child: OverviewCard(child: BarcodeOwnerHint(barcode: barcode)),
        ),
        if (!offline)
          SliverToBoxAdapter(
            child: UnknownBarcodeOwnershipCard(barcode: barcode),
          ),
        SliverToBoxAdapter(
          child: Center(
            child: Text(
              barcode,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// An unknown barcode: the frame it was read from often shows the brand or
/// the company too. Read it on the phone (offline data only, no guessing
/// online) and show the owner when found.
class _BrandOnPhoto extends StatefulWidget {
  const _BrandOnPhoto({required this.photo});

  final Uint8List photo;

  @override
  State<_BrandOnPhoto> createState() => _BrandOnPhotoState();
}

class _BrandOnPhotoState extends State<_BrandOnPhoto> {
  BrandCandidate? _found;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    try {
      final Directory dir = await getTemporaryDirectory();
      final File file = File('${dir.path}/owned_scan_frame.jpg');
      await file.writeAsBytes(widget.photo, flush: true);
      final PhotoAnalysis a =
          await PhotoAnalyzer(
            readBarcode: (_) async => null,
            online: (_) async => null,
          ).analyze(
            file.path,
            countryTags: <String>[ProductQuery.getCountry().offTag],
          );
      if (mounted && a.brands.isNotEmpty) {
        setState(() => _found = a.brands.first);
      }
    } catch (_) {
      // Nothing readable: the rest of the sheet still helps.
    }
  }

  @override
  Widget build(BuildContext context) {
    final BrandCandidate? found = _found;
    if (found == null) {
      return const SizedBox.shrink();
    }
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        LARGE_SPACE,
        MEDIUM_SPACE,
        LARGE_SPACE,
        SMALL_SPACE,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'On your photo: ${found.name}',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: SMALL_SPACE),
          OwnerResultHeader(
            ownerName: found.owner.owner,
            logoNames: <String?>[found.owner.owner, ...found.owner.ethicsChain],
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => OwnerPage(
                  name: found.owner.owner,
                  controlledBy: found.owner.controlledBy,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
