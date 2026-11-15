import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/database/dao_ownership_scan.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/generic_lib/buttons/smooth_simple_button.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/generic_lib/widgets/smooth_card.dart';
import 'package:smooth_app/pages/owner/owner_correction_page.dart';
import 'package:smooth_app/pages/product/product_page/tabs/ownership/ownership_result_view.dart';
import 'package:smooth_app/query/product_query.dart';
import 'package:smooth_app/services/label_ocr.dart';
import 'package:smooth_app/services/label_operator_parser.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/ownership_service.dart';

/// Steps 2-4 of the fallback chain in `projects/ejerskab-app/BRIEF.md`: the
/// barcode itself wasn't recognised, so let the user photograph the package,
/// confirm/reject a vision guess at the brand, then run the normal ownership
/// chain on the confirmed name. Falls through to a manual text field at any
/// point that fails — this card must never end up blank.
class UnknownBarcodeOwnershipCard extends StatefulWidget {
  const UnknownBarcodeOwnershipCard({
    required this.barcode,
    this.labelOcr = const MlKitLabelOcr(),
    super.key,
  });

  final String barcode;
  final LabelOcr labelOcr;

  @override
  State<UnknownBarcodeOwnershipCard> createState() =>
      _UnknownBarcodeOwnershipCardState();
}

enum _Step {
  idle,
  guessingBrand,
  chooseOperator,
  brandGuessPending,
  manualInput,
  resolvingOwnership,
  ownershipGuessPending,
  resolved,
}

class _UnknownBarcodeOwnershipCardState
    extends State<UnknownBarcodeOwnershipCard> {
  final OwnershipService _service = OwnershipService();
  final TextEditingController _manualController = TextEditingController();

  _Step _step = _Step.idle;
  BrandGuess? _brandGuess;
  List<String> _operatorCandidates = const <String>[];
  BrandOwnerResult? _pendingOwner;
  late BrandOwnerResult? _resolvedOwner;
  late EthicsRating? _ethics;
  String? _activeBrand;
  int? _pendingScanId;
  String? _countryCode;
  String? _errorMessage;
  bool _hasManualText = false;

  /// Resolved once the widget is in the tree (never in `initState`, where
  /// the inherited `LocalDatabase` provider may not be reachable yet), so no
  /// handler below ever needs `BuildContext` after an `await`.
  DaoOwnershipScan? _scanDao;

  @override
  void initState() {
    super.initState();
    _manualController.addListener(() {
      final bool hasText = _manualController.text.trim().isNotEmpty;
      if (hasText != _hasManualText) {
        setState(() => _hasManualText = hasText);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scanDao ??= DaoOwnershipScan(context.read<LocalDatabase>());
  }

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  String get _countryTag => _countryCode ??= ProductQuery.getCountry().offTag;

  Future<void> _takePhoto() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (file == null || !mounted) {
      return;
    }
    setState(() {
      _errorMessage = null;
      _step = _Step.guessingBrand;
    });
    final List<String> operators = await _readOperators(file.path);
    if (!mounted) {
      return;
    }
    if (operators.isNotEmpty) {
      setState(() {
        _operatorCandidates = operators;
        _step = _Step.chooseOperator;
      });
      return;
    }
    final Uint8List bytes = await file.readAsBytes();
    final BrandGuess? guess = await _service.guessBrandFromImage(bytes);
    if (!mounted) {
      return;
    }
    if (guess == null) {
      setState(() {
        _errorMessage = 'Could not read the brand. Please type it.';
        _step = _Step.manualInput;
      });
      return;
    }
    setState(() {
      _brandGuess = guess;
      _step = _Step.brandGuessPending;
    });
  }

  /// On-device OCR + EU-label parser (art. 9(1)(h) 1169/2011: the operator's
  /// name must be printed on the pack). Empty list if nothing readable.
  Future<List<String>> _readOperators(final String path) async {
    try {
      final String text = await widget.labelOcr.readText(path);
      return LabelOperatorParser.candidates(text);
    } catch (_) {
      return const <String>[];
    }
  }

  /// The user picked which company on the label markets the product.
  Future<void> _chooseOperator(final String company) async {
    _pendingScanId = await _scanDao!.insertScan(
      barcode: widget.barcode,
      countryCode: _countryTag,
      source: OwnershipScanSource.manual,
      status: OwnershipScanStatus.pendingConfirmation,
      guessedName: company,
    );
    try {
      final OwnershipLocalDb db = await OwnershipLocalDb.load();
      final String? owner = db.ownerOfCompany(company);
      if (owner != null) {
        await _finishResolved(BrandOwnerResult(
          ownerCompany: owner,
          ownerChain: owner == company ? <String>[company] : <String>[company, owner],
          source: BrandOwnerSource.offlineDb,
        ));
        return;
      }
    } catch (_) {
      // Offline DB unavailable: fall through to the online chain.
    }
    await _resolveOwnership(company, labelFallback: true);
  }

  Future<void> _confirmBrandGuess() async {
    final BrandGuess? guess = _brandGuess;
    if (guess == null) {
      return;
    }
    _pendingScanId = await _scanDao!.insertScan(
      barcode: widget.barcode,
      countryCode: _countryTag,
      source: OwnershipScanSource.aiGuess,
      status: OwnershipScanStatus.pendingConfirmation,
      confidence: guess.confidence,
      guessedName: guess.brandName,
    );
    await _resolveOwnership(guess.brandName);
  }

  void _rejectBrandGuess() {
    if (_pendingScanId != null) {
      unawaited(
        _scanDao!.updateStatus(
          _pendingScanId!,
          OwnershipScanStatus.unresolved,
        ),
      );
    }
    setState(() {
      _brandGuess = null;
      _step = _Step.manualInput;
    });
  }

  Future<void> _lookupManualBrand() async {
    final String brand = _manualController.text.trim();
    if (brand.isEmpty) {
      return;
    }
    _pendingScanId = await _scanDao!.insertScan(
      barcode: widget.barcode,
      countryCode: _countryTag,
      source: OwnershipScanSource.manual,
      status: OwnershipScanStatus.pendingConfirmation,
      guessedName: brand,
    );
    await _resolveOwnership(brand);
  }

  /// Cache -> Wikidata -> AI fallback, in trust order. Cache and Wikidata
  /// hits are trusted enough to show (and, for Wikidata, cache) right away;
  /// an AI-fallback chain still needs an explicit human confirm before it is
  /// ever written to the shared cache, same as the "Ejerskab" tab.
  Future<void> _resolveOwnership(final String brand, {final bool labelFallback = false}) async {
    _activeBrand = brand;
    if (!mounted) {
      return;
    }
    setState(() => _step = _Step.resolvingOwnership);
    final String country = _countryTag;

    try {
      final OwnershipLocalDb db = await OwnershipLocalDb.load();
      final LocalOwnerResult? hit = db.lookup(barcode: widget.barcode, brands: brand, countryTags: <String>[country]);
      if (hit != null) {
        await _finishResolved(BrandOwnerResult(
          ownerCompany: hit.owner,
          ownerChain: hit.chain.isEmpty ? <String>[brand, hit.owner] : hit.chain,
          source: hit.source == LocalOwnerSource.user ? BrandOwnerSource.user : BrandOwnerSource.offlineDb,
        ));
        return;
      }
    } catch (_) {
      // Offline DB unavailable: continue with the online chain.
    }

    BrandOwnerResult? owner = await _service.getCachedOwner(
      brand,
      countryCode: country,
    );
    if (owner != null) {
      await _finishResolved(owner);
      return;
    }

    owner = await _service.lookupWikidata(brand);
    if (owner != null) {
      await _service.pushToCentralCache(brand, owner, countryCode: country);
      await _finishResolved(owner);
      return;
    }

    owner = await _service.lookupAiFallback(brand);
    if (owner != null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingOwner = owner;
        _step = _Step.ownershipGuessPending;
      });
      return;
    }

    if (labelFallback) {
      // The label itself is the legal answer: the operator printed on the
      // pack is the company the food is marketed under (EU 1169/2011 art. 8).
      await _finishResolved(BrandOwnerResult(
        ownerCompany: brand,
        ownerChain: <String>[brand],
        source: BrandOwnerSource.label,
      ));
      return;
    }

    if (_pendingScanId != null) {
      await _scanDao!.updateStatus(
        _pendingScanId!,
        OwnershipScanStatus.unresolved,
      );
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _errorMessage =
          'Could not find an owner for "$brand". Try another name.';
      _step = _Step.manualInput;
    });
  }

  Future<void> _confirmOwnershipGuess() async {
    final BrandOwnerResult? pending = _pendingOwner;
    final String? brand = _activeBrand;
    if (pending == null || brand == null) {
      return;
    }
    await _service.pushToCentralCache(
      brand,
      pending,
      countryCode: _countryTag,
    );
    await _finishResolved(pending);
  }

  void _rejectOwnershipGuess() {
    if (_pendingScanId != null) {
      unawaited(
        _scanDao!.updateStatus(
          _pendingScanId!,
          OwnershipScanStatus.unresolved,
        ),
      );
    }
    setState(() {
      _pendingOwner = null;
      _step = _Step.manualInput;
    });
  }

  Future<void> _finishResolved(final BrandOwnerResult owner) async {
    if (_pendingScanId != null) {
      await _scanDao!.updateStatus(
        _pendingScanId!,
        OwnershipScanStatus.resolved,
      );
    }
    final EthicsRating? ethics = await _service.getEthicsRating(
      owner.ownerCompany,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _resolvedOwner = owner;
      _ethics = ethics;
      _step = _Step.resolved;
    });
  }

  @override
  Widget build(final BuildContext context) {
    switch (_step) {
      case _Step.idle:
        return _buildIdle(context);
      case _Step.guessingBrand:
        return const OwnershipLoadingView(label: 'Reading the photo…');
      case _Step.resolvingOwnership:
        return const OwnershipLoadingView(label: 'Looking up the owner…');
      case _Step.chooseOperator:
        return _buildChooseOperator(context);
      case _Step.brandGuessPending:
        return _buildBrandGuessPending(context);
      case _Step.ownershipGuessPending:
        return _buildOwnershipGuessPending(context);
      case _Step.manualInput:
        return _buildManualInput(context);
      case _Step.resolved:
        return _buildResolved(context);
    }
  }

  Widget _buildIdle(final BuildContext context) {
    return SmoothCard(
      margin: const EdgeInsets.only(top: LARGE_SPACE),
      child: Padding(
        padding: const EdgeInsets.all(LARGE_SPACE),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.search, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: SMALL_SPACE),
                Text(
                  'Find the owner anyway',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: SMALL_SPACE),
            const Text('Take a photo of the back. The company behind it is always printed on the pack.'),
            const SizedBox(height: SMALL_SPACE),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SmoothSimpleButton(
                  onPressed: _takePhoto,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.camera_alt),
                      SizedBox(width: SMALL_SPACE),
                      Text('Take photo'),
                    ],
                  ),
                ),
                const SizedBox(width: SMALL_SPACE),
                TextButton(
                  onPressed: () => setState(() => _step = _Step.manualInput),
                  child: const Text('Type the brand'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Red/yellow/green, matching the traffic-light convention the rest of
  /// the app already uses for other scores (see `design_constants.dart`),
  /// so a glance at the bar means the same thing here as everywhere else.
  static Color _confidenceColor(final double confidence) {
    if (confidence >= 0.75) {
      return DARK_GREEN_COLOR;
    }
    if (confidence >= 0.4) {
      return DARK_YELLOW_COLOR;
    }
    return RED_COLOR;
  }

  Widget _buildChooseOperator(final BuildContext context) {
    return SmoothCard(
      margin: const EdgeInsets.only(top: LARGE_SPACE),
      child: Padding(
        padding: const EdgeInsets.all(LARGE_SPACE),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Who is named on the label?',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: VERY_SMALL_SPACE),
            const Text('Pick the company the product is sold under.'),
            const SizedBox(height: SMALL_SPACE),
            for (final String company in _operatorCandidates)
              Padding(
                padding: const EdgeInsets.only(bottom: SMALL_SPACE),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _chooseOperator(company),
                    child: Text(company, textAlign: TextAlign.center),
                  ),
                ),
              ),
            TextButton(
              onPressed: () => setState(() => _step = _Step.manualInput),
              child: const Text('None of these, let me type'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandGuessPending(final BuildContext context) {
    final BrandGuess guess = _brandGuess!;
    return SmoothCard(
      margin: const EdgeInsets.only(top: LARGE_SPACE),
      child: Padding(
        padding: const EdgeInsets.all(LARGE_SPACE),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.auto_awesome, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: SMALL_SPACE),
                Expanded(
                  child: Text(
                    'Is the brand ${guess.brandName}?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: SMALL_SPACE),
            ClipRRect(
              borderRadius: ANGULAR_BORDER_RADIUS,
              child: LinearProgressIndicator(
                value: guess.confidence.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: GREY_COLOR,
                color: _confidenceColor(guess.confidence),
              ),
            ),
            const SizedBox(height: VERY_SMALL_SPACE),
            Text(
              'Confidence: ${(guess.confidence * 100).round()}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: SMALL_SPACE),
            Row(
              children: <Widget>[
                Expanded(
                  child: SmoothSimpleButton(
                    onPressed: _confirmBrandGuess,
                    child: const Text('Yes, correct'),
                  ),
                ),
                const SizedBox(width: SMALL_SPACE),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _rejectBrandGuess,
                    child: const Text('No, wrong'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOwnershipGuessPending(final BuildContext context) {
    final BrandOwnerResult guess = _pendingOwner!;
    return SmoothCard(
      margin: const EdgeInsets.only(top: LARGE_SPACE),
      child: Padding(
        padding: const EdgeInsets.all(LARGE_SPACE),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.auto_awesome, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: SMALL_SPACE),
                Expanded(
                  child: Text(
                    'Is this right?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: LARGE_SPACE),
            OwnershipChainView(chain: guess.ownerChain),
            const SizedBox(height: SMALL_SPACE),
            Row(
              children: <Widget>[
                Expanded(
                  child: SmoothSimpleButton(
                    onPressed: _confirmOwnershipGuess,
                    child: const Text('Yes, correct'),
                  ),
                ),
                const SizedBox(width: SMALL_SPACE),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _rejectOwnershipGuess,
                    child: const Text('No, wrong'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualInput(final BuildContext context) {
    return SmoothCard(
      margin: const EdgeInsets.only(top: LARGE_SPACE),
      child: Padding(
        padding: const EdgeInsets.all(LARGE_SPACE),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.help_outline, color: Theme.of(context).colorScheme.outline),
                const SizedBox(width: SMALL_SPACE),
                Expanded(
                  child: Text(
                    'Which brand is it?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: VERY_SMALL_SPACE),
              Text(
                _errorMessage!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: RED_COLOR),
              ),
            ],
            const SizedBox(height: SMALL_SPACE),
            const Text('What is the brand called?'),
            const SizedBox(height: SMALL_SPACE),
            TextField(
              controller: _manualController,
              textCapitalization: TextCapitalization.words,
              decoration: ownedFieldDecoration(Theme.of(context), hint: 'For example "Oreo"', icon: Icons.sell_rounded),
              onSubmitted: _hasManualText ? (_) => _lookupManualBrand() : null,
            ),
            const SizedBox(height: SMALL_SPACE),
            SmoothSimpleButton(
              minWidth: double.infinity,
              onPressed: _hasManualText ? _lookupManualBrand : null,
              child: const Text('Look up'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResolved(final BuildContext context) {
    final BrandOwnerResult owner = _resolvedOwner!;
    final EthicsRating? ethics = _ethics;
    return Column(
      children: <Widget>[
        SmoothCard(
          margin: const EdgeInsets.only(top: LARGE_SPACE),
          child: Padding(
            padding: const EdgeInsets.all(LARGE_SPACE),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Ownership chain',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: SMALL_SPACE),
                OwnershipChainView(chain: owner.ownerChain),
                const SizedBox(height: SMALL_SPACE),
                OwnershipSourceLine(source: owner.source),
              ],
            ),
          ),
        ),
        SmoothCard(
          child: EthicsRatingSection(
            ownerCompany: owner.ownerCompany,
            ethics: ethics,
          ),
        ),
      ],
    );
  }
}
