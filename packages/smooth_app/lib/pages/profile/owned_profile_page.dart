import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/data_models/preferences/user_preferences.dart';
import 'package:smooth_app/data_models/user_management_provider.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/l10n/app_localizations.dart';
import 'package:smooth_app/pages/preferences_v2/roots/about_app_root.dart';
import 'package:smooth_app/pages/preferences_v2/roots/account_root.dart';
import 'package:smooth_app/pages/preferences_v2/roots/app_settings_root.dart';
import 'package:smooth_app/pages/preferences_v2/roots/contribute_root.dart';
import 'package:smooth_app/pages/preferences_v2/roots/legal_information_root.dart';
import 'package:smooth_app/pages/preferences_v2/roots/preferences_root.dart';
import 'package:smooth_app/pages/preferences_v2/tiles/app_settings_tiles/country_selector/country_selector_tile.dart';
import 'package:smooth_app/pages/product/product_page/overview/overview_card.dart';
import 'package:smooth_app/pages/product/product_page/overview/owner_section.dart';
import 'package:smooth_app/pages/profile/owned_info_page.dart';
import 'package:smooth_app/pages/user_management/login_page.dart';
import 'package:smooth_app/query/product_query.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/owner_overrides.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/themes/theme_provider.dart';

/// The Profile tab: what the app knows, your corrections, settings, how
/// Owned works, and (last) the Open Food Facts account for contributing data.
/// Who you buy from and the avoid list moved to the Companies tab (15/11).
class OwnedProfilePage extends StatefulWidget {
  const OwnedProfilePage({this.localDb, this.ethicsDb, super.key});

  /// For tests: the bundled databases.
  final Future<OwnershipLocalDb> Function()? localDb;
  final Future<EthicsDb> Function()? ethicsDb;

  @override
  State<OwnedProfilePage> createState() => _OwnedProfilePageState();
}

class _OwnedProfilePageState extends State<OwnedProfilePage> {
  late final Future<_DataStats> _stats = _load();

  Future<_DataStats> _load() async {
    final OwnershipLocalDb db = await (widget.localDb ?? OwnershipLocalDb.load)();
    EthicsDb? ethics;
    try {
      ethics = await (widget.ethicsDb ?? EthicsDb.load)();
    } catch (_) {
      // Brands still count without the ratings.
    }
    return _DataStats(brands: db.brandCount, rated: ethics?.companies.length, updated: db.built ?? ethics?.updated);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      body: FutureBuilder<_DataStats>(
        future: _stats,
        builder: (BuildContext context, AsyncSnapshot<_DataStats> snapshot) {
          return CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(child: _Header(stats: snapshot.data)),
              const SliverToBoxAdapter(child: _CorrectionsCard()),
              const SliverToBoxAdapter(child: _SettingsCard()),
              const SliverToBoxAdapter(child: _HowItWorksCard()),
              const SliverToBoxAdapter(child: _ImproveDataCard()),
              const SliverToBoxAdapter(child: _AboutCard()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    VERY_LARGE_SPACE,
                    MEDIUM_SPACE,
                    VERY_LARGE_SPACE,
                    VERY_LARGE_SPACE * 2,
                  ),
                  child: Text(
                    'Product data from Open Food Facts and its sister projects (ODbL). '
                    'Ownership from Wikidata (CC0) and researched sources.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// What the app knows, for trust: how many brands have a known owner,
/// how many companies are rated with sources, and how fresh the data is.
class _DataStats {
  const _DataStats({required this.brands, required this.rated, required this.updated});

  final int brands;
  final int? rated;

  /// ISO date.
  final String? updated;
}

class _Header extends StatelessWidget {
  const _Header({required this.stats});

  final _DataStats? stats;

  static String _thousands(final int n) =>
      n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (Match m) => '${m[1]} ');

  static String? _date(final String? iso) {
    final DateTime? d = iso == null ? null : DateTime.tryParse(iso);
    if (d == null) {
      return null;
    }
    const List<String> m = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final _DataStats? st = stats;
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(LARGE_SPACE, LARGE_SPACE, LARGE_SPACE, SMALL_SPACE),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Profile', style: theme.textTheme.displayLarge),
            const SizedBox(height: 16.0),
            Card(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(18.0, 16.0, 18.0, 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'What Owned knows',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10.0),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _Stat(text: st == null ? null : _thousands(st.brands), label: 'Brands known'),
                        _Stat(text: st?.rated?.toString(), label: 'Rated firms'),
                        _Stat(text: _date(st?.updated), label: 'Data updated'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.text, required this.label});

  final String? text;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsetsDirectional.only(end: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                text ?? '–',
                style: theme.textTheme.displayMedium?.copyWith(
                  fontSize: 24.0,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 2.0),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// A short message with an Undo button, replacing any earlier one.
void _showUndo(final BuildContext context, final String message, final Future<void> Function() undo) {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(label: 'Undo', onPressed: () => unawaited(undo())),
    ),
  );
}

/// Owners the user corrected, shown only when there are some.
class _CorrectionsCard extends StatelessWidget {
  const _CorrectionsCard();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListenableBuilder(
      listenable: OwnerOverrides.instance,
      builder: (BuildContext context, _) {
        final List<OwnerCorrection> all = OwnerOverrides.instance.all;
        if (all.isEmpty) {
          return const SizedBox.shrink();
        }
        return OverviewCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SectionLabel('Your corrections'),
              const SizedBox(height: SMALL_SPACE),
              Text(
                'Owners you named yourself. They are kept on this phone and win over our data.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
              ),
              for (final OwnerCorrection c in all)
                ListTile(
                  contentPadding: EdgeInsetsDirectional.zero,
                  leading: OwnerAvatar(name: c.owner, size: 36.0),
                  title: Text(c.owner, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(c.isBarcode ? 'Barcode ${c.label}' : c.label),
                  trailing: IconButton(
                    tooltip: 'Remove correction',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      unawaited(OwnerOverrides.instance.removeCorrection(c));
                      _showUndo(context, 'Correction removed', () => OwnerOverrides.instance.restore(c));
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations appLocalizations = AppLocalizations.of(context);
    final ThemeProvider themeProvider = context.watch<ThemeProvider>();
    final String theme = themeProvider.currentTheme == THEME_AMOLED ? THEME_DARK : themeProvider.currentTheme;
    return OverviewCard(
      padding: const EdgeInsetsDirectional.symmetric(vertical: MEDIUM_SPACE),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsetsDirectional.symmetric(horizontal: LARGE_SPACE),
            child: SectionLabel('Settings'),
          ),
          CountrySelectorTile(
            title: appLocalizations.country_picker_label,
            forceCurrencyChange: false,
            autoValidate: false,
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(LARGE_SPACE, SMALL_SPACE, LARGE_SPACE, 0),
            child: Text(
              'Store brands, search results and search languages follow your country.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(LARGE_SPACE, MEDIUM_SPACE, LARGE_SPACE, SMALL_SPACE),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(
                    value: THEME_SYSTEM_DEFAULT,
                    label: Text('Auto'),
                    icon: Icon(Icons.brightness_auto_rounded),
                  ),
                  ButtonSegment<String>(value: THEME_LIGHT, label: Text('Light'), icon: Icon(Icons.light_mode_rounded)),
                  ButtonSegment<String>(value: THEME_DARK, label: Text('Dark'), icon: Icon(Icons.dark_mode_rounded)),
                ],
                selected: <String>{theme},
                showSelectedIcon: false,
                onSelectionChanged: (Set<String> v) => themeProvider.setTheme(v.first),
              ),
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: LARGE_SPACE),
            secondary: const Icon(CupertinoIcons.waveform),
            title: const Text('Haptics'),
            subtitle: const Text('Small vibrations when you tap, scan and get an answer'),
            value: context.watch<UserPreferences>().hapticFeedbackEnabled,
            onChanged: (bool on) async {
              await context.read<UserPreferences>().setHapticFeedbackEnabled(on);
              if (on) {
                Haptics.select();
              }
            },
          ),
          _NavRow(
            icon: Icons.tune_rounded,
            title: 'More settings',
            subtitle: 'Camera, photos, product page',
            onTap: () => _pushRoot(context, AppSettingsRoot(title: appLocalizations.myPreferences_settings_title)),
          ),
        ],
      ),
    );
  }
}

class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard();

  @override
  Widget build(BuildContext context) => OverviewCard(
    padding: const EdgeInsetsDirectional.symmetric(vertical: MEDIUM_SPACE),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsetsDirectional.symmetric(horizontal: LARGE_SPACE),
          child: SectionLabel('How Owned works'),
        ),
        for (final OwnedInfoTopic t in OwnedInfoTopic.values)
          _NavRow(
            icon: t.icon,
            title: t.title,
            subtitle: t.subtitle,
            onTap: () => Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => OwnedInfoPage(t))),
          ),
      ],
    ),
  );
}

class _ImproveDataCard extends StatelessWidget {
  const _ImproveDataCard();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations appLocalizations = AppLocalizations.of(context);
    context.watch<UserManagementProvider>();
    final String? userId = ProductQuery.isLoggedIn() ? OpenFoodAPIConfiguration.globalUser?.userId : null;
    return OverviewCard(
      padding: const EdgeInsetsDirectional.symmetric(vertical: MEDIUM_SPACE),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsetsDirectional.symmetric(horizontal: LARGE_SPACE),
            child: SectionLabel('Improve the data'),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(LARGE_SPACE, SMALL_SPACE, LARGE_SPACE, 0),
            child: Text(
              'Product facts come from Open Food Facts, a free database anyone can edit. '
              'With an account you can add missing products and photos.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4),
            ),
          ),
          _NavRow(
            icon: Icons.account_circle_rounded,
            title: userId == null ? 'Sign in to Open Food Facts' : 'Open Food Facts account',
            subtitle: userId ?? 'Needed to add or edit products',
            onTap: () => userId == null
                ? Navigator.of(
                    context,
                    rootNavigator: true,
                  ).push<void>(MaterialPageRoute<void>(builder: (_) => const LoginPage()))
                : _pushRoot(context, AccountRoot(title: appLocalizations.preferences_account_title)),
          ),
          _NavRow(
            icon: Icons.volunteer_activism_rounded,
            title: 'Contribute',
            subtitle: 'Simple ways to help the open database',
            onTap: () => _pushRoot(context, ContributeRoot(title: appLocalizations.preferences_contribute_title)),
          ),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations appLocalizations = AppLocalizations.of(context);
    return OverviewCard(
      padding: const EdgeInsetsDirectional.symmetric(vertical: MEDIUM_SPACE),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsetsDirectional.symmetric(horizontal: LARGE_SPACE),
            child: SectionLabel('About'),
          ),
          _NavRow(
            icon: Icons.info_outline_rounded,
            title: 'About this app',
            subtitle: 'Version and source code',
            onTap: () => _pushRoot(context, AboutAppRoot(title: appLocalizations.preferences_about_app_title)),
          ),
          _NavRow(
            icon: Icons.gavel_rounded,
            title: appLocalizations.preferences_legal_information_title,
            subtitle: 'Open Food Facts terms, privacy and licences',
            onTap: () =>
                _pushRoot(context, LegalInformationRoot(title: appLocalizations.preferences_legal_information_title)),
          ),
        ],
      ),
    );
  }
}

void _pushRoot(final BuildContext context, final PreferencesRoot root) => unawaited(
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider<PreferencesRootSearchController>(
        create: (_) => PreferencesRootSearchController(),
        child: root,
      ),
    ),
  ),
);

class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: LARGE_SPACE),
      leading: Container(
        width: 40.0,
        height: 40.0,
        decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12.0)),
        child: Icon(icon, color: theme.colorScheme.onPrimaryContainer, size: 22.0),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
