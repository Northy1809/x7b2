import 'package:flutter/material.dart';
import 'package:smooth_app/pages/scan/carousel/main_card/top_card/scan_search_card.dart';

class ScanMainCard extends StatelessWidget {
  const ScanMainCard();

  /// The Open Food Facts news feed (campaigns, in many languages) is left
  /// out: the scan screen only shows the Owned search card.
  @override
  Widget build(BuildContext context) =>
      const ScanSearchCard(expandedMode: true);
}
