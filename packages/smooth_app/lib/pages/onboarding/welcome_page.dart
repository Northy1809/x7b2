import 'package:flutter/material.dart';
import 'package:smooth_app/l10n/app_localizations.dart';
import 'package:smooth_app/pages/onboarding/next_button.dart';
import 'package:smooth_app/pages/onboarding/onboarding_flow_navigator.dart';
import 'package:smooth_app/pages/preferences/country_selector/country_selector.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/smooth_scaffold.dart';

/// Welcome page for first time users.
class WelcomePage extends StatelessWidget {
  const WelcomePage(this.backgroundColor);

  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations appLocalizations = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    return SmoothBrightnessOverride(
      brightness: Brightness.light,
      child: SmoothScaffold(
        backgroundColor: BrandColors.paper,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const OnboardingTopBar(OnboardingPage.WELCOME),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsetsDirectional.fromSTEB(24.0, 16.0, 24.0, 120.0),
                      children: <Widget>[
                        const FadeUpIn(
                          child: OnboardingTitle(
                            title: 'Where do you shop?',
                            subtitle: 'Store brands and products differ from country to country. '
                                'You can change this later in Profile.',
                          ),
                        ),
                        const SizedBox(height: 36.0),
                        FadeUpIn(
                          index: 1,
                          child: Container(
                            decoration: BoxDecoration(
                              color: BrandColors.fill,
                              borderRadius: BorderRadius.circular(16.0),
                            ),
                            child: Material(
                              type: MaterialType.transparency,
                              child: CountrySelector(
                                autoValidate: true,
                                forceCurrencyChange: true,
                                padding: const EdgeInsetsDirectional.fromSTEB(18.0, 18.0, 18.0, 18.0),
                                inkWellBorderRadius: BorderRadius.circular(16.0),
                                icon: const Icon(Icons.chevron_right_rounded, color: BrandColors.ink),
                                textStyle: theme.textTheme.titleMedium?.copyWith(color: BrandColors.ink),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14.0),
                        FadeUpIn(
                          index: 2,
                          child: Text(
                            appLocalizations.onboarding_country_chooser_label,
                            style: theme.textTheme.bodyMedium?.copyWith(color: BrandColors.muted),
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
                  OnboardingPage.WELCOME,
                  backgroundColor: BrandColors.paper,
                  nextKey: Key('nextAfterWelcome'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
