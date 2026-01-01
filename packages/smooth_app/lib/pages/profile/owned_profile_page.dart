import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/data_models/preferences/user_preferences.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/helpers/launch_url_helper.dart';
import 'package:smooth_app/pages/product/product_page/overview/owner_section.dart';
import 'package:smooth_app/pages/profile/country_picker_page.dart';
import 'package:smooth_app/pages/profile/owned_info_page.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/owner_overrides.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/themes/theme_provider.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/cal_ui.dart';

/// The Profile tab as Cal AI's (16/11): a big title, what Owned knows,
/// your corrections, and white cards of rows for preferences, how the app
/// works and about. Open Food Facts' account, contribute and settings pages
/// are no longer reachable from here.
class OwnedProfilePage extends StatefulWidget {
  const OwnedProfilePage({this.localDb, this.ethicsDb, this.version, super.key});

  /// For tests: the bundled databases.
  final Future<OwnershipLocalDb> Function()? localDb;
  final Future<EthicsDb> Function()? ethicsDb;

  /// For tests: the app version.
  final String? version;

  @override
  State<OwnedProfilePage> createState() => _OwnedProfilePageState();
}

class _OwnedProfilePageState extends State<OwnedProfilePage> {
  late final Future<_DataStats> _stats = _load();
  String? _version;

  @override
  void initState() {
    super.initState();
    _version = widget.version;
    if (_version == null) {
      unawaited(
        PackageInfo.fromPlatform().then((PackageInfo p) {
          if (mounted) {
            setState(() => _version = p.version);
          }
        }, onError: (_) {}),
      );
    }
  }

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
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    return Scaffold(
      body: FutureBuilder<_DataStats>(
        future: _stats,
        builder: (BuildContext context, AsyncSnapshot<_DataStats> snapshot) {
          return ListView(
            padding: EdgeInsetsDirectional.fromSTEB(kCalSide, pad.top + 14.0, kCalSide, pad.bottom + 120.0),
            children: <Widget>[
              const FadeUpIn(child: CalLargeTitle('Profile')),
              const SizedBox(height: 16.0),
              FadeUpIn(index: 1, child: _KnowsCard(stats: snapshot.data)),
              const FadeUpIn(index: 2, child: _CorrectionsGroup()),
              const SizedBox(height: 24.0),
              const FadeUpIn(index: 3, child: _PreferencesGroup()),
              const SizedBox(height: 24.0),
              FadeUpIn(
                index: 4,
                child: CalGroup(
                  title: 'How Owned works',
                  children: <Widget>[
                    for (final OwnedInfoTopic t in OwnedInfoTopic.values)
                      CalNavRow(
                        icon: t.icon,
                        title: t.title,
                        onTap: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(builder: (_) => OwnedInfoPage(t)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24.0),
              FadeUpIn(
                index: 5,
                child: CalGroup(
                  title: 'About',
                  children: <Widget>[
                    CalNavRow(icon: CupertinoIcons.info, title: 'Version', value: _version ?? '–'),
                    CalNavRow(
                      icon: CupertinoIcons.globe,
                      title: 'Open Food Facts',
                      subtitle: 'Where the product facts come from',
                      onTap: () => unawaited(LaunchUrlHelper.launchURL('https://world.openfoodfacts.org')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24.0),
              Text(
                'Product data from Open Food Facts and its sister projects (ODbL). '
                'Ownership from Wikidata (CC0) and researched sources.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12.0,
                  height: 1.4,
                  color: theme.colorScheme.onSurfaceVariant,
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

class _KnowsCard extends StatelessWidget {
  const _KnowsCard({required this.stats});

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
    return CalCard(
      padding: const EdgeInsetsDirectional.fromSTEB(18.0, 16.0, 18.0, 18.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'What Owned knows',
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14.0, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12.0),
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
                  letterSpacing: -0.5,
                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 2.0),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 13.0, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Owners the user corrected, shown only when there are some.
class _CorrectionsGroup extends StatelessWidget {
  const _CorrectionsGroup();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: OwnerOverrides.instance,
    builder: (BuildContext context, _) {
      final List<OwnerCorrection> all = OwnerOverrides.instance.all;
      if (all.isEmpty) {
        return const SizedBox.shrink();
      }
      final ThemeData theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsetsDirectional.only(top: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CalGroup(
              title: 'Your corrections',
              children: <Widget>[for (final OwnerCorrection c in all) _CorrectionRow(correction: c)],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(4.0, 8.0, 4.0, 0.0),
              child: Text(
                'Owners you named yourself. They stay on this phone and win over our data.',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 13.0,
                  height: 1.35,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _CorrectionRow extends StatelessWidget {
  const _CorrectionRow({required this.correction});

  final OwnerCorrection correction;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final OwnerCorrection c = correction;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(14.0, 10.0, 4.0, 10.0),
      child: Row(
        children: <Widget>[
          OwnerAvatar(name: c.owner, size: 32.0),
          const SizedBox(width: 12.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  c.owner,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16.0, fontWeight: FontWeight.w600),
                ),
                Text(
                  c.isBarcode ? 'Barcode ${c.label}' : c.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 13.0, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: 'Remove correction',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Haptics.remove();
                unawaited(OwnerOverrides.instance.removeCorrection(c));
                final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
                messenger.hideCurrentSnackBar();
                messenger.showSnackBar(
                  SnackBar(
                    content: const Text('Correction removed'),
                    behavior: SnackBarBehavior.floating,
                    action: SnackBarAction(
                      label: 'Undo',
                      onPressed: () => unawaited(OwnerOverrides.instance.restore(c)),
                    ),
                  ),
                );
              },
              child: SizedBox(
                width: 44.0,
                height: 44.0,
                child: Icon(CupertinoIcons.xmark, size: 16.0, color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferencesGroup extends StatelessWidget {
  const _PreferencesGroup();

  static const List<(String, String)> _themes = <(String, String)>[
    (THEME_SYSTEM_DEFAULT, 'System'),
    (THEME_LIGHT, 'Light'),
    (THEME_DARK, 'Dark'),
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeProvider themeProvider = context.watch<ThemeProvider>();
    final UserPreferences prefs = context.watch<UserPreferences>();
    final String theme = themeProvider.currentTheme == THEME_AMOLED ? THEME_DARK : themeProvider.currentTheme;
    final String themeLabel = _themes
        .firstWhere(((String, String) t) => t.$1 == theme, orElse: () => _themes.first)
        .$2;
    return CalGroup(
      title: 'Preferences',
      children: <Widget>[
        CalNavRow(
          icon: CupertinoIcons.location,
          title: 'Country',
          value: CountryPickerPage.currentName() ?? 'Choose',
          onTap: () => CountryPickerPage.open(context),
        ),
        CalNavRow(
          icon: CupertinoIcons.circle_lefthalf_fill,
          title: 'Appearance',
          value: themeLabel,
          onTap: () async {
            final String? chosen = await showCalChoices<String>(
              context: context,
              title: 'Appearance',
              choices: _themes,
              selected: theme,
            );
            if (chosen != null) {
              await themeProvider.setTheme(chosen);
            }
          },
        ),
        CalSwitchRow(
          icon: CupertinoIcons.waveform,
          title: 'Haptics',
          subtitle: 'Small vibrations when you tap, scan and get an answer',
          value: prefs.hapticFeedbackEnabled,
          onChanged: (bool on) async {
            await context.read<UserPreferences>().setHapticFeedbackEnabled(on);
            if (on) {
              Haptics.select();
            }
          },
        ),
      ],
    );
  }
}
