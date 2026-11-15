/// Finds the responsible food business operator printed on a label.
///
/// EU Regulation 1169/2011 art. 9(1)(h) + art. 8(1) make the name and address
/// of the operator under whose name the food is marketed mandatory on every
/// prepacked food. Port of research/prefix/label_parser.py; returns candidates
/// ranked so "made for X" (the marketer) comes before "made by Y" (a co-packer).
class LabelOperatorParser {
  const LabelOperatorParser._();

  static const String _l = r'\p{L}';

  static RegExp _phrases(final String body) => RegExp(
        '(?<![$_l])($body)(?![$_l])\\s*:?\\s*',
        caseSensitive: false,
        unicode: true,
      );

  static final RegExp _for = _phrases(
    'fabriqu[ée]e?s? pour|conditionn[ée]e?s? pour|[ée]labor[ée]e?s? pour|produit pour|'
    'distribu[ée]e?s? (?:par|pour)|commercialis[ée]e?s? par|import[ée]e?s? par|'
    'hergestellt (?:in [a-zäöü]+ )?für|vertrieb(?:en)? (?:durch|von)|vertrieb|'
    'elaborado para|envasado para|fabricado para|distribuido por|prodotto per|confezionato per|'
    'distribuito da|geproduceerd voor|verpakt voor|produced for|packed for|manufactured for|made for|'
    'distributed by|produceret for|pakket for|wyprodukowano dla|dystrybutor|tillverkad för|'
    // Nordic labels.
    'fremstillet for|distribueret af|importeret af|importør|produsert for|distribuert av|importert av|'
    'distribueras av|importerad av|förpackad för',
  );

  /// "Para: Lidl Supermercados" — case-sensitive on the next word so
  /// "para calentar" (Spanish "to heat") is not taken for a company.
  static final RegExp _para = RegExp(r'(?<![\p{L}])[Pp][Aa][Rr][Aa](?=\s*:|\s+\p{Lu})\s*:?\s*', unicode: true);

  static final RegExp _by = _phrases(
    'fabriqu[ée]e?s? par|conditionn[ée]e?s? par|[ée]labor[ée]e?s? par|produit par|hergestellt von|'
    'hersteller|elaborado por|envasado por|fabricado por|produzido por|prodotto da|confezionato da|'
    'geproduceerd door|verpakt door|produced by|packed by|manufactured by|produceret af|pakket af|'
    'wyprodukowano przez|producent|tillverkad av|valmistaja|fremstillet af|produsert av|pakket av|'
    'förpackad av',
  );

  static final RegExp _legal = RegExp(
    r'(?<![\p{L}])(s\.?a\.?s\.?u?|s\.?a\.?r\.?l|s\.?a\.?u?|gmbh|ag|kg|s\.?l\.?u?|s\.?p\.?a\.?|s\.?r\.?l\.?|'
    r'sp\. ?z ?o\.? ?o\.?|a/s|aps|amba|b\.?v\.?|n\.?v\.?|ltd|limited|plc|oy|oyj)(?![\p{L}])',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _noise = RegExp(
    r'ingr[ée]dient|zutaten|ingredientes|ingredienti|nutri|energ|kcal|\bkj\b|graisse|fett|sucre|zucker|'
    r'sugar|\bsel\b|salz|prot[ée]in|conserv|consommer|haltbar|best before|poids|gewicht|peso|\blot\b|www\.|'
    r'http|@|\btel\b|t[ée]l[ée]phone|service|kunden|biologique|organic|gratis|r[ée]glementation|rejoignez',
    caseSensitive: false,
  );

  static const Set<String> _generic = <String>{
    'ab', 'eg', 'coop', 'cooperative', 'sa', 'sas', 'gmbh', 'kg', 'sl', 'spa', 'srl', 'bv', 'nv', 'ag',
    'foods', 'food', 'agriculture', 'bio', 'france', 'espana', 'italia', 'deutschland', 'co', 'gmbh co kg',
  };

  static final RegExp _cut = RegExp(
    r'\s[-–]\s|,\s*\d|,\s*(?:C/|Ctra|Rue|Via|Str|Avda|Av\.|Calle|BP|CS|ZI|ZA)\b|\s\d{2}[ -]?\d{3}\b|\bBP ?\d',
  );
  // Keeps "/" for Nordic legal forms (A/S).
  static final RegExp _junk = RegExp(r"[^\p{L}\p{N}&'’./\- ]+", unicode: true);
  static final RegExp _spaces = RegExp(r'\s+');

  static String _clean(final String s) {
    final String head = s.split(_cut).first;
    return head
        .replaceAll(_junk, ' ')
        .replaceAll(_spaces, ' ')
        .trim()
        .replaceAll(RegExp(r"^[ .\-']+|[ .\-']+$"), '');
  }

  static final RegExp _unit = RegExp(r'\d+\s*(g|kg|mg|ml|cl|l|zł|%)(?![\p{L}])', caseSensitive: false, unicode: true);
  static final RegExp _legalEnd = RegExp(
    r'(?:^|\s)(s\.?a\.?s\.?u?|s\.?a\.?r\.?l|s\.?a\.?u?|gmbh(?:\s?&\s?co\.?\s?kg)?|s\.?l\.?u?|s\.?p\.?a\.?|'
    r's\.?r\.?l\.?|sri|sp\. ?z ?o\.? ?o\.?|a/?\s?s|aps|amba|b\.?v\.?|n\.?v\.?|ltd|limited|plc|oy|oyj|ag)\.?$',
    caseSensitive: false,
  );
  static final RegExp _word3 = RegExp(r'\p{L}{3,}', unicode: true);

  static bool _ok(final String c, {required final bool fromPhrase}) {
    final String k = c.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ').replaceAll(_spaces, ' ').trim();
    final int letters = RegExp(r'\p{L}', unicode: true).allMatches(c).length;
    if (k.length < 4 || _generic.contains(k) || _noise.hasMatch(c) || _unit.hasMatch(c) || letters < 4) {
      return false;
    }
    final String probe = '$c ';
    final RegExpMatch? f = _for.firstMatch(probe) ?? _by.firstMatch(probe);
    if (f != null && f.start == 0 && f.end == probe.length) {
      return false;
    }
    final String trimmed = c.trim();
    if (!trimmed.contains(' ') && trimmed == trimmed.toLowerCase()) {
      return false;
    }
    if (!fromPhrase) {
      return _legalEnd.hasMatch(c) && _word3.allMatches(c).length >= 2;
    }
    return true;
  }

  /// Up to 6 operator-name candidates, best first.
  static List<String> candidates(final String ocrText) {
    final List<String> lines = ocrText
        .split('\n')
        .map((String l) => l.trim())
        .where((String l) => l.isNotEmpty)
        .toList();
    final List<(int, String)> out = <(int, String)>[];
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      bool phrase = false;
      for (final (int, RegExp) rule in <(int, RegExp)>[(0, _for), (0, _para), (1, _by)]) {
        for (final RegExpMatch m in rule.$2.allMatches(line)) {
          phrase = true;
          String rest = _clean(line.substring(m.end));
          if (rest.length < 3 && i + 1 < lines.length) {
            rest = _clean(lines[i + 1]);
          }
          out.add((rule.$1, rest));
        }
      }
      // A whole line is only a candidate on its own, not when a phrase already named the company.
      if (!phrase && _legal.hasMatch(line) && line.length <= 70) {
        out.add((2, _clean(line)));
      }
    }
    final List<(int, String)> sorted = List<(int, String)>.of(out)..sort(((int, String) a, (int, String) b) => a.$1.compareTo(b.$1));
    final Set<String> seen = <String>{};
    final List<String> ranked = <String>[];
    for (final (int, String) c in sorted) {
      final String key = c.$2.toLowerCase();
      if (_ok(c.$2, fromPhrase: c.$1 < 2) && seen.add(key)) {
        ranked.add(c.$2);
      }
    }
    return ranked.take(6).toList();
  }
}
