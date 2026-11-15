import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/data_models/preferences/user_preferences.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/generic_lib/widgets/owned_wordmark.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/pages/onboarding/next_button.dart';
import 'package:smooth_app/pages/onboarding/onboarding_flow_navigator.dart';
import 'package:smooth_app/pages/product/product_page/overview/owner_section.dart';
import 'package:smooth_app/pages/product/product_page/overview/score_donut.dart';
import 'package:smooth_app/services/score_types.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/smooth_scaffold.dart';

/// First onboarding page, laid out as Cal AI's: the picture fills the top,
/// the promise sits centred under it, one ink pill at the bottom.
class OwnedIntroPage extends StatelessWidget {
  const OwnedIntroPage({super.key});

  @override
  Widget build(BuildContext context) => SmoothBrightnessOverride(
    brightness: Brightness.light,
    child: SmoothScaffold(
      backgroundColor: BrandColors.paper,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 24.0),
          child: Column(
            children: <Widget>[
              const SizedBox(height: 12.0),
              const FadeUpIn(child: Center(child: OwnedWordmark(height: 26.0))),
              const Spacer(),
              const FadeUpIn(
                index: 1,
                child: CalCard(
                  padding: EdgeInsetsDirectional.all(LARGE_SPACE),
                  child: OwnerTrail(chain: <String>['KitKat', 'Nestlé']),
                ),
              ),
              const Spacer(),
              FadeUpIn(
                index: 2,
                child: Text(
                  'See who really owns what you buy',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontSize: 32.0,
                    height: 1.16,
                    color: BrandColors.ink,
                  ),
                ),
              ),
              const SizedBox(height: 12.0),
              FadeUpIn(
                index: 3,
                child: Text(
                  'Snap a product. Owned follows the brand up to the company at '
                  'the top, with a moral and a health score.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: BrandColors.muted),
                ),
              ),
              const SizedBox(height: 28.0),
              SizedBox(
                width: double.infinity,
                height: 56.0,
                child: FilledButton(
                  key: const Key('ownedGetStarted'),
                  onPressed: () {
                    Haptics.open();
                    OnboardingFlowNavigator(
                      context.read<UserPreferences>(),
                    ).navigateToPage(context, OnboardingPage.HOME_PAGE.getNextPage());
                  },
                  child: const Text('Get started'),
                ),
              ),
              const SizedBox(height: LARGE_SPACE),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The two scores every product gets.
class OwnedScoresIntroPage extends StatelessWidget {
  const OwnedScoresIntroPage(this.backgroundColor, {super.key});

  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: BrandColors.paper,
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                const OnboardingTopBar(OnboardingPage.HEALTH_CARD_EXAMPLE),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsetsDirectional.fromSTEB(24.0, 16.0, 24.0, 120.0),
                    children: const <Widget>[
                      FadeUpIn(
                        child: OnboardingTitle(
                          title: 'Two scores for every product',
                          subtitle: 'Both run from 0 to 100. The fuller the ring, the better.',
                        ),
                      ),
                      SizedBox(height: 36.0),
                      FadeUpIn(
                        index: 1,
                        child: _ScoreExample(
                          title: 'Moral score',
                          score: 30,
                          text: 'The owner’s record on climate, workers and honesty. Every case links to its source.',
                        ),
                      ),
                      SizedBox(height: 12.0),
                      FadeUpIn(
                        index: 2,
                        child: _ScoreExample(
                          title: 'Health score',
                          score: 72,
                          text: 'Nutri-Score, additives, how processed the food is, and organic. Food only.',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Positioned(
              left: 0.0,
              right: 0.0,
              bottom: 0.0,
              child: NextButton(
                OnboardingPage.HEALTH_CARD_EXAMPLE,
                backgroundColor: BrandColors.paper,
                nextKey: Key('nextAfterScores'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreExample extends StatelessWidget {
  const _ScoreExample({required this.title, required this.score, required this.text});

  final String title;
  final int score;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ScoreBand band = ScoreBand.of(score);
    return CalOption(
      padding: const EdgeInsetsDirectional.all(LARGE_SPACE),
      child: Row(
          children: <Widget>[
            ScoreDonut(score: score, size: 76.0),
            const SizedBox(width: LARGE_SPACE),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(color: BrandColors.ink),
                  ),
                  Text(
                    band.label,
                    style: theme.textTheme.bodySmall?.copyWith(color: BrandColors.ink),
                  ),
                  const SizedBox(height: 6.0),
                  Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: BrandColors.muted)),
                ],
              ),
            ),
          ],
        ),
    );
  }
}
