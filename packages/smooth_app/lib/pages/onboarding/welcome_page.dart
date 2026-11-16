import 'package:flutter/cupertino.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/data_models/preferences/user_preferences.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/pages/onboarding/next_button.dart';
import 'package:smooth_app/pages/onboarding/onboarding_flow_navigator.dart';
import 'package:smooth_app/pages/preferences/country_selector/country.dart';
import 'package:smooth_app/query/product_query.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/cal_ui.dart';
import 'package:smooth_app/widgets/smooth_scaffold.dart';

/// "Where do you shop?" as a Cal AI onboarding question: big title, a search
/// field and one grey choice per country; the chosen one turns ink.
class WelcomePage extends StatefulWidget {
  const WelcomePage(this.backgroundColor);

  final Color backgroundColor;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final TextEditingController _search = TextEditingController();
  late final List<OpenFoodFactsCountry> _all = OpenFoodFactsCountry.values.toList()
    ..sort((OpenFoodFactsCountry a, OpenFoodFactsCountry b) => a.localizedName.compareTo(b.localizedName));

  /// The country shown first: the saved one, or the phone's own.
  OpenFoodFactsCountry? _first;
  OpenFoodFactsCountry? _current;

  @override
  void initState() {
    super.initState();
    try {
      _current = ProductQuery.getCountry();
    } catch (_) {
      // Nothing to suggest.
    }
    _first = _current;
    _search.addListener(() => setState(() {}));
    // The phone's country counts as chosen until the user picks another.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _current == null) {
        return;
      }
      if (context.read<UserPreferences>().userCountryCode == null) {
        _save(_current!);
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _save(final OpenFoodFactsCountry country) async {
    final UserPreferences preferences = context.read<UserPreferences>();
    await ProductQuery.setCountry(preferences, country.offTag);
    final String? currency = country.currency?.name;
    if (currency != null) {
      await preferences.setUserCurrencyCode(currency);
    }
  }

  void _choose(final OpenFoodFactsCountry country) {
    if (country == _current) {
      return;
    }
    Haptics.select();
    setState(() => _current = country);
    _save(country);
  }

  @override
  Widget build(BuildContext context) {
    final String q = _search.text.trim().toLowerCase();
    final List<OpenFoodFactsCountry> shown = <OpenFoodFactsCountry>[
      if (q.isEmpty && _first != null) _first!,
      for (final OpenFoodFactsCountry c in _all)
        if ((q.isEmpty && c != _first) || (q.isNotEmpty && c.localizedName.toLowerCase().contains(q))) c,
    ];

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
                  const Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(kCalSide, 16.0, kCalSide, 0.0),
                    child: FadeUpIn(
                      child: OnboardingTitle(
                        title: 'Where do you shop?',
                        subtitle: 'Store brands and products differ from country to country. '
                            'You can change this later in Profile.',
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(kCalSide, 24.0, kCalSide, 12.0),
                    child: FadeUpIn(
                      index: 1,
                      child: CalSearchField(controller: _search, hint: 'Search countries'),
                    ),
                  ),
                  Expanded(
                    child: FadeUpIn(
                      index: 2,
                      child: ListView.builder(
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsetsDirectional.fromSTEB(kCalSide, 0.0, kCalSide, 130.0),
                        itemCount: shown.length,
                        itemBuilder: (BuildContext context, int i) {
                          final OpenFoodFactsCountry c = shown[i];
                          final bool selected = c == _current;
                          return Padding(
                            padding: const EdgeInsetsDirectional.only(bottom: 8.0),
                            child: CalOption(
                              selected: selected,
                              onTap: () => _choose(c),
                              child: Row(
                                children: <Widget>[
                                  Expanded(child: Text(c.localizedName)),
                                  if (selected) const Icon(CupertinoIcons.checkmark_alt, size: 20.0),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
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
