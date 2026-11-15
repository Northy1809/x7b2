import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_app/services/label_operator_parser.dart';

/// Fixtures are real OCR lines from Open Food Facts product photos
/// (research/ocr/cache), trimmed to the operator block.
void main() {
  test('Spanish store brand: "Para:" (marketer) beats "Fabricado por:" (co-packer)', () {
    const String text = 'Fabricado por:\nHarinas de Castilla La Mancha, S.L.\nPara: Lidl Supermercados, S.A.U.\nHARINA PARA';
    final List<String> c = LabelOperatorParser.candidates(text);
    expect(c.first, 'Lidl Supermercados S.A.U');
    expect(c, contains('Harinas de Castilla La Mancha S.L'));
  });

  test('German "Hergestellt für" names the marketer', () {
    final List<String> c = LabelOperatorParser.candidates('Hergestellt für Polli GmbH, 6789 Musterstadt');
    expect(c.first, 'Polli GmbH');
  });

  test('French "Fabriqué par" with accents', () {
    final List<String> c = LabelOperatorParser.candidates('Fabriqué par VALENTIN TRAITEUR - 56250 Elven');
    expect(c.first, 'VALENTIN TRAITEUR');
  });

  test('ingredient and nutrition lines are never candidates', () {
    final List<String> c = LabelOperatorParser.candidates(
      'Ingrédients: farine de blé, sucre, sel\nÉnergie 1500 kJ\npara calentar en el horno',
    );
    expect(c, isEmpty);
  });

  test('generic tokens like "AB" or "EG" are rejected', () {
    expect(LabelOperatorParser.candidates('AB\nEG\nCOOP'), isEmpty);
  });

  test('a single lowercase word after a phrase is not a company', () {
    expect(LabelOperatorParser.candidates('Hergestellt von nature'), isEmpty);
  });

  test('weights are not taken for the German legal form KG', () {
    expect(LabelOperatorParser.candidates('con 1 kg ben 4 torte\nAG 10g-AS 12g-AN 5'), isEmpty);
  });

  test('legal-form line without a phrase still found when it ends with the legal form', () {
    expect(LabelOperatorParser.candidates('SALICA INDUSTRIA ALIMENTARIA S.A.'), <String>['SALICA INDUSTRIA ALIMENTARIA S.A']);
  });

  test('Danish and Norwegian labels: "for" (marketer) beats "af/av" (maker)', () {
    expect(
      LabelOperatorParser.candidates('Fremstillet af: Mejeri Nord ApS\nFremstillet for: Salling Group A/S, 8270 Højbjerg'),
      <String>['Salling Group A/S', 'Mejeri Nord ApS'],
    );
    expect(LabelOperatorParser.candidates('Produsert for: Rema 1000 Norge AS'), <String>['Rema 1000 Norge AS']);
    expect(LabelOperatorParser.candidates('Importeret af: Dagrofa ApS'), <String>['Dagrofa ApS']);
  });
}
