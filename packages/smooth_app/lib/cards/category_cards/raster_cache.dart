import 'package:flutter/material.dart';
import 'package:smooth_app/cards/category_cards/abstract_cache.dart';
import 'package:smooth_app/cards/category_cards/asset_cache_helper.dart';
import 'package:smooth_app/cards/category_cards/raster_async_asset.dart';
import 'package:smooth_app/widgets/company_logo.dart' show greyscale;

/// Widget that displays a png/jpeg from network (and cache while waiting).
class RasterCache extends AbstractCache {
  const RasterCache(super.iconUrl, {super.width, super.height});

  @override
  Widget build(BuildContext context) {
    final List<String> fullFilenames = getCachedFilenames();
    if (fullFilenames.isEmpty) {
      return getDefaultUnknown();
    }

    // Icons in greys, as the rest of the app.
    return ColorFiltered(
      colorFilter: greyscale,
      child: Image.network(
        iconUrl!,
        width: width,
        height: height,
        fit: BoxFit.contain,
        loadingBuilder:
            (
              final BuildContext context,
              final Widget child,
              final ImageChunkEvent? loadingProgress,
            ) {
              if (loadingProgress == null) {
                return child;
              }
              return _localAssetWidget(fullFilenames);
            },
        errorBuilder:
            (
              final BuildContext context,
              final Object error,
              final StackTrace? stackTrace,
            ) => _localAssetWidget(fullFilenames),
      ),
    );
  }

  RasterAsyncAsset _localAssetWidget(List<String> fullFilenames) {
    return RasterAsyncAsset(
      AssetCacheHelper(fullFilenames, iconUrl!, width: width, height: height),
    );
  }
}
