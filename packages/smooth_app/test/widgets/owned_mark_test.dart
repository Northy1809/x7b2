import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_app/generic_lib/widgets/owned_wordmark.dart';
import 'package:smooth_app/helpers/string_extension.dart';
import 'package:smooth_app/pages/home/home_scanner_card.dart';
import 'package:smooth_app/widgets/cal_ui.dart';
import 'package:smooth_app/widgets/owned_mark.dart';
import 'package:smooth_app/widgets/scan_sweep.dart';

/// 17/11: the new logo, its motion, the home scanner and the scan line.
void main() {
  group('OwnedMark poses', () {
    test('the intro starts open and wide, and ends on the plain logo', () {
      final OwnedMarkPose start = OwnedMark.poseAt(0.0);
      expect(start.frame, greaterThan(1.1), reason: 'the corners come in from outside');
      expect(start.frameOpacity, 0.0);
      expect(start.ring, 0.0);
      expect(start.dot, 0.0);
      final OwnedMarkPose end = OwnedMark.poseAt(OwnedMark.intro.inMilliseconds.toDouble());
      expect(end, same(OwnedMarkPose.rest));
    });

    test('the loop keeps the logo whole while the ring turns and the line sweeps', () {
      final double introMs = OwnedMark.intro.inMilliseconds.toDouble();
      final double cycle = OwnedMark.cycle.inMilliseconds.toDouble();
      final OwnedMarkPose mid = OwnedMark.poseAt(introMs + cycle / 2, loop: true);
      expect(mid.ring, 1.0);
      expect(mid.frame, 1.0);
      expect(mid.spin, closeTo(0.5, 0.03));
      expect(mid.scan, closeTo(0.5, 0.03));
      expect(mid.scanOpacity, greaterThan(0.5));
      // One cycle later it is where it was.
      final OwnedMarkPose again = OwnedMark.poseAt(introMs + cycle * 1.5, loop: true);
      expect(again.spin, closeTo(mid.spin, 1e-9));
      expect(again.scan, closeTo(mid.scan!, 1e-9));
    });

    test('skipIntro starts the loop at once (the launch screen)', () {
      final OwnedMarkPose p = OwnedMark.poseAt(0.0, loop: true, skipIntro: true);
      expect(p.ring, 1.0);
      expect(p.frameOpacity, 1.0);
    });
  });

  testWidgets('the wordmark plays its intro once and settles', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: OwnedWordmark(height: 30.0, motion: OwnedMarkMotion.intro))),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Owned'), findsOneWidget);
    expect(find.byType(OwnedMark), findsOneWidget);
  });

  testWidgets('page waits show the moving logo, small ones the arc', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: <Widget>[
            CalLoader(label: 'Searching…'),
            CalLoader(size: 18.0, stroke: 2.0),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(OwnedLoader), findsOneWidget);
    expect(find.text('Searching…'), findsOneWidget);
    // Swapping the loaders away must not throw (17/11 regression).
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion: the logo and the scan line stand still', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Column(
            children: <Widget>[
              OwnedMark(size: 60.0, motion: OwnedMarkMotion.loop),
              SizedBox(height: 80.0, width: 80.0, child: ScanSweep()),
            ],
          ),
        ),
      ),
    );
    // Nothing keeps ticking.
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('the home scanner card opens the camera', (WidgetTester tester) async {
    int opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24.0),
            child: HomeScannerCard(onOpen: () => opened++),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Scan a product'), findsOneWidget);
    expect(find.text('Open camera'), findsOneWidget);
    expect(find.byType(ScanSweep), findsOneWidget);
    await tester.tap(find.byType(HomeScannerCard));
    await tester.pump(const Duration(milliseconds: 300));
    expect(opened, 1);
  });

  test('ScanSweepPainter: down leaves the wash above, up below', () {
    final ScanSweepPainter down = ScanSweepPainter(t: 0.5, down: true, color: Colors.white);
    final ScanSweepPainter up = ScanSweepPainter(t: 0.5, down: false, color: Colors.white);
    expect(down.shouldRepaint(up), isTrue);
    expect(down.shouldRepaint(ScanSweepPainter(t: 0.5, down: true, color: Colors.white)), isFalse);
  });

  group('capFirst', () {
    test('names start with a capital', () {
      expect('nutella'.capFirst(), 'Nutella');
      expect('coca-cola zero'.capFirst(), 'Coca-cola zero');
      expect('Nestlé'.capFirst(), 'Nestlé');
      expect('élan'.capFirst(), 'Élan');
      expect('  arla'.capFirst(), '  Arla');
      expect(''.capFirst(), '');
      expect('7up'.capFirst(), '7up');
    });

    test('names with their own capitals stay as they are', () {
      expect('iPhone'.capFirst(), 'iPhone');
      expect('eBay shop'.capFirst(), 'eBay shop');
    });
  });
}
