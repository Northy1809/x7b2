import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_app/services/live_barcode_reader.dart';

/// 25/11: a live barcode opens only when two frames in a row agree.
void main() {
  final DateTime t0 = DateTime(2026, 11, 25, 12);
  LiveBarcodeReader reader() => LiveBarcodeReader(onCode: (_) {});

  test('two frames reading the same code open it', () {
    final LiveBarcodeReader r = reader();
    expect(r.vote(<String>['3017620422003'], t0), isNull);
    expect(r.vote(<String>['3017620422003'], t0.add(const Duration(milliseconds: 300))), '3017620422003');
  });

  test('a misread in one frame does not open anything', () {
    final LiveBarcodeReader r = reader();
    expect(r.vote(<String>['3017620422003'], t0), isNull);
    expect(r.vote(<String>['5000112637922'], t0.add(const Duration(milliseconds: 200))), isNull);
    expect(r.vote(<String>['5000112637922'], t0.add(const Duration(milliseconds: 400))), '5000112637922');
  });

  test('frames too far apart start over', () {
    final LiveBarcodeReader r = reader();
    expect(r.vote(<String>['3017620422003'], t0), isNull);
    expect(r.vote(<String>['3017620422003'], t0.add(const Duration(seconds: 3))), isNull);
  });

  test('a wrong check digit, a shop code or two products in view wait', () {
    final LiveBarcodeReader r = reader();
    for (int i = 0; i < 3; i++) {
      final DateTime t = t0.add(Duration(milliseconds: 200 * i));
      expect(r.vote(<String>['3017620422004'], t), isNull);
      expect(r.vote(<String>['2012345678903'], t), isNull);
      expect(r.vote(<String>['3017620422003', '5000112637922'], t), isNull);
    }
  });

  test('Lidl EAN-8 codes starting with 2 count', () {
    final LiveBarcodeReader r = reader();
    expect(r.vote(<String>['20004101'], t0), isNull);
    expect(r.vote(<String>['20004101'], t0.add(const Duration(milliseconds: 200))), '20004101');
  });

  test('an empty frame between two reads does not reset', () {
    final LiveBarcodeReader r = reader();
    expect(r.vote(<String>['3017620422003'], t0), isNull);
    expect(r.vote(const <String>[], t0.add(const Duration(milliseconds: 150))), isNull);
    expect(r.vote(<String>['3017620422003'], t0.add(const Duration(milliseconds: 300))), '3017620422003');
  });
}
