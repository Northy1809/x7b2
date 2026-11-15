import 'package:smooth_app/services/ownership_fold_table.dart';

/// Brand/company name normalization. Must stay byte-identical with
/// research/prefix/norm.py, because the offline database keys were built with it.
class OwnershipNorm {
  const OwnershipNorm._();

  static final RegExp _nonWord = RegExp(r'[^a-z0-9ø æåß]+');
  static final RegExp _spaces = RegExp(r'\s+');
  static final RegExp _legal = RegExp(
    r'\b(a/?s|aps|amba|a\.m\.b\.a|gmbh(?: & co\.? kg)?|kg|ag|se|s\.?a\.?s?|s\.?p\.?a|s\.?r\.?l|b\.?v|n\.?v|ltd|limited|plc|inc|llc|co|corp|corporation|oy|oyj|ab|asa|sp\. z o\.o\.|s\.l|sl|srl|spa|sas|sa|bv|nv|group|groupe)\b\.?',
  );

  static const Set<String> stopBrands = <String>{
    'bio', 'organic', 'demeter', 'ab', 'eu', 'vegan', 'fairtrade', 'naturland', 'bioland', 'sans marque',
    'no brand', 'generique', 'generic', 'marque distributeur', 'unbranded', 'sin marca', 'senza marca',
    'ohne marke', 'aucune', 'none', 'n a', 'na', 'x', 'bio organic', 'agriculture biologique', 'ecocert',
    'max havelaar', 'v label', 'europe', 'null',
  };

  static String _fold(final String lower) {
    final StringBuffer out = StringBuffer();
    for (final int rune in lower.runes) {
      final String ch = String.fromCharCode(rune);
      out.write(kOwnershipFoldTable[ch] ?? ch);
    }
    return out.toString();
  }

  static String norm(final String input) {
    String s = _fold(input.toLowerCase());
    // OFF sometimes stores escaped apostrophes (C\'est).
    s = s.replaceAll('&', ' and ').replaceAll(r'\', '').replaceAll("'", '').replaceAll('’', '');
    s = s.replaceAll('ø', 'o').replaceAll('æ', 'ae').replaceAll('å', 'a').replaceAll('ß', 'ss');
    s = s.replaceAll(_nonWord, ' ');
    return s.replaceAll(_spaces, ' ').trim();
  }

  static String normCore(final String input) {
    final String n = norm(input);
    final String c = n.replaceAll(_legal, ' ').replaceAll(_spaces, ' ').trim();
    return c.isEmpty ? n : c;
  }

  static List<String> splitBrands(final String? brands) => (brands ?? '')
      .split(',')
      .map((String x) => x.trim())
      .where((String x) => x.isNotEmpty)
      .toList();
}
