import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_app/services/score_types.dart';

double _contrast(final Color a, final Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  test('every score colour reaches 4.5:1 as text on light and dark cards', () {
    for (final ScoreBand band in ScoreBand.values) {
      for (final Color bg in <Color>[Colors.white, const Color(0xFF161936)]) {
        expect(_contrast(readableOn(band.color, bg), bg), greaterThanOrEqualTo(4.5), reason: '${band.name} on $bg');
      }
    }
  });

  test('a colour that is already readable is left alone', () {
    const Color ink = Color(0xFF161B52);
    expect(readableOn(ink, Colors.white), ink);
  });
}
