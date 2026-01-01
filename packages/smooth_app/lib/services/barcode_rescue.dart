import 'package:smooth_app/helpers/gs1_code.dart';

/// Second and third chances for a barcode the camera could not read from
/// the bars (20/11 2026): blur, glare, a curved pack or a barcode only
/// half in the picture.
///
/// 1. [fromText]: the digits printed under the bars, as the text reader
///    saw them ("5 701234 567892"), when their GS1 check digit is right.
/// (25/11: the clearer copies of the photo are now passes inside
/// ZxingBarcodeReader, on grey pixels, without writing image files.)
class BarcodeRescue {
  const BarcodeRescue._();

  static final RegExp _run = RegExp(r'\d+');

  /// Lengths of the product codes on packs: EAN-13, UPC-A, EAN-8, ITF-14.
  static const List<int> _lengths = <int>[13, 12, 14, 8];

  /// The product code in the pack's printed text, or null.
  ///
  /// Digit groups next to each other (on one line or the next one) are
  /// joined, since the digits under EAN-13 bars are printed as 1 + 6 + 6.
  /// Only a code whose check digit is right counts, and shop-only codes
  /// (weighed fresh food) do not.
  static String? fromText(final List<String> lines) {
    // Every digit group, in reading order, with the line it is on.
    final List<(int, String)> groups = <(int, String)>[
      for (int l = 0; l < lines.length; l++)
        for (final RegExpMatch m in _run.allMatches(lines[l])) (l, m.group(0)!),
    ];
    final List<String> found = <String>[];
    for (int i = 0; i < groups.length; i++) {
      final StringBuffer joined = StringBuffer();
      for (int j = i; j < groups.length && j < i + 4; j++) {
        // Groups more than one line apart are not one code.
        if (groups[j].$1 - groups[i].$1 > 1) {
          break;
        }
        joined.write(groups[j].$2);
        final String code = joined.toString();
        if (code.length > 14) {
          break;
        }
        if (_lengths.contains(code.length) && Gs1Code.hasValidCheckDigit(code)) {
          found.add(code);
        }
      }
    }
    for (final int length in _lengths) {
      for (final String code in found) {
        if (code.length != length) {
          continue;
        }
        final String? product = Gs1Code.toProductCode(code);
        if (product != null && !Gs1Code.isInStoreCode(product)) {
          return product;
        }
      }
    }
    return null;
  }

  /// Whether the text has a run of digits as long as a barcode's, i.e. a
  /// barcode is probably in the picture.
  static bool mentionsACode(final List<String> lines) =>
      fromTextDigits(lines).any((String d) => d.length >= 8);

  static Iterable<String> fromTextDigits(final List<String> lines) sync* {
    for (final String line in lines) {
      final String compact = line.replaceAll(RegExp(r'[\s-]'), '');
      for (final RegExpMatch m in _run.allMatches(compact)) {
        yield m.group(0)!;
      }
    }
  }
}
