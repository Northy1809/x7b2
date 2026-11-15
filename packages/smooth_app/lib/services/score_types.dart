import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared 0-100 bands for the health and ethics scores, so both read the
/// same way. As in Cal AI, a score is a black ring on a grey track: the
/// band shows in the word and the ring's length, never in a hue.
enum ScoreBand {
  excellent('Excellent', Color(0xFF1E1A22)),
  good('Good', Color(0xFF1E1A22)),
  mediocre('Fair', Color(0xFF1E1A22)),
  bad('Poor', Color(0xFF1E1A22));

  const ScoreBand(this.label, this.color);

  final String label;
  final Color color;

  static ScoreBand of(final int score) {
    if (score >= 75) {
      return ScoreBand.excellent;
    }
    if (score >= 50) {
      return ScoreBand.good;
    }
    if (score >= 25) {
      return ScoreBand.mediocre;
    }
    return ScoreBand.bad;
  }
}

/// [color] made darker (on light backgrounds) or lighter (on dark ones)
/// until text in it reaches WCAG AA contrast (4.5:1) against [background].
/// Score colours keep their hue, so they still mean the same thing.
Color readableOn(final Color color, final Color background, {final double minContrast = 4.5}) {
  double contrast(final Color a) {
    final double la = a.computeLuminance();
    final double lb = background.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  if (contrast(color) >= minContrast) {
    return color;
  }
  final bool darken = background.computeLuminance() > 0.4;
  HSLColor hsl = HSLColor.fromColor(color);
  for (int i = 0; i < 20 && contrast(hsl.toColor()) < minContrast; i++) {
    hsl = hsl.withLightness((hsl.lightness + (darken ? -0.03 : 0.03)).clamp(0.0, 1.0));
  }
  return hsl.toColor();
}

/// A score colour for text on the current card background.
Color scoreTextColor(final BuildContext context, final int score) =>
    readableOn(ScoreBand.of(score).color, Theme.of(context).colorScheme.surface);

/// A link to the evidence behind a statement in the app.
class SourceLink {
  const SourceLink({required this.title, required this.url});

  factory SourceLink.fromJson(final Map<String, dynamic> json) => SourceLink(
    title: json['title'] as String? ?? json['url'] as String,
    url: json['url'] as String,
  );

  final String title;
  final String url;

  /// "efsa.europa.eu" from the URL, to show where a link goes.
  String get host {
    final String h = Uri.tryParse(url)?.host ?? url;
    return h.startsWith('www.') ? h.substring(4) : h;
  }
}

enum FactorTone { positive, neutral, negative }

/// One line in a score explanation, e.g. "Nutri-Score D: 15/60 points".
class ScoreFactor {
  const ScoreFactor({
    required this.title,
    required this.tone,
    this.detail,
    this.points,
    this.maxPoints,
    this.sources = const <SourceLink>[],
  });

  final String title;
  final String? detail;
  final FactorTone tone;

  /// Points earned, when this factor is part of the score sum.
  final int? points;
  final int? maxPoints;
  final List<SourceLink> sources;
}
