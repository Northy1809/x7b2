import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:smooth_app/services/ownership_local_db.dart';
import 'package:smooth_app/services/ownership_norm.dart';

/// A line of text read off a photo, with its height (any unit: only the
/// ratio to the biggest line counts — the brand is usually the biggest).
class PackTextLine {
  const PackTextLine(this.text, this.height);

  final String text;
  final double height;
}

/// A brand found on the pack, with the owner the offline DB gives it.
class BrandCandidate {
  const BrandCandidate({
    required this.key,
    required this.name,
    required this.owner,
    required this.score,
  });

  /// [OwnershipNorm.normCore] of the brand.
  final String key;

  /// For display ("Nutella").
  final String name;
  final LocalOwnerResult owner;
  final double score;
}

/// Finds known brands in the text of a photographed pack: every run of 1-4
/// words of every line is looked up in the offline brand table (18 000+
/// brands); words that are just pack words ("lait", "pesto", "Nutri") are
/// skipped. Bigger text and a run that fills its line rank first.
///
/// Measured on Open Food Facts' OCR of the front photo of popular EU packs
/// (research/ocr/front_eval/match_eval.py is the Python twin; keep in step).
class BrandTextMatcher {
  BrandTextMatcher(this.db, this.packWords);

  final OwnershipLocalDb db;

  /// assets/ownership/pack_words.txt.
  final Set<String> packWords;

  static const String packWordsAsset = 'assets/ownership/pack_words.txt';
  static const int _maxWords = 4;

  static Future<Set<String>>? _packWords;

  static Future<Set<String>> loadPackWords() => _packWords ??= rootBundle
      .loadString(packWordsAsset)
      .then(parsePackWords);

  static Set<String> parsePackWords(final String text) => <String>{
    for (final String l in text.split('\n'))
      if (l.trim().isNotEmpty && !l.startsWith('#')) l.trim(),
  };

  /// Best first; one entry per brand and per owner.
  List<BrandCandidate> match(
    final List<PackTextLine> lines, {
    final List<String> countryTags = const <String>[],
    final int limit = 5,
  }) {
    if (lines.isEmpty) {
      return const <BrandCandidate>[];
    }
    final double hmax = lines.map((PackTextLine l) => l.height).fold(0.0, math.max);
    final Map<String, (double, String)> best = <String, (double, String)>{};
    for (final PackTextLine line in lines) {
      final List<String> tokens = OwnershipNorm.norm(line.text).split(' ').where((String t) => t.isNotEmpty).toList();
      if (tokens.isEmpty) {
        continue;
      }
      final int lineLength = tokens.join(' ').length;
      final double rel = hmax <= 0 ? 1.0 : line.height / hmax;
      for (int n = math.min(_maxWords, tokens.length); n >= 1; n--) {
        for (int i = 0; i + n <= tokens.length; i++) {
          final String gram = tokens.sublist(i, i + n).join(' ');
          final String key = OwnershipNorm.normCore(gram);
          if (OwnershipNorm.stopBrands.contains(key) ||
              packWords.contains(key) ||
              key.replaceAll(' ', '').length < 3 ||
              int.tryParse(key.replaceAll(' ', '')) != null ||
              !db.hasBrandKey(key)) {
            continue;
          }
          final double cover = gram.length / math.max(1, lineLength);
          final double score = rel * 2.0 + cover + math.min(n, 3) * 0.25 + math.min(key.length, 12) / 24.0;
          final (double, String)? old = best[key];
          if (old == null || score > old.$1) {
            best[key] = (score, gram);
          }
        }
      }
    }
    final List<MapEntry<String, (double, String)>> ranked = best.entries.toList()
      ..sort((MapEntry<String, (double, String)> a, MapEntry<String, (double, String)> b) => b.value.$1.compareTo(a.value.$1));
    final List<BrandCandidate> out = <BrandCandidate>[];
    final Set<String> owners = <String>{};
    for (final MapEntry<String, (double, String)> e in ranked) {
      final LocalOwnerResult? owner = db.lookup(barcode: '', brands: e.value.$2, countryTags: countryTags);
      if (owner == null || !owners.add(OwnershipNorm.normCore(owner.owner))) {
        continue;
      }
      out.add(BrandCandidate(key: e.key, name: _displayName(e.key, owner), owner: owner, score: e.value.$1));
      if (out.length >= limit) {
        break;
      }
    }
    return out;
  }

  /// The brand as the DB writes it when it has it ("Nutella"), else the
  /// words in title case.
  static String _displayName(final String key, final LocalOwnerResult owner) {
    for (final String n in owner.chain) {
      if (OwnershipNorm.normCore(n) == key) {
        return n;
      }
    }
    if (OwnershipNorm.normCore(owner.owner) == key) {
      return owner.owner;
    }
    return key
        .split(' ')
        .map((String w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}
