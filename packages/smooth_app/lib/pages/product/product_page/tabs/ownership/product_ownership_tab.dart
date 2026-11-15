import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/database/dao_ownership_scan.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/generic_lib/buttons/smooth_simple_button.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/generic_lib/widgets/smooth_card.dart';
import 'package:smooth_app/pages/owner/owner_correction_page.dart';
import 'package:smooth_app/pages/product/product_page/overview/ethics_details.dart';
import 'package:smooth_app/pages/product/product_page/tabs/ownership/ownership_provider.dart';
import 'package:smooth_app/pages/product/product_page/tabs/ownership/ownership_result_view.dart';
import 'package:smooth_app/pages/product/product_page/widgets/product_page_title.dart';
import 'package:smooth_app/query/product_query.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/ownership_service.dart';

/// "Ejerskab" tab: who actually owns this brand, and (if curated) an ethics
/// note. See `projects/ejerskab-app/BRIEF.md` for the fallback chain this
/// implements — the tab must never render blank.
class ProductOwnershipTab extends StatelessWidget {
  const ProductOwnershipTab(this.product, {this.askUser = false, this.onUseOwner});

  final Product product;

  /// Start by asking for the brand (the user said the answer is wrong).
  final bool askUser;

  /// Keeps an owner found from a typed brand for this product.
  final ValueChanged<String>? onUseOwner;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<OwnershipProvider>(
      create: (BuildContext context) => OwnershipProvider(
        product: product,
        countryCode: ProductQuery.getCountry().offTag,
        service: OwnershipService(),
        scanDao: DaoOwnershipScan(context.read<LocalDatabase>()),
        askUser: askUser,
      ),
      child: _OwnershipTabBody(onUseOwner: onUseOwner),
    );
  }
}

class _OwnershipTabBody extends StatelessWidget {
  const _OwnershipTabBody({this.onUseOwner});

  final ValueChanged<String>? onUseOwner;

  @override
  Widget build(BuildContext context) {
    final OwnershipProvider provider = context.watch<OwnershipProvider>();

    switch (provider.status) {
      case OwnershipStatus.loading:
        return const OwnershipLoadingView();
      case OwnershipStatus.resolved:
        return _ResolvedView(provider: provider, onUseOwner: onUseOwner);
      case OwnershipStatus.pendingConfirmation:
        return _PendingConfirmationView(provider: provider);
      case OwnershipStatus.noBrand:
      case OwnershipStatus.unresolved:
        return _ManualInputView(provider: provider);
    }
  }
}

class _ResolvedView extends StatelessWidget {
  const _ResolvedView({required this.provider, this.onUseOwner});

  final OwnershipProvider provider;
  final ValueChanged<String>? onUseOwner;

  @override
  Widget build(BuildContext context) {
    final BrandOwnerResult owner = provider.result!;
    final EthicsRating? ethics = provider.ethics;

    return ListView(
      padding: const EdgeInsets.all(SMALL_SPACE),
      children: <Widget>[
        SmoothCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const ProductPageTitle(label: 'Ownership chain'),
              Padding(
                padding: const EdgeInsets.all(LARGE_SPACE),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    OwnershipChainView(chain: owner.ownerChain),
                    const SizedBox(height: SMALL_SPACE),
                    OwnershipSourceLine(source: owner.source),
                    if (onUseOwner != null && provider.fromTypedBrand) ...<Widget>[
                      const SizedBox(height: LARGE_SPACE),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => onUseOwner!(owner.ownerCompany),
                          child: Text('Use ${owner.ownerCompany} for this product'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        FutureBuilder<EthicsDb>(
          future: EthicsDb.load(),
          builder: (BuildContext context, AsyncSnapshot<EthicsDb> snapshot) {
            final EthicsDb? db = snapshot.data;
            if (db == null) {
              return snapshot.hasError || ethics == null
                  ? EMPTY_WIDGET
                  : SmoothCard(
                      child: EthicsRatingSection(
                        ownerCompany: owner.ownerCompany,
                        ethics: ethics,
                      ),
                    );
            }
            final EthicsCompany? company = db.forOwner(
              owner.ownerCompany,
              chain: owner.ethicsChain,
            );
            return EthicsDetails(
              result: company == null ? null : EthicsScore.compute(company),
              ownerName: owner.ownerCompany,
              db: db,
            );
          },
        ),
      ],
    );
  }
}

class _PendingConfirmationView extends StatelessWidget {
  const _PendingConfirmationView({required this.provider});

  final OwnershipProvider provider;

  @override
  Widget build(BuildContext context) {
    final BrandOwnerResult guess = provider.result!;

    return Padding(
      padding: const EdgeInsets.all(SMALL_SPACE),
      child: SmoothCard(
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
              const SizedBox(height: LARGE_SPACE),
              Row(
                children: <Widget>[
                  Expanded(
                    child: SmoothSimpleButton(
                      onPressed: provider.confirmAiGuess,
                      child: const Text('Yes, correct'),
                    ),
                  ),
                  const SizedBox(width: SMALL_SPACE),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: provider.rejectAiGuess,
                      child: const Text('No, wrong'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualInputView extends StatefulWidget {
  const _ManualInputView({required this.provider});

  final OwnershipProvider provider;

  @override
  State<_ManualInputView> createState() => _ManualInputViewState();
}

class _ManualInputViewState extends State<_ManualInputView> {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final bool hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() => _hasText = hasText);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool noBrand = widget.provider.status == OwnershipStatus.noBrand;

    return Padding(
      padding: const EdgeInsets.all(SMALL_SPACE),
      child: SmoothCard(
        child: Padding(
          padding: const EdgeInsets.all(LARGE_SPACE),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.help_outline,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: SMALL_SPACE),
                  Expanded(
                    child: Text(
                      noBrand
                          ? 'There is no brand on this product yet.'
                          : 'Which brand is it?',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: SMALL_SPACE),
              const Text('Type the brand on the pack and we will look up who owns it.'),
              const SizedBox(height: SMALL_SPACE),
              TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.words,
                decoration: ownedFieldDecoration(Theme.of(context), hint: 'For example "Oreo"', icon: Icons.sell_rounded),
                onSubmitted: _hasText ? widget.provider.lookupManualBrand : null,
              ),
              const SizedBox(height: SMALL_SPACE),
              SmoothSimpleButton(
                minWidth: double.infinity,
                onPressed: _hasText
                    ? () => widget.provider.lookupManualBrand(_controller.text)
                    : null,
                child: const Text('Look up'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
