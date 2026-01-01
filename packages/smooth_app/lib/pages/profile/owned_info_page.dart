import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:smooth_app/generic_lib/design_constants.dart';
import 'package:smooth_app/helpers/launch_url_helper.dart';
import 'package:smooth_app/pages/product/product_page/overview/ethics_details.dart';
import 'package:smooth_app/pages/product/product_page/overview/overview_card.dart';
import 'package:smooth_app/services/ethics_db.dart';
import 'package:smooth_app/services/health_score.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/widgets/cal_ui.dart';

/// "How Owned works": what each answer in the app is based on.
enum OwnedInfoTopic {
  ownership('Who owns it', 'Where the owner comes from', CupertinoIcons.building_2_fill),
  health('Health score', 'How the 0-100 health score is made', CupertinoIcons.heart),
  ethics('Moral score', 'How companies are rated, and the sources', Icons.balance_rounded),
  data('Data and privacy', 'Sources, licences and what stays on your phone', CupertinoIcons.lock_shield);

  const OwnedInfoTopic(this.title, this.subtitle, this.icon);

  final String title;
  final String subtitle;
  final IconData icon;
}

class OwnedInfoPage extends StatelessWidget {
  const OwnedInfoPage(this.topic, {super.key});

  final OwnedInfoTopic topic;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: CalTopBar(title: topic.title),
    body: ListView(
      padding: const EdgeInsetsDirectional.symmetric(vertical: MEDIUM_SPACE),
      children: switch (topic) {
        OwnedInfoTopic.ownership => const <Widget>[
          _Block(
            title: 'The short version',
            paragraphs: <String>[
              'Owned reads the brand on the pack and follows it up to the company at the top: Nesquik → Nestlé, Président → Lactalis, a store brand → the supermarket chain.',
              'The trail on the product page shows every step. A listed company, a cooperative or a family-owned company is the top. When a person or family controls the top company, they are shown as "Controlled by".',
            ],
          ),
          _Block(
            title: 'Where the answer comes from',
            bullets: <String>[
              'Wikidata: which company owns which brand and company ("owned by", "parent organisation").',
              'Supermarket store-brand lists, checked one by one, each with a source.',
              'Researched brands that Wikidata lacks, kept only with a source.',
              'Barcode company prefixes learned from products with a known owner.',
              'The oval EU health mark on meat, dairy and fish, which names the plant.',
              'All of this is built into the app, so most answers come instantly and offline.',
            ],
          ),
          _Block(
            title: 'When the app does not know',
            paragraphs: <String>[
              'It asks Wikidata online for the brand. If that fails too, you can type the brand or take a photo of the back of the pack: EU law says the company responsible for the food must be named on it.',
              'Ownership changes and data can be old or wrong. Tap "Not right?" on any product to name the right owner: Owned then shows your correction on every screen. You find your corrections on the Profile tab.',
            ],
          ),
          _DataDate(),
        ],
        OwnedInfoTopic.health => const <Widget>[
          _Block(
            title: 'What goes into it',
            bullets: <String>[
              'Nutri-Score, the EU front-of-pack nutrition grade: ${HealthScore.nutritionMax} points.',
              'Additives with a risk of overexposure according to EFSA: ${HealthScore.additivesMax} points.',
              'How processed the food is (NOVA group): ${HealthScore.processingMax} points.',
              'Organic (EU organic logo): ${HealthScore.organicMax} points.',
            ],
          ),
          _Block(
            title: 'How to read it',
            paragraphs: <String>[
              'Parts without data are left out and the rest is scaled to 0-100. Without a Nutri-Score there is no health score, because nutrition is most of it.',
              '75-100 is excellent, 50-74 good, 25-49 fair and below 25 poor. Only food gets a health score: cosmetics, books or electronics do not.',
              'The score is a guide, not medical advice.',
            ],
          ),
        ],
        OwnedInfoTopic.ethics => const <Widget>[
          _Block(
            title: 'Three things are rated',
            bullets: <String>[
              'Climate & environment: emissions, deforestation, plastic and water.',
              'People & workers: child labour, forced labour, conditions for workers and farmers.',
              'Honesty & responsibility: unethical marketing, misleading claims, food safety, animal welfare and corruption.',
            ],
          ),
          _Block(
            title: 'How the score is counted',
            paragraphs: <String>[
              'Every company starts at ${EthicsScore.baseline} in each area. A documented case lowers it by 15, 30 or 45 points depending on how serious it is. Cases from the last ten years count fully, older ones less. Proven good practice adds ${EthicsScore.goodBonus}. The ethics score is the average of the three areas.',
              'Every case in the app links to its source. Nothing is rated without one.',
            ],
          ),
          _Block(
            title: 'Benchmarks used for every company',
            bullets: <String>[
              'Chocolate Scorecard 2026 (child labour, deforestation in cocoa).',
              'KnowTheChain 2023 food & beverage benchmark (forced labour).',
              'Branded plastic pollution study, Science Advances 2024.',
              'Science Based Targets initiative (climate targets).',
              "Oxfam's supermarket checks (Germany 2022, Italy 2020).",
              'Decisions of competition authorities (cartel fines) and food safety agencies.',
            ],
            links: <(String, String)>[
              ('Chocolate Scorecard', 'https://www.chocolatescorecard.com/'),
              ('KnowTheChain', 'https://knowthechain.org/'),
              ('Science Based Targets', 'https://sciencebasedtargets.org/'),
            ],
          ),
          _Block(
            title: 'Limits',
            paragraphs: <String>[
              'Big companies are researched better than small ones, so a small company with no cases is "not rated" rather than good. Companies with only a climate target have not been checked for cases yet.',
            ],
          ),
        ],
        OwnedInfoTopic.data => const <Widget>[
          _Block(
            title: 'Your data stays on your phone',
            paragraphs: <String>[
              'Your scans, history, corrections and the companies you avoid are stored only on this phone. Owned sends no usage analytics and no crash reports.',
              'To show a product, the app asks Open Food Facts for the barcode. Unknown barcodes may be looked up at UPCitemdb or Open Library, and unknown brands at Wikidata.',
            ],
          ),
          _Block(
            title: 'Open data Owned is built on',
            bullets: <String>[
              'Product data: Open Food Facts, Open Beauty Facts, Open Pet Food Facts and Open Products Facts, under the Open Database Licence (ODbL).',
              'Ownership: Wikidata (CC0) plus researched sources.',
              'Books: Open Library. Other products: UPCitemdb.',
              'The app itself is a fork of the Open Food Facts app (Apache 2.0).',
            ],
            links: <(String, String)>[
              ('Open Food Facts', 'https://world.openfoodfacts.org/'),
              ('Wikidata', 'https://www.wikidata.org/'),
              ('Source code', 'https://github.com/openfoodfacts/smooth-app'),
            ],
          ),
        ],
      },
    ),
  );
}

class _Block extends StatelessWidget {
  const _Block({
    required this.title,
    this.paragraphs = const <String>[],
    this.bullets = const <String>[],
    this.links = const <(String, String)>[],
  });

  final String title;
  final List<String> paragraphs;
  final List<String> bullets;
  final List<(String, String)> links;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? body = theme.textTheme.bodyMedium?.copyWith(height: 1.45);
    return OverviewCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(fontSize: 17.0, fontWeight: FontWeight.w600, letterSpacing: -0.4),
          ),
          for (final String p in paragraphs)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: SMALL_SPACE),
              child: Text(p, style: body),
            ),
          for (final String b in bullets)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: SMALL_SPACE),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 7.0,
                    height: 7.0,
                    margin: const EdgeInsetsDirectional.only(top: 7.0, end: 10.0),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.onSurface),
                  ),
                  Expanded(child: Text(b, style: body)),
                ],
              ),
            ),
          if (links.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: SMALL_SPACE),
              child: Wrap(
                spacing: SMALL_SPACE,
                runSpacing: SMALL_SPACE,
                children: <Widget>[
                  for (final (String label, String url) in links)
                    CalPill(
                      icon: CupertinoIcons.arrow_up_right,
                      label: label,
                      onTap: () => LaunchUrlHelper.launchURL(url),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "Ownership data built 9 Nov 2026": how old the offline answers are.
class _DataDate extends StatelessWidget {
  const _DataDate();

  @override
  Widget build(BuildContext context) => FutureBuilder<OwnershipLocalDb>(
    future: OwnershipLocalDb.load(),
    builder: (BuildContext context, AsyncSnapshot<OwnershipLocalDb> snapshot) {
      final String? built = snapshot.data?.built;
      if (built == null) {
        return const SizedBox.shrink();
      }
      final ThemeData theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsetsDirectional.symmetric(horizontal: VERY_LARGE_SPACE, vertical: MEDIUM_SPACE),
        child: Text(
          'Ownership data built ${formatShortDate(built)}.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    },
  );
}
