import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/data_models/continuous_scan_model.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/pages/owner/moral_score_page.dart';
import 'package:smooth_app/pages/owner/owner_page.dart';
import 'package:smooth_app/pages/scan/result/result_sheet_parts.dart';
import 'package:smooth_app/pages/scan/result/scan_result_page.dart';
import 'package:smooth_app/pages/scan/result/scan_sheet_scaffold.dart';
import 'package:smooth_app/query/product_query.dart';
import 'package:smooth_app/services/avoided_owners.dart';
import 'package:smooth_app/services/brand_text_matcher.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/ownership_norm.dart';
import 'package:smooth_app/services/ownership_service.dart';
import 'package:smooth_app/services/photo_analyzer.dart';
import 'package:smooth_app/widgets/cal_ui.dart';

/// What a photo of a pack opens: the photo stays still while a white line
/// sweeps it ("Analyzing…"), then the answer pops up from the bottom: the
/// owner's logo and name, the moral and health scores as charts, and the
/// rest behind a tap. Finds products that no barcode database knows.
class PhotoResultPage extends StatefulWidget {
  const PhotoResultPage({
    required this.imagePath,
    this.analyzer,
    this.ethicsDb,
    this.countryTags,
    this.minAnalyzing = const Duration(milliseconds: 1600),
    this.analysis,
    this.barcode,
    super.key,
  });

  /// A barcode the live camera read already.
  final String? barcode;

  final String imagePath;

  /// Already read (the home page reads photos in the background): no
  /// "Analyzing…" again.
  final PhotoAnalysis? analysis;

  /// The user's country first (brands differ per country); default from
  /// the app settings.
  final List<String>? countryTags;

  /// The scan line runs at least this long, so the answer never flashes.
  final Duration minAnalyzing;

  /// For tests.
  final PhotoAnalyzer? analyzer;
  final Future<EthicsDb> Function()? ethicsDb;

  static Route<void> route({required final String imagePath, final PhotoAnalysis? analysis, final String? barcode}) =>
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 160),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => PhotoResultPage(imagePath: imagePath, analysis: analysis, barcode: barcode),
        transitionsBuilder: (_, Animation<double> a, _, Widget child) =>
            FadeTransition(opacity: a, child: child),
      );

  @override
  State<PhotoResultPage> createState() => _PhotoResultPageState();
}

class _PhotoResultPageState extends State<PhotoResultPage> {
  PhotoAnalysis? _analysis;
  int _chosen = 0;

  /// A brand the user typed (after "Not right?").
  BrandCandidate? _typed;
  bool _typing = false;
  EthicsDb? _ethics;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final List<String> countries =
        widget.countryTags ?? <String>[ProductQuery.getCountry().offTag];
    final PhotoAnalyzer analyzer = widget.analyzer ?? PhotoAnalyzer();
    final Future<EthicsDb> ethics = (widget.ethicsDb ?? EthicsDb.load)();
    final Future<void> minimum = Future<void>.delayed(widget.analysis == null ? widget.minAnalyzing : Duration.zero);
    final PhotoAnalysis analysis = widget.analysis ?? await analyzer.analyze(widget.imagePath, countryTags: countries, liveBarcode: widget.barcode);
    EthicsDb? db;
    try {
      db = await ethics;
    } catch (_) {}
    if (!mounted) {
      return;
    }
    final String? barcode = analysis.barcode;
    if (barcode != null) {
      // A barcode was in the picture: the full product answer, over the
      // same photo, when a database knows it. When none does, the brand on
      // the photo (or the barcode's company) answers here instead.
      final ContinuousScanModel model = context.read<ContinuousScanModel>();
      await model.onScan(barcode);
      final ScannedProductState? state = await _settled(model, barcode);
      final bool known =
          state == ScannedProductState.FOUND ||
          state == ScannedProductState.CACHED;
      if (!mounted) {
        return;
      }
      if (known || analysis.brands.isEmpty) {
        final Uint8List bytes = await File(widget.imagePath).readAsBytes();
        if (mounted) {
          unawaited(
            Navigator.of(context).pushReplacement(
              ScanResultPage.route(
                barcode: barcode,
                photo: bytes,
                instant: true,
              ),
            ),
          );
        }
        return;
      }
    }
    await minimum;
    if (!mounted) {
      return;
    }
    setState(() {
      _analysis = analysis;
      _ethics = db;
    });
  }

  /// Waits (up to 10 s) until the product of [barcode] is found or not.
  static Future<ScannedProductState?> _settled(
    final ContinuousScanModel model,
    final String barcode,
  ) async {
    bool done(final ScannedProductState? s) =>
        s != null && s != ScannedProductState.LOADING;
    if (done(model.getBarcodeState(barcode))) {
      return model.getBarcodeState(barcode);
    }
    final Completer<void> settled = Completer<void>();
    void listen() {
      if (done(model.getBarcodeState(barcode)) && !settled.isCompleted) {
        settled.complete();
      }
    }

    model.addListener(listen);
    try {
      await settled.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      // Too slow: answer from the photo.
    } finally {
      model.removeListener(listen);
    }
    return model.getBarcodeState(barcode);
  }

  BrandCandidate? get _current {
    if (_typed != null) {
      return _typed;
    }
    final List<BrandCandidate> brands =
        _analysis?.brands ?? const <BrandCandidate>[];
    return brands.isEmpty ? null : brands[_chosen.clamp(0, brands.length - 1)];
  }

  Future<void> _typeBrand() async {
    final String? brand = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _TypeBrandDialog(),
    );
    if (brand == null || brand.trim().isEmpty || !mounted) {
      return;
    }
    setState(() => _typing = true);
    BrandCandidate? found;
    try {
      final OwnershipLocalDb db = await OwnershipLocalDb.load();
      final LocalOwnerResult? local = db.lookup(
        barcode: '',
        brands: brand,
        countryTags:
            widget.countryTags ?? <String>[ProductQuery.getCountry().offTag],
      );
      LocalOwnerResult? owner = local;
      if (owner == null) {
        final BrandOwnerResult? online = await OwnershipService()
            .lookupWikidata(brand.trim());
        if (online != null) {
          owner = LocalOwnerResult(
            owner: online.ownerCompany,
            source: LocalOwnerSource.other,
            chain: online.ownerChain,
          );
        }
      }
      if (owner != null) {
        found = BrandCandidate(
          key: OwnershipNorm.normCore(brand),
          name: brand.trim(),
          owner: owner,
          score: 0.0,
        );
      }
    } catch (_) {}
    if (!mounted) {
      return;
    }
    setState(() {
      _typing = false;
      _typed = found;
    });
    if (found == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('We could not find who owns "${brand.trim()}" yet.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ImageProvider photo = FileImage(File(widget.imagePath));
    final PhotoAnalysis? analysis = _analysis;
    if (analysis == null || _typing) {
      return ScanSheetScaffold(
        photo: ScanPhoto(image: photo),
        leading: _closeButton(context),
        analyzing: true,
        slivers: const <Widget>[],
      );
    }
    final BrandCandidate? current = _current;
    return ScanSheetScaffold(
      photo: ScanPhoto(image: photo),
      leading: _closeButton(context),
      title: current?.owner.owner,
      bottomBar: SheetActions(secondary: 'Not right?', onSecondary: _typeBrand),
      slivers: current == null
          ? <Widget>[
              SliverToBoxAdapter(child: _NothingFound(onType: _typeBrand, seenBrand: analysis.seenBrand)),
            ]
          : _found(context, current, analysis),
    );
  }

  List<Widget> _found(
    final BuildContext context,
    final BrandCandidate current,
    final PhotoAnalysis analysis,
  ) {
    final ThemeData theme = Theme.of(context);
    final EthicsCompany? company = _ethics?.forOwner(
      current.owner.owner,
      chain: current.owner.ethicsChain,
    );
    final EthicsScoreResult? ethics = company == null
        ? null
        : EthicsScore.compute(company);
    final String ownerName = EthicsDb.displayName(current.owner.owner, company);
    final List<String> chain = <String>[
      current.name,
      for (final String c in current.owner.chain)
        if (OwnershipNorm.normCore(c) != OwnershipNorm.normCore(current.name))
          c,
    ];
    final List<BrandCandidate> others = _typed == null
        ? analysis.brands
        : const <BrandCandidate>[];
    final String how = _typed != null
        ? 'the brand you typed'
        : current.owner.source == LocalOwnerSource.labelCompany
        ? 'the company on the label'
        : current.owner.source == LocalOwnerSource.barcodePrefix
        ? 'from the barcode'
        : 'read on your photo';
    final String? barcode = analysis.barcode;
    void openOwner() => Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => OwnerPage(
          name: ownerName,
          dbName: current.owner.owner,
          company: company,
          controlledBy: current.owner.controlledBy,
        ),
      ),
    );
    return <Widget>[
      SliverPadding(
        padding: const EdgeInsetsDirectional.fromSTEB(20.0, 6.0, 20.0, 0.0),
        sliver: SliverList.list(
          children: <Widget>[
            ListenableBuilder(
              listenable: AvoidedOwners.instance,
              builder: (BuildContext context, _) => OwnerResultHeader(
                ownerName: ownerName,
                logoNames: <String?>[
                  ownerName,
                  current.owner.owner,
                  ...current.owner.ethicsChain,
                ],
                subtitle: '${current.name} · $how',
                avoided: AvoidedOwners.instance.isAvoided(<String?>[
                  ownerName,
                  current.owner.owner,
                  ...current.owner.ethicsChain,
                ]),
                onTap: openOwner,
              ),
            ),
            const SizedBox(height: 18.0),
            ScorePair(
              moral: ethics?.score,
              moralVerdict: ethics == null ? 'Not rated yet' : null,
              health: null,
              healthVerdict: barcode == null ? 'Scan barcode' : 'No data yet',
              onHealthTap: barcode != null
                  ? null
                  : () => DetailsPage.open(
                      context,
                      'Health score',
                      const _HealthNeedsBarcode(),
                    ),
              onMoralTap: () => MoralScorePage.open(
                context,
                result: ethics,
                ownerName: current.owner.owner,
                db: _ethics,
              ),
            ),
            if (others.length > 1) ...<Widget>[
              const SizedBox(height: 22.0),
              Text('Also on the pack', style: theme.textTheme.titleSmall),
              const SizedBox(height: 10.0),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: <Widget>[
                  for (int i = 0; i < others.length; i++)
                    CalPill(
                      label: others[i].name,
                      selected: i == _chosen,
                      onTap: () => setState(() => _chosen = i),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 22.0),
            MoreRows(
              rows: <MoreRow>[
                if (chain.length > 1)
                  MoreRow(
                    icon: Icons.account_tree_outlined,
                    title: 'Ownership chain',
                    detail: chain.join(' → '),
                    onTap: () => DetailsPage.open(
                      context,
                      'Ownership chain',
                      _ChainList(chain: chain),
                    ),
                  ),
                MoreRow(
                  icon: Icons.domain_rounded,
                  title: 'About $ownerName',
                  detail: 'Brands, record and your scans',
                  onTap: openOwner,
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  Widget _closeButton(final BuildContext context) => GlassIconButton(
    icon: Icons.close_rounded,
    tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
    onPressed: () => Navigator.of(context).maybePop(),
  );
}

/// The ownership chain, brand first, as a short vertical timeline.
class _ChainList extends StatelessWidget {
  const _ChainList({required this.chain});

  final List<String> chain;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int i = 0; i < chain.length; i++)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    width: 24.0,
                    child: Column(
                      children: <Widget>[
                        Container(
                          margin: const EdgeInsetsDirectional.only(top: 6.0),
                          width: 10.0,
                          height: 10.0,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == chain.length - 1
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.outline,
                          ),
                        ),
                        if (i < chain.length - 1)
                          Expanded(
                            child: Container(
                              width: 2.0,
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10.0),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(bottom: 18.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            i == 0
                                ? 'Brand'
                                : i == chain.length - 1
                                ? 'Owner'
                                : 'Part of',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(chain[i], style: theme.textTheme.titleMedium),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HealthNeedsBarcode extends StatelessWidget {
  const _HealthNeedsBarcode();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 20.0),
      child: Text(
        'The health score is worked out from the nutrition table of one '
        'exact product. A photo of the front tells us the brand, not the '
        'product. Snap the barcode (or the whole pack with the barcode in '
        'view) to see it.',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _NothingFound extends StatelessWidget {
  const _NothingFound({required this.onType, this.seenBrand = ''});

  final VoidCallback onType;

  /// A brand read on the photo whose owner is not known yet.
  final String seenBrand;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20.0, 6.0, 20.0, 0.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(seenBrand.isEmpty ? 'No brand found' : seenBrand, style: theme.textTheme.displaySmall),
          const SizedBox(height: 6.0),
          Text(
            seenBrand.isEmpty
                ? 'We could not read a brand we know on this photo.'
                : 'We can see the brand, but we do not know who owns $seenBrand yet. The barcode tells us the exact product.',
            style: theme.textTheme.bodyLarge?.copyWith(color: muted),
          ),
          const SizedBox(height: 20.0),
          MoreRows(
            rows: <MoreRow>[
              MoreRow(
                icon: Icons.center_focus_strong_outlined,
                title: 'Fill the frame with the logo',
                detail: 'The brand name is read best up close',
                onTap: () => Navigator.of(context).maybePop(),
              ),
              MoreRow(
                icon: Icons.qr_code_2_rounded,
                title: 'Get the barcode in the photo',
                detail: 'Then we know the exact product',
                onTap: () => Navigator.of(context).maybePop(),
              ),
              MoreRow(
                icon: Icons.flip_rounded,
                title: 'Or snap the back',
                detail: 'The company is named near the address',
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          const SizedBox(height: LARGE_SPACE),
          OutlinedButton.icon(
            onPressed: onType,
            icon: const Icon(Icons.keyboard_rounded, size: 20.0),
            label: const Text('Type the brand'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52.0),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeBrandDialog extends StatefulWidget {
  const _TypeBrandDialog();

  @override
  State<_TypeBrandDialog> createState() => _TypeBrandDialogState();
}

class _TypeBrandDialogState extends State<_TypeBrandDialog> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Which brand is it?'),
      content: TextField(
        controller: _text,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'For example Lurpak'),
        onSubmitted: (String v) => Navigator.of(context).pop(v),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_text.text),
          child: const Text('Find owner'),
        ),
      ],
    );
  }
}
