import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/data_models/preferences/user_preferences.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/pages/onboarding/next_button.dart';
import 'package:smooth_app/pages/onboarding/onboarding_flow_navigator.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/smooth_scaffold.dart';

/// Cal AI's "We're setting everything up for you" (16/11), for real: the
/// big percentage counts up while Owned loads its offline brand and company
/// data, the thin bar fills, and each line of the checklist ticks off. Then
/// the next page opens on its own. Loading here also makes the first scan
/// answer at once.
class OwnedSetupPage extends StatefulWidget {
  const OwnedSetupPage({this.load, this.autoAdvance = true, super.key});

  /// For tests and previews: what to wait for (brand count, rated count).
  final Future<(int, int?)> Function()? load;
  final bool autoAdvance;

  static const OnboardingPage page = OnboardingPage.ECO_CARD_EXAMPLE;

  /// When each checklist line ticks, as a share of the bar.
  static const List<double> ticks = <double>[0.22, 0.48, 0.74, 1.0];

  @override
  State<OwnedSetupPage> createState() => _OwnedSetupPageState();
}

class _OwnedSetupPageState extends State<OwnedSetupPage> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  int _ticked = 0;
  int? _brands;
  int? _rated;

  static Future<(int, int?)> _loadData() async {
    final OwnershipLocalDb db = await OwnershipLocalDb.load();
    int? rated;
    try {
      rated = (await EthicsDb.load()).companies.length;
    } catch (_) {
      // Owners still work without ratings.
    }
    return (db.brandCount, rated);
  }

  @override
  void initState() {
    super.initState();
    _c.addListener(_onTick);
    unawaited(_run());
  }

  void _onTick() {
    int n = 0;
    while (n < OwnedSetupPage.ticks.length && _c.value >= OwnedSetupPage.ticks[n] - 0.0001) {
      n++;
    }
    if (n != _ticked) {
      Haptics.select();
      setState(() => _ticked = n);
    }
  }

  Future<void> _run() async {
    final Future<(int, int?)> data = (widget.load ?? _loadData)().catchError((_) => (0, null));
    // The bar runs to 92 % at Cal AI's pace and waits there for the data.
    await _c.animateTo(0.92, duration: const Duration(milliseconds: 2600), curve: Curves.easeInOutCubic);
    final (int brands, int? rated) = await data;
    if (!mounted) {
      return;
    }
    setState(() {
      _brands = brands;
      _rated = rated;
    });
    await _c.animateTo(1.0, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    if (!mounted) {
      return;
    }
    Haptics.success();
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted || !widget.autoAdvance) {
      return;
    }
    await OnboardingFlowNavigator(
      context.read<UserPreferences>(),
    ).navigateToPage(context, OwnedSetupPage.page.getNextPage());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static String _thousands(final int n) =>
      n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (Match m) => '${m[1]} ');

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int brands = _brands ?? 0;
    final String brandLine = brands == 0 ? 'Brands and their owners' : '${_thousands(brands)} brands and their owners';
    final String ratedLine = _rated == null ? 'Company moral scores' : 'Moral scores for $_rated companies';
    final List<String> lines = <String>[brandLine, ratedLine, 'Store brands for your country', 'Health scores for food'];
    return SmoothBrightnessOverride(
      brightness: Brightness.light,
      child: ColoredBox(
      color: BrandColors.paper,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const OnboardingTopBar(OwnedSetupPage.page),
            const Spacer(flex: 2),
            AnimatedBuilder(
              animation: _c,
              builder: (BuildContext context, _) => Semantics(
                label: '${(_c.value * 100).round()} percent',
                liveRegion: true,
                excludeSemantics: true,
                child: Text(
                  '${(_c.value * 100).round()}%',
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontSize: 64.0,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.5,
                    color: BrandColors.ink,
                    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6.0),
            Text(
              "We're setting everything\nup for you",
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontSize: 24.0,
                height: 1.2,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
                color: BrandColors.ink,
              ),
            ),
            const SizedBox(height: 22.0),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 40.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4.0),
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (BuildContext context, _) => LinearProgressIndicator(
                    value: _c.value,
                    minHeight: 6.0,
                    color: BrandColors.ink,
                    backgroundColor: BrandColors.hairline,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10.0),
            Text(
              _ticked >= lines.length ? 'All set' : 'Loading what Owned knows…',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14.0, color: BrandColors.muted),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 24.0),
              child: CalCard(
                padding: const EdgeInsetsDirectional.fromSTEB(18.0, 16.0, 18.0, 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Ready on this phone, offline',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: 16.0,
                        fontWeight: FontWeight.w600,
                        color: BrandColors.ink,
                      ),
                    ),
                    const SizedBox(height: 8.0),
                    for (int i = 0; i < lines.length; i++)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(bottom: 10.0),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                '• ${lines[i]}',
                                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15.0, color: BrandColors.ink),
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: CalMotion.page,
                              transitionBuilder: (Widget child, Animation<double> a) =>
                                  ScaleTransition(scale: a, child: child),
                              child: i < _ticked
                                  ? const Icon(
                                      CupertinoIcons.checkmark_circle_fill,
                                      key: ValueKey<bool>(true),
                                      size: 20.0,
                                      color: BrandColors.ink,
                                    )
                                  : const Icon(
                                      CupertinoIcons.circle,
                                      key: ValueKey<bool>(false),
                                      size: 20.0,
                                      color: BrandColors.faint,
                                    ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
      ),
    );
  }
}
