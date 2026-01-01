import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/pages/product/product_page/overview/score_donut.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/cal_ui.dart';
import 'package:smooth_app/widgets/company_logo.dart';

/// Building blocks of the result sheet (photo or barcode scan, history,
/// search), laid out as Cal AI's food result: a small tag and the product
/// as a two-line title, one wide card with the answer (Cal AI's "Calories
/// 330", here the owner), the two score cards, grey rows for the details,
/// and "Fix" + "Done" pinned under it.

/// Top of the sheet: a tag ("Nesquik · 1 kg"), the product as the title,
/// and the owner's card: logo in a grey tile, "Owned by", the owner big.
class OwnerResultHeader extends StatelessWidget {
  const OwnerResultHeader({
    required this.ownerName,
    required this.logoNames,
    required this.onTap,
    this.subtitle,
    this.loading = false,
    this.avoided = false,
    this.corrected = false,
    super.key,
  });

  /// Null while loading or when no owner was found.
  final String? ownerName;
  final List<String?> logoNames;

  /// What was scanned ("Nutella · 400 g"): the first part becomes the
  /// title, the rest the tag above it.
  final String? subtitle;
  final VoidCallback? onTap;
  final bool loading;
  final bool avoided;
  final bool corrected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final bool known = !loading && ownerName != null;
    final String label = loading
        ? 'Finding the owner'
        : !known
        ? 'Owner unknown'
        : corrected
        ? 'Owned by · your correction'
        : 'Owned by';
    final List<String> parts = (subtitle ?? '')
        .split(' · ')
        .map((String p) => p.trim())
        .where((String p) => p.isNotEmpty)
        .toList();
    final String? title = parts.isEmpty ? null : parts.first;
    final String? rest = parts.length < 2 ? null : parts.skip(1).join(' · ');
    final String? tag = rest == null ? null : rest[0].toUpperCase() + rest.substring(1);

    final Widget card = CalCard(
      radius: 20.0,
      padding: const EdgeInsetsDirectional.fromSTEB(12.0, 12.0, 14.0, 12.0),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Container(
            width: 64.0,
            height: 64.0,
            decoration: BoxDecoration(
              color: dark ? BrandColors.fillDark : BrandColors.fill,
              borderRadius: BorderRadius.circular(16.0),
            ),
            alignment: Alignment.center,
            child: loading
                ? const SizedBox.square(dimension: 22.0, child: CircularProgressIndicator(strokeWidth: 2.4))
                : CompanyLogo(names: known ? logoNames : const <String?>[], size: 64.0, radius: 16.0),
          ),
          const SizedBox(width: 14.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15.0, color: muted)),
                const SizedBox(height: 1.0),
                Text(
                  known
                      ? ownerName!
                      : loading
                      ? '…'
                      : 'Tap to help find it',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: known
                      ? theme.textTheme.displayMedium?.copyWith(
                          fontSize: 28.0,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                        )
                      : theme.textTheme.titleLarge,
                ),
              ],
            ),
          ),
          if (onTap != null) Icon(CupertinoIcons.chevron_right, size: 18.0, color: muted),
        ],
      ),
    );

    return Semantics(
      button: onTap != null,
      label: known ? '$label $ownerName' : label,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (tag != null) ...<Widget>[
            Row(
              children: <Widget>[
                Icon(CupertinoIcons.bookmark, size: 17.0, color: theme.colorScheme.onSurface),
                const SizedBox(width: 8.0),
                Flexible(
                  child: Container(
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: 10.0, vertical: 4.0),
                    decoration: BoxDecoration(
                      color: dark ? BrandColors.fillDark : BrandColors.fill,
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    child: Text(
                      tag,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(fontSize: 13.0, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12.0),
          ],
          if (title != null) ...<Widget>[
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontSize: 22.0,
                height: 1.18,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 16.0),
          ],
          card,
          if (known && avoided) ...<Widget>[
            const SizedBox(height: 10.0),
            DecoratedBox(
              decoration: BoxDecoration(
                color: dark ? BrandColors.fillDark : BrandColors.fill,
                borderRadius: BorderRadius.circular(20.0),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 12.0, vertical: 6.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(CupertinoIcons.nosign, size: 16.0, color: theme.colorScheme.onSurface),
                    const SizedBox(width: 6.0),
                    Text(
                      'You avoid this company',
                      style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Moral score" and "Health score" side by side.
class ScorePair extends StatelessWidget {
  const ScorePair({
    required this.moral,
    required this.health,
    required this.onMoralTap,
    required this.onHealthTap,
    this.moralLoading = false,
    this.moralVerdict,
    this.healthVerdict,
    super.key,
  });

  final int? moral;
  final int? health;
  final bool moralLoading;
  final String? moralVerdict;
  final String? healthVerdict;
  final VoidCallback? onMoralTap;
  final VoidCallback? onHealthTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: ScoreDonutCard(
            title: 'Moral score',
            score: moral,
            loading: moralLoading,
            verdict: moralVerdict,
            onTap: onMoralTap,
            icon: Icons.balance_rounded,
          ),
        ),
        const SizedBox(width: 10.0),
        Expanded(
          child: ScoreDonutCard(
            title: 'Health score',
            score: health,
            verdict: healthVerdict,
            onTap: onHealthTap,
            icon: CupertinoIcons.heart_fill,
          ),
        ),
      ],
    );
  }
}

/// One row of [MoreRows].
class MoreRow {
  const MoreRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.detail,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final VoidCallback onTap;
}

/// Every fact that is not the answer, one tap away, as Cal AI's ingredient
/// rows: separate light-grey rounded rows, the name in ink, the detail in
/// grey, a chevron.
class MoreRows extends StatelessWidget {
  const MoreRows({required this.rows, super.key});

  final List<MoreRow> rows;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    return Column(
      children: <Widget>[
        for (int i = 0; i < rows.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: 8.0),
          Semantics(
            button: true,
            label: rows[i].detail == null ? rows[i].title : '${rows[i].title}, ${rows[i].detail}',
            excludeSemantics: true,
            child: PressScale(
              scale: 0.98,
              onTap: rows[i].onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 58.0),
                padding: const EdgeInsetsDirectional.fromSTEB(14.0, 10.0, 12.0, 10.0),
                decoration: BoxDecoration(
                  color: dark ? BrandColors.fillDark : BrandColors.row,
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(color: dark ? BrandColors.hairlineDark : const Color(0xFFF1F0F6)),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(rows[i].icon, size: 20.0, color: theme.colorScheme.onSurface),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            rows[i].title,
                            style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16.0, fontWeight: FontWeight.w500),
                          ),
                          if (rows[i].detail != null)
                            Text(
                              rows[i].detail!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 13.0,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Icon(CupertinoIcons.chevron_right, size: 16.0, color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The page behind a score or a row: a large title on paper, the details
/// below. Used for "Moral score", "Health score", "Ownership"...
class DetailsPage extends StatelessWidget {
  const DetailsPage({required this.title, required this.child, super.key});

  final String title;
  final Widget child;

  static Future<void> open(
    final BuildContext context,
    final String title,
    final Widget child,
  ) => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => DetailsPage(title: title, child: child),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CalTopBar(title: title),
      body: CustomScrollView(
        slivers: <Widget>[
          const SliverToBoxAdapter(child: SizedBox(height: 8.0)),
          SliverToBoxAdapter(child: child),
          const SliverToBoxAdapter(child: SizedBox(height: 40.0)),
        ],
      ),
    );
  }
}

/// "Done" (and an optional secondary action) pinned under a result sheet,
/// as Cal AI's "✦ Fix Results" and "Done".
class SheetActions extends StatelessWidget {
  const SheetActions({this.secondary, this.onSecondary, super.key});

  final String? secondary;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        if (secondary != null) ...<Widget>[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onSecondary == null
                  ? null
                  : () {
                      Haptics.tap();
                      onSecondary!();
                    },
              icon: Icon(CupertinoIcons.sparkles, size: 18.0, color: theme.colorScheme.onSurface),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52.0)),
              label: Text(secondary!),
            ),
          ),
          const SizedBox(width: 12.0),
        ],
        Expanded(
          child: FilledButton(
            onPressed: () {
              Haptics.tap();
              Navigator.of(context).maybePop();
            },
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52.0)),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}
