import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:smooth_app/database/dao_ownership_scan.dart';
import 'package:smooth_app/services/owner_overrides.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/ownership_service.dart';

/// Where the "Ejerskab" tab currently is in the fallback chain from
/// `projects/ejerskab-app/BRIEF.md`.
enum OwnershipStatus {
  loading,
  resolved,
  pendingConfirmation,
  unresolved,
  noBrand,
}

/// Drives the ownership lookup for one product: central cache -> Wikidata
/// -> AI fallback -> manual input, never leaving the tab blank.
class OwnershipProvider extends ChangeNotifier {
  OwnershipProvider({
    required this.product,
    required this.countryCode,
    required this.service,
    required this.scanDao,
    Future<OwnershipLocalDb> Function()? localDb,
    final bool askUser = false,
  }) : localDb = localDb ?? OwnershipLocalDb.load {
    if (askUser) {
      // The user said the answer is wrong: ask for the brand instead of
      // showing the same answer again.
      status = OwnershipStatus.unresolved;
    } else {
      unawaited(_resolveFromProduct());
      // Corrections load at start-up and can change on other screens.
      OwnerOverrides.instance.addListener(_onCorrections);
    }
  }

  void _onCorrections() {
    if (status != OwnershipStatus.loading) {
      unawaited(refresh());
    }
  }

  final Product product;
  final String countryCode;
  final OwnershipService service;
  final DaoOwnershipScan scanDao;
  final Future<OwnershipLocalDb> Function() localDb;

  OwnershipStatus status = OwnershipStatus.loading;
  BrandOwnerResult? result;

  /// [result] answers a brand the user typed, not the product's own data.
  bool fromTypedBrand = false;
  EthicsRating? ethics;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    OwnerOverrides.instance.removeListener(_onCorrections);
    super.dispose();
  }

  /// Lookups finish after the page may have closed.
  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  /// The brand name currently being resolved (from the product, or typed in
  /// manually) — kept so a confirm/retry knows what to cache against.
  String? _activeBrandName;
  int? _pendingScanId;

  Future<void> _resolveFromProduct() async {
    final BrandOwnerResult? offline = await _lookupOffline();
    if (offline != null) {
      _activeBrandName = product.getFirstBrand()?.trim();
      await _logScan(
        source: OwnershipScanSource.barcodeMatch,
        status: OwnershipScanStatus.resolved,
      );
      await _applyResolved(offline);
      return;
    }
    final String? brand = product.getFirstBrand()?.trim();
    if (brand == null || brand.isEmpty) {
      status = OwnershipStatus.noBrand;
      notifyListeners();
      return;
    }
    await _runChain(brand, source: OwnershipScanSource.barcodeMatch);
  }

  /// Looks again after the user saved or removed a correction.
  /// The scan was logged the first time; a refresh does not log it again.
  Future<void> refresh() async {
    status = OwnershipStatus.loading;
    result = null;
    ethics = null;
    fromTypedBrand = false;
    notifyListeners();
    _refreshing = true;
    try {
      await _resolveFromProduct();
    } finally {
      _refreshing = false;
    }
  }

  bool _refreshing = false;

  Future<int?> _logScan({
    required final OwnershipScanSource source,
    required final OwnershipScanStatus status,
    final String? guessedName,
  }) async {
    if (_refreshing) {
      return null;
    }
    return scanDao.insertScan(
      barcode: product.barcode,
      countryCode: countryCode,
      source: source,
      status: status,
      guessedName: guessedName,
    );
  }

  /// Last-resort fallback (BRIEF.md step 4): the user types the brand name
  /// themselves when nothing else resolved it.
  Future<void> lookupManualBrand(final String typedBrand) async {
    final String brand = typedBrand.trim();
    if (brand.isEmpty) {
      return;
    }
    status = OwnershipStatus.loading;
    fromTypedBrand = true;
    notifyListeners();
    // The offline database first, as for a scan.
    try {
      final LocalOwnerResult? hit = (await localDb()).lookup(
        barcode: '',
        brands: brand,
        countryTags: product.countriesTags ?? const <String>[],
      );
      if (hit != null) {
        await _applyResolved(
          BrandOwnerResult(
            ownerCompany: hit.owner,
            ownerChain: hit.chain.isEmpty ? <String>[brand, hit.owner] : hit.chain,
            source: BrandOwnerSource.offlineDb,
            controlledBy: hit.controlledBy,
          ),
        );
        return;
      }
    } catch (_) {
      // No offline data: ask online.
    }
    await _runChain(brand, source: OwnershipScanSource.manual);
  }

  /// Runs cache -> Wikidata -> AI fallback for [brand], in that trust order,
  /// and updates [status]/[result] accordingly.
  Future<void> _runChain(
    final String brand, {
    required final OwnershipScanSource source,
  }) async {
    _activeBrandName = brand;

    final BrandOwnerResult? cached = await service.getCachedOwner(
      brand,
      countryCode: countryCode,
    );
    if (cached != null) {
      await _logScan(
        source: source,
        status: OwnershipScanStatus.resolved,
      );
      await _applyResolved(cached);
      return;
    }

    final BrandOwnerResult? wiki = await service.lookupWikidata(brand);
    if (wiki != null) {
      await service.pushToCentralCache(brand, wiki, countryCode: countryCode);
      await _logScan(
        source: source,
        status: OwnershipScanStatus.resolved,
      );
      await _applyResolved(wiki);
      return;
    }

    final BrandOwnerResult? ai = await service.lookupAiFallback(brand);
    if (ai != null) {
      _pendingScanId = await _logScan(
        source: OwnershipScanSource.aiGuess,
        status: OwnershipScanStatus.pendingConfirmation,
        guessedName: ai.ownerCompany,
      );
      result = ai;
      status = OwnershipStatus.pendingConfirmation;
      notifyListeners();
      return;
    }

    await _logScan(
      source: source,
      status: OwnershipScanStatus.unresolved,
    );
    status = OwnershipStatus.unresolved;
    notifyListeners();
  }

  /// User confirmed an AI guess ("Jeg tror det er X — korrekt?" -> yes).
  /// Only now is it safe to push it to the shared central cache.
  Future<void> confirmAiGuess() async {
    final BrandOwnerResult? pending = result;
    final String? brand = _activeBrandName;
    if (pending == null || brand == null) {
      return;
    }
    await service.pushToCentralCache(brand, pending, countryCode: countryCode);
    if (_pendingScanId != null) {
      await scanDao.updateStatus(_pendingScanId!, OwnershipScanStatus.resolved);
    }
    await _applyResolved(pending);
  }

  /// User rejected the AI guess — fall through to manual input rather than
  /// show a wrong answer.
  void rejectAiGuess() {
    if (_pendingScanId != null) {
      unawaited(
        scanDao.updateStatus(_pendingScanId!, OwnershipScanStatus.unresolved),
      );
    }
    result = null;
    status = OwnershipStatus.unresolved;
    notifyListeners();
  }

  /// Offline database first: free, instant, no network (see BRIEF.md).
  Future<BrandOwnerResult?> _lookupOffline() async {
    final String? barcode = product.barcode;
    if (barcode == null) {
      return null;
    }
    try {
      final OwnershipLocalDb db = await localDb();
      final LocalOwnerResult? hit = db.lookup(
        barcode: barcode,
        brands: product.brands,
        countryTags: product.countriesTags ?? const <String>[],
        embCodeTags: embCodeTags(product.embCodes),
      );
      if (hit == null) {
        return null;
      }
      return BrandOwnerResult(
        ownerCompany: hit.owner,
        ownerChain: hit.chain.isEmpty ? <String>[hit.owner] : hit.chain,
        source: hit.source == LocalOwnerSource.user ? BrandOwnerSource.user : BrandOwnerSource.offlineDb,
        controlledBy: hit.controlledBy,
      );
    } catch (_) {
      return null;
    }
  }

  static List<String> embCodeTags(final String? embCodes) => OwnershipLocalDb.embCodeTags(embCodes);

  Future<void> _applyResolved(final BrandOwnerResult owner) async {
    result = owner;
    ethics = await service.getEthicsRating(owner.ownerCompany);
    status = OwnershipStatus.resolved;
    notifyListeners();
  }
}
