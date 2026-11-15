/// Turns whatever the camera read into the product number (GTIN) that
/// Open Food Facts and the ownership database are keyed on.
///
/// Packs carry more than plain EAN-13 bars: QR codes and Data Matrix with a
/// GS1 Digital Link (https://id.gs1.org/01/05701234567892/10/LOT) or a GS1
/// element string ("(01)05701234567892(17)270101", or the raw form with
/// FNC1 separators), and outer cases carry ITF-14. Reference:
/// GS1 General Specifications, sections 3.2 (AI 01) and 7.9 (check digit);
/// GS1 Digital Link standard 1.4.
class Gs1Code {
  const Gs1Code._();

  static final RegExp _digits = RegExp(r'^\d+$');
  static final RegExp _symbologyId = RegExp(r'^\][A-Za-z]\d');
  static final RegExp _bracketedGtin = RegExp(r'\(01\)(\d{14})');

  /// The GTIN to look up, or null when [raw] is not a product code (e.g. a
  /// QR code with a plain web address).
  ///
  /// GTIN-12 (UPC-A) is padded to 13 digits and GTIN-14 is reduced to the
  /// 13-digit GTIN of the item inside, which is how Open Food Facts stores
  /// barcodes.
  static String? toProductCode(final String raw) {
    String code = raw.trim().replaceFirst(_symbologyId, '');
    if (code.isEmpty) {
      return null;
    }

    final String compact = code.replaceAll(RegExp(r'[\s-]'), '');
    if (_digits.hasMatch(compact)) {
      // Plain linear barcode. A long numeric string starting with AI 01 is
      // an element string without separators.
      if (compact.length > 14 && compact.startsWith('01')) {
        return _normalize(compact.substring(2, 16));
      }
      return _normalize(compact);
    }

    final String? fromLink = _gtinFromDigitalLink(code);
    if (fromLink != null) {
      return _normalize(fromLink);
    }

    final RegExpMatch? bracketed = _bracketedGtin.firstMatch(code);
    if (bracketed != null) {
      return _normalize(bracketed.group(1)!);
    }

    // Raw element string: FNC1 shows up as GS (0x1D) or the visible ␝.
    code = code.replaceAll('␝', '\x1D');
    if (code.startsWith('\x1D')) {
      code = code.substring(1);
    }
    if (code.startsWith('01') && code.length >= 16 && _digits.hasMatch(code.substring(2, 16))) {
      return _normalize(code.substring(2, 16));
    }
    return null;
  }

  /// "https://id.gs1.org/01/05701234567892/10/ABC" or "...?01=..." → GTIN.
  static String? _gtinFromDigitalLink(final String value) {
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      return null;
    }
    final Uri? uri = Uri.tryParse(value);
    if (uri == null) {
      return null;
    }
    final List<String> segments = uri.pathSegments;
    for (int i = 0; i < segments.length - 1; i++) {
      if (segments[i] == '01' || segments[i] == 'gtin') {
        final String v = segments[i + 1];
        if (_digits.hasMatch(v) && v.length >= 8 && v.length <= 14) {
          return v;
        }
      }
    }
    final String? q = uri.queryParameters['01'] ?? uri.queryParameters['gtin'];
    if (q != null && _digits.hasMatch(q)) {
      return q;
    }
    return null;
  }

  static String? _normalize(String code) {
    if (code.length == 14) {
      if (code.startsWith('000000')) {
        // A GTIN-8 padded to 14 digits; Open Food Facts keys it on 8.
        return code.substring(6);
      }
      if (code.startsWith('0')) {
        code = code.substring(1);
      } else if (code[0] != '9') {
        // Indicator 1-8: a case of the item. The item's own GTIN-13 is the
        // 12 digits after the indicator plus a new check digit. (9 means a
        // variable-measure item, which has no fixed GTIN-13.)
        final String body = code.substring(1, 13);
        return body + checkDigit(body).toString();
      } else {
        return null;
      }
    }
    if (code.length == 12) {
      return '0$code';
    }
    if (code.length < 4) {
      return null;
    }
    return code;
  }

  /// GS1 modulo-10 check digit for the digits before it.
  static int checkDigit(final String body) {
    int sum = 0;
    for (int i = 0; i < body.length; i++) {
      final int d = body.codeUnitAt(body.length - 1 - i) - 48;
      sum += i.isEven ? d * 3 : d;
    }
    return (10 - sum % 10) % 10;
  }

  static bool hasValidCheckDigit(final String code) =>
      _digits.hasMatch(code) &&
      code.length >= 8 &&
      checkDigit(code.substring(0, code.length - 1)) ==
          code.codeUnitAt(code.length - 1) - 48;

  /// Codes a shop or company prints for itself (weighed fresh food,
  /// in-store items): GS1 prefixes 02, 04 and 20-29. They don't identify a
  /// product outside that shop.
  static bool isInStoreCode(final String code) {
    if (code.length == 13) {
      return code.startsWith('02') ||
          code.startsWith('04') ||
          code.startsWith('2');
    }
    if (code.length == 8) {
      return code.startsWith('2');
    }
    return false;
  }

  /// ISBN barcodes (prefix 978/979): books.
  static bool isBook(final String code) =>
      code.length == 13 && (code.startsWith('978') || code.startsWith('979'));

  /// Country of the GS1 office that issued the company prefix. This is where
  /// the brand owner registered the barcode, not where the item was made.
  static String? registrationCountry(final String code) {
    if (code.length != 13 || !_digits.hasMatch(code)) {
      return null;
    }
    final int p3 = int.parse(code.substring(0, 3));
    for (final (int from, int to, String country) in _prefixes) {
      if (p3 >= from && p3 <= to) {
        return country;
      }
    }
    return null;
  }

  /// GS1 company prefix ranges (gs1.org/standards/id-keys/company-prefix).
  static const List<(int, int, String)> _prefixes = <(int, int, String)>[
    (0, 19, 'the USA or Canada'),
    (30, 39, 'the USA or Canada'),
    (60, 139, 'the USA or Canada'),
    (300, 379, 'France'),
    (380, 380, 'Bulgaria'),
    (383, 383, 'Slovenia'),
    (385, 385, 'Croatia'),
    (387, 387, 'Bosnia and Herzegovina'),
    (389, 389, 'Montenegro'),
    (400, 440, 'Germany'),
    (450, 459, 'Japan'),
    (460, 469, 'Russia'),
    (470, 470, 'Kyrgyzstan'),
    (471, 471, 'Taiwan'),
    (474, 474, 'Estonia'),
    (475, 475, 'Latvia'),
    (476, 476, 'Azerbaijan'),
    (477, 477, 'Lithuania'),
    (478, 478, 'Uzbekistan'),
    (479, 479, 'Sri Lanka'),
    (480, 480, 'the Philippines'),
    (481, 481, 'Belarus'),
    (482, 482, 'Ukraine'),
    (484, 484, 'Moldova'),
    (485, 485, 'Armenia'),
    (486, 486, 'Georgia'),
    (487, 487, 'Kazakhstan'),
    (489, 489, 'Hong Kong'),
    (490, 499, 'Japan'),
    (500, 509, 'the UK'),
    (520, 521, 'Greece'),
    (528, 528, 'Lebanon'),
    (529, 529, 'Cyprus'),
    (530, 530, 'Albania'),
    (531, 531, 'North Macedonia'),
    (535, 535, 'Malta'),
    (539, 539, 'Ireland'),
    (540, 549, 'Belgium or Luxembourg'),
    (560, 560, 'Portugal'),
    (569, 569, 'Iceland'),
    (570, 579, 'Denmark'),
    (590, 590, 'Poland'),
    (594, 594, 'Romania'),
    (599, 599, 'Hungary'),
    (600, 601, 'South Africa'),
    (611, 611, 'Morocco'),
    (613, 613, 'Algeria'),
    (616, 616, 'Kenya'),
    (619, 619, 'Tunisia'),
    (622, 622, 'Egypt'),
    (625, 625, 'Jordan'),
    (626, 626, 'Iran'),
    (628, 628, 'Saudi Arabia'),
    (629, 629, 'the United Arab Emirates'),
    (640, 649, 'Finland'),
    (690, 699, 'China'),
    (700, 709, 'Norway'),
    (729, 729, 'Israel'),
    (730, 739, 'Sweden'),
    (740, 745, 'Central America'),
    (750, 750, 'Mexico'),
    (754, 755, 'Canada'),
    (759, 759, 'Venezuela'),
    (760, 769, 'Switzerland'),
    (770, 771, 'Colombia'),
    (773, 773, 'Uruguay'),
    (775, 775, 'Peru'),
    (777, 777, 'Bolivia'),
    (778, 779, 'Argentina'),
    (780, 780, 'Chile'),
    (784, 784, 'Paraguay'),
    (786, 786, 'Ecuador'),
    (789, 790, 'Brazil'),
    (800, 839, 'Italy'),
    (840, 849, 'Spain'),
    (850, 850, 'Cuba'),
    (858, 858, 'Slovakia'),
    (859, 859, 'the Czech Republic'),
    (860, 860, 'Serbia'),
    (865, 865, 'Mongolia'),
    (867, 867, 'North Korea'),
    (868, 869, 'Turkey'),
    (870, 879, 'the Netherlands'),
    (880, 881, 'South Korea'),
    (884, 884, 'Cambodia'),
    (885, 885, 'Thailand'),
    (888, 888, 'Singapore'),
    (890, 890, 'India'),
    (893, 893, 'Vietnam'),
    (896, 896, 'Pakistan'),
    (899, 899, 'Indonesia'),
    (900, 919, 'Austria'),
    (930, 939, 'Australia'),
    (940, 949, 'New Zealand'),
    (955, 955, 'Malaysia'),
    (958, 958, 'Macau'),
  ];
}
