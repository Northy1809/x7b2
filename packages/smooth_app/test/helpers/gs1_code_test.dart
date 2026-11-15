import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_app/helpers/gs1_code.dart';

void main() {
  group('Gs1Code.toProductCode', () {
    test('plain EAN-13 and EAN-8 pass through', () {
      expect(Gs1Code.toProductCode('5701073063643'), '5701073063643');
      expect(Gs1Code.toProductCode(' 5701-0730-63643 '), '5701073063643');
      expect(Gs1Code.toProductCode('96385074'), '96385074');
      // GTIN-8 padded to 14 digits (Digital Link, ITF-14) keeps its 8 digits.
      expect(Gs1Code.toProductCode('https://id.gs1.org/01/00000096385074'), '96385074');
    });

    test('UPC-A is padded to 13 digits, like Open Food Facts stores it', () {
      expect(Gs1Code.toProductCode('036000291452'), '0036000291452');
    });

    test('GS1 Digital Link QR codes give the GTIN', () {
      expect(
        Gs1Code.toProductCode('https://id.gs1.org/01/05701073063643/10/AB12?17=270101'),
        '5701073063643',
      );
      expect(
        Gs1Code.toProductCode('https://brand.example.com/products/01/05701073063643'),
        '5701073063643',
      );
      expect(Gs1Code.toProductCode('https://example.com/?01=05701073063643'), '5701073063643');
    });

    test('a QR code with an ordinary web address is not a product', () {
      expect(Gs1Code.toProductCode('https://www.example.com/campaign'), isNull);
      expect(Gs1Code.toProductCode('WIFI:S:home;T:WPA;P:secret;;'), isNull);
    });

    test('GS1 element strings: bracketed, raw with FNC1, and with a symbology id', () {
      expect(Gs1Code.toProductCode('(01)05701073063643(17)270101(10)LOT'), '5701073063643');
      expect(Gs1Code.toProductCode('0105701073063643\x1D10LOT42'), '5701073063643');
      expect(Gs1Code.toProductCode(']d20105701073063643172701011012'), '5701073063643');
    });

    test('ITF-14 case codes map to the GTIN-13 of the item inside', () {
      // Indicator 0: same item.
      expect(Gs1Code.toProductCode('05701073063643'), '5701073063643');
      // Indicator 1: a case; drop it and recompute the check digit.
      expect(Gs1Code.toProductCode('15701073063640'), '5701073063644');
      // Indicator 9: variable measure, no fixed item code.
      expect(Gs1Code.toProductCode('95701073063646'), isNull);
    });

    test('too short to be anything', () {
      expect(Gs1Code.toProductCode('123'), isNull);
      expect(Gs1Code.toProductCode(''), isNull);
    });
  });

  group('Gs1Code helpers', () {
    test('check digit', () {
      expect(Gs1Code.checkDigit('570107306364'), 4);
      expect(Gs1Code.checkDigit('301762042200'), 3);
      expect(Gs1Code.hasValidCheckDigit('3017620422003'), isTrue);
      expect(Gs1Code.hasValidCheckDigit('3017620422004'), isFalse);
    });

    test('in-store codes and books', () {
      expect(Gs1Code.isInStoreCode('2012345678903'), isTrue);
      expect(Gs1Code.isInStoreCode('0212345678904'), isTrue);
      expect(Gs1Code.isInStoreCode('5701073063643'), isFalse);
      expect(Gs1Code.isBook('9780141036144'), isTrue);
      expect(Gs1Code.isBook('5701073063643'), isFalse);
    });

    test('registration country from the prefix', () {
      expect(Gs1Code.registrationCountry('5701073063643'), 'Denmark');
      expect(Gs1Code.registrationCountry('3017620422003'), 'France');
      expect(Gs1Code.registrationCountry('4008400401621'), 'Germany');
      expect(Gs1Code.registrationCountry('0036000291452'), 'the USA or Canada');
      expect(Gs1Code.registrationCountry('96385074'), isNull);
    });
  });
}
