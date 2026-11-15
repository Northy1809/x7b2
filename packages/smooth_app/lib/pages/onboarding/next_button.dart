import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/data_models/onboarding_loader.dart';
import 'package:smooth_app/data_models/preferences/user_preferences.dart';
import 'package:smooth_app/database/local_database.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/pages/onboarding/onboarding_flow_navigator.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';

/// Cal AI's onboarding footer: the page fades to white above one full-width
/// ink "Continue" pill. Going back is the round arrow at the top
/// ([OnboardingTopBar]).
class NextButton extends StatelessWidget {
  // we need a Key for the test/screenshots
  const NextButton(
    this.currentPage, {
    required this.backgroundColor,
    required this.nextKey,
    this.label = 'Continue',
  });

  final OnboardingPage currentPage;
  final Key nextKey;
  final String label;

  /// Color of the background where we put the button.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final UserPreferences userPreferences = context.watch<UserPreferences>();
    final LocalDatabase localDatabase = context.watch<LocalDatabase>();
    final OnboardingFlowNavigator navigator = OnboardingFlowNavigator(userPreferences);
    final Color back = backgroundColor ?? BrandColors.paper;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[back.withValues(alpha: 0.0), back],
          stops: const <double>[0.0, 0.35],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(24.0, 22.0, 24.0, 12.0),
          child: SizedBox(
            width: double.infinity,
            height: 56.0,
            child: FilledButton(
              key: nextKey,
              onPressed: () async {
                Haptics.tap();
                await OnboardingLoader(localDatabase).runAtNextTime(currentPage, context);
                if (context.mounted) {
                  await navigator.navigateToPage(context, currentPage.getNextPage());
                }
              },
              child: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cal AI's onboarding header: a round grey back arrow and a thin progress
/// bar that grows from page to page.
class OnboardingTopBar extends StatelessWidget {
  const OnboardingTopBar(this.currentPage, {super.key});

  final OnboardingPage currentPage;

  /// Owned's pages in order; the bar fills one step per page.
  static const List<OnboardingPage> _steps = <OnboardingPage>[
    OnboardingPage.HOME_PAGE,
    OnboardingPage.WELCOME,
    OnboardingPage.HEALTH_CARD_EXAMPLE,
    OnboardingPage.PERMISSIONS_PAGE,
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final OnboardingPage previous = currentPage.getPrevPage();
    final int step = _steps.indexOf(currentPage);
    final double to = step < 0 ? 1.0 : (step + 1) / _steps.length;
    final double from = step <= 0 ? 0.0 : step / _steps.length;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20.0, 8.0, 24.0, 8.0),
      child: Row(
        children: <Widget>[
          if (previous.isOnboardingNotStarted())
            const SizedBox.square(dimension: 40.0)
          else
            Semantics(
              button: true,
              label: MaterialLocalizations.of(context).backButtonTooltip,
              excludeSemantics: true,
              child: PressScale(
                onTap: () async {
                  final NavigatorState nav = Navigator.of(context);
                  if (nav.canPop()) {
                    await context.read<UserPreferences>().setLastVisitedOnboardingPage(previous);
                    nav.pop();
                  } else if (context.mounted) {
                    await OnboardingFlowNavigator(context.read<UserPreferences>()).navigateToPage(context, previous);
                  }
                },
                child: Container(
                  width: 40.0,
                  height: 40.0,
                  decoration: const BoxDecoration(color: BrandColors.fill, shape: BoxShape.circle),
                  child: Icon(
                    Directionality.of(context) == TextDirection.ltr ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded,
                    size: 22.0,
                    color: BrandColors.ink,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 16.0),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2.0),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: from, end: to),
                duration: CalMotion.reduced(context) ? Duration.zero : const Duration(milliseconds: 450),
                curve: CalMotion.curve,
                builder: (BuildContext context, double v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 4.0,
                  color: theme.colorScheme.primary,
                  backgroundColor: BrandColors.hairline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A Cal AI onboarding title: big, bold, left-aligned, with a grey line
/// under it.
class OnboardingTitle extends StatelessWidget {
  const OnboardingTitle({required this.title, this.subtitle, super.key});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.displayMedium?.copyWith(fontSize: 30.0, height: 1.18, color: BrandColors.ink),
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: 10.0),
          Text(subtitle!, style: theme.textTheme.bodyLarge?.copyWith(color: BrandColors.ink, fontSize: 16.0)),
        ],
      ],
    );
  }
}
