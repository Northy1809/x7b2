import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openfoodfacts/openfoodfacts.dart';
import 'package:provider/provider.dart';
import 'package:smooth_app/data_models/preferences/user_preferences.dart';
import 'package:smooth_app/pages/preferences/country_selector/country.dart';
import 'package:smooth_app/query/product_query.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/cal_ui.dart';

/// The user's country, without a reference to Open Food Facts' selector:
/// a Cal AI page with a search field and grey choices; the chosen one is ink.
class CountryPickerPage extends StatefulWidget {
  const CountryPickerPage({super.key});

  static Future<void> open(final BuildContext context) =>
      Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => const CountryPickerPage()));

  /// The country's name in English, or null before one is chosen.
  static String? currentName() {
    try {
      return ProductQuery.getCountry().localizedName;
    } catch (_) {
      return null;
    }
  }

  @override
  State<CountryPickerPage> createState() => _CountryPickerPageState();
}

class _CountryPickerPageState extends State<CountryPickerPage> {
  final TextEditingController _search = TextEditingController();
  late final List<OpenFoodFactsCountry> _all = OpenFoodFactsCountry.values.toList()
    ..sort((OpenFoodFactsCountry a, OpenFoodFactsCountry b) => a.localizedName.compareTo(b.localizedName));
  OpenFoodFactsCountry? _current;

  @override
  void initState() {
    super.initState();
    try {
      _current = ProductQuery.getCountry();
    } catch (_) {
      // Not chosen yet.
    }
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _choose(final OpenFoodFactsCountry country) async {
    setState(() => _current = country);
    await ProductQuery.setCountry(context.read<UserPreferences>(), country.offTag);
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final String q = _search.text.trim().toLowerCase();
    final List<OpenFoodFactsCountry> shown = <OpenFoodFactsCountry>[
      if (q.isEmpty && _current != null) _current!,
      for (final OpenFoodFactsCountry c in _all)
        if ((q.isEmpty && c != _current) || (q.isNotEmpty && c.localizedName.toLowerCase().contains(q))) c,
    ];
    return Scaffold(
      appBar: const CalTopBar(title: 'Country'),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(kCalSide, 8.0, kCalSide, 6.0),
            child: Text(
              'Store brands, search results and search languages follow your country.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 15.0,
                height: 1.35,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(kCalSide, 8.0, kCalSide, 12.0),
            child: CalSearchField(controller: _search, hint: 'Search countries'),
          ),
          Expanded(
            child: ListView.builder(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsetsDirectional.fromSTEB(kCalSide, 0.0, kCalSide, MediaQuery.paddingOf(context).bottom + 24.0),
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
        ],
      ),
    );
  }
}
