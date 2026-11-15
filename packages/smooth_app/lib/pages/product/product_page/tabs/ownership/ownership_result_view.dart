import 'package:flutter/material.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/helpers/launch_url_helper.dart';
import 'package:smooth_app/pages/product/product_page/widgets/product_page_title.dart';
import 'package:smooth_app/services/ownership_service.dart';

/// Shared rendering for an ownership chain + its source, used by both the
/// resolved "Owner" tab and the unknown-barcode fallback card so the two
/// never drift apart visually. See `projects/ejerskab-app/BRIEF.md`.
///
/// A plain `Wrap` of chips with arrow icons between them (the first version
/// of this UI) breaks on a long chain: once it wraps to a second line, an
/// arrow can land alone at the start of the line with nothing to point from.
/// A vertical trail has no such wrap boundary — it reads top (the scanned
/// brand) to bottom (the ultimate owner) at any chain length or screen width.
class OwnershipChainView extends StatelessWidget {
  const OwnershipChainView({required this.chain, this.highlightLast = true, super.key});

  final List<String> chain;

  /// The last link (the ultimate owner) is the one answer users came for —
  /// bold it so it doesn't read as just another step in the chain.
  final bool highlightLast;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < chain.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i < chain.length - 1 ? SMALL_SPACE : 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Column(
                  children: <Widget>[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == chain.length - 1 && highlightLast
                            ? colors.primary
                            : colors.outlineVariant,
                      ),
                    ),
                    if (i < chain.length - 1)
                      Container(
                        width: 2,
                        height: 20,
                        color: colors.outlineVariant,
                      ),
                  ],
                ),
                const SizedBox(width: MEDIUM_SPACE),
                Expanded(
                  child: Text(
                    chain[i],
                    style: i == chain.length - 1 && highlightLast
                        ? Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          )
                        : Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A small "where this came from" line, shown under a chain or rating so
/// users can judge how much to trust it at a glance.
class OwnershipSourceLine extends StatelessWidget {
  const OwnershipSourceLine({required this.source, super.key});

  final BrandOwnerSource source;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String label) = switch (source) {
      BrandOwnerSource.wikidata => (Icons.public, 'Source: Wikidata'),
      BrandOwnerSource.aiFallback => (
        Icons.auto_awesome,
        'Source: AI lookup, confirmed by a user',
      ),
      BrandOwnerSource.manualCurated => (Icons.edit_note, 'Source: checked by hand'),
      BrandOwnerSource.offlineDb => (Icons.storage, 'Source: Owned ownership database'),
      BrandOwnerSource.label => (Icons.receipt_long, 'Source: the company named on the label'),
      BrandOwnerSource.user => (Icons.person_rounded, 'Your correction'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: VERY_SMALL_SPACE),
        Flexible(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
      ],
    );
  }
}

/// Curated ethics note for the resolved owner, or an honest "nothing curated
/// yet" state — the tab must never imply a rating that doesn't exist.
class EthicsRatingSection extends StatelessWidget {
  const EthicsRatingSection({required this.ownerCompany, required this.ethics, super.key});

  final String ownerCompany;
  final EthicsRating? ethics;

  /// `ethics_rating.category` is free text, written by hand (see
  /// `schema/supabase.sql` — no fixed enum), so this is a best-effort colour
  /// hint from common words, not a strict mapping. Anything that doesn't
  /// match falls back to a neutral badge instead of guessing a colour.
  static ({Color background, Color foreground, String label})? _badgeFor(
    final String category,
  ) {
    final String c = category.toLowerCase();
    if (c.contains('boycot') || c.contains('undgå') || c.contains('avoid')) {
      return (
        background: RED_BACKGROUND_COLOR,
        foreground: DARK_RED_COLOR,
        label: category,
      );
    }
    if (c.contains('contest') || c.contains('omdiskuteret') || c.contains('obs')) {
      return (
        background: ORANGE_BACKGROUND_COLOR,
        foreground: DARK_ORANGE_COLOR,
        label: category,
      );
    }
    if (c.contains('ethic') || c.contains('etisk') || c.contains('ok') ||
        c.contains('good') || c.contains('fin')) {
      return (
        background: LIGHT_GREEN_BACKGROUND_COLOR,
        foreground: DARK_GREEN_COLOR,
        label: category,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final EthicsRating? rating = ethics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const ProductPageTitle(label: 'Moral score'),
        Padding(
          padding: const EdgeInsets.all(LARGE_SPACE),
          child: rating == null
              ? Text(
                  'No ethics rating yet for $ownerCompany.',
                  style: Theme.of(context).textTheme.bodyMedium,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _CategoryBadge(category: rating.category),
                    const SizedBox(height: SMALL_SPACE),
                    Text(rating.rationale, style: Theme.of(context).textTheme.bodyMedium),
                    if (rating.sourceUrl != null) ...<Widget>[
                      const SizedBox(height: SMALL_SPACE),
                      InkWell(
                        onTap: () => LaunchUrlHelper.launchURL(rating.sourceUrl!),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              Icons.open_in_new,
                              size: 14,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: VERY_SMALL_SPACE),
                            Text(
                              'Source',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final ({Color background, Color foreground, String label})? badge =
        EthicsRatingSection._badgeFor(category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: MEDIUM_SPACE, vertical: VERY_SMALL_SPACE),
      decoration: BoxDecoration(
        color: badge?.background ?? GREY_COLOR,
        borderRadius: ANGULAR_BORDER_RADIUS,
      ),
      child: Text(
        badge?.label ?? category,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: badge?.foreground ?? PRIMARY_GREY_COLOR,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Loading state with a short label — a bare spinner doesn't tell the user
/// which of the multi-step lookup chain (cache → Wikidata → AI) is running,
/// and that chain can take a few seconds end to end.
class OwnershipLoadingView extends StatelessWidget {
  const OwnershipLoadingView({this.label = 'Looking up the owner…', super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(LARGE_SPACE),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: MEDIUM_SPACE),
            Flexible(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          ],
        ),
      ),
    );
  }
}
