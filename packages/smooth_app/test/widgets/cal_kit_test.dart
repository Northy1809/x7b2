import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_app/themes/brand_colors.dart';
import 'package:smooth_app/widgets/cal_kit.dart';

/// The motion Cal AI was measured to have (30 fps screen recording,
/// research/ui/CALAI.md), checked frame by frame.
void main() {
  Widget app(final Widget child) => MaterialApp(
    theme: ThemeData(colorScheme: const ColorScheme.light(primary: BrandColors.ink, onPrimary: Colors.white)),
    home: Scaffold(body: Center(child: child)),
  );

  Color fillOf(final WidgetTester tester) {
    final AnimatedContainer box = tester.widget(find.byType(AnimatedContainer));
    final RenderBox render = tester.renderObject(find.byType(AnimatedContainer));
    expect(render.hasSize, isTrue);
    expect(box.decoration, isA<BoxDecoration>());
    final Container inner = tester.widget<Container>(
      find.descendant(of: find.byType(AnimatedContainer), matching: find.byType(Container)).first,
    );
    return (inner.decoration! as BoxDecoration).color!;
  }

  testWidgets('a choice turns ink within 100 ms, as Cal AI', (WidgetTester tester) async {
    bool selected = false;
    late StateSetter set;
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (BuildContext context, StateSetter s) {
            set = s;
            return SizedBox(
              width: 300,
              child: CalOption(selected: selected, onTap: () {}, child: const Text('0-2')),
            );
          },
        ),
      ),
    );
    expect(fillOf(tester), BrandColors.fill);
    set(() => selected = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final Color mid = fillOf(tester);
    expect(mid, isNot(BrandColors.fill));
    expect(mid, isNot(BrandColors.ink));
    await tester.pump(const Duration(milliseconds: 51));
    expect(fillOf(tester), BrandColors.ink);
  });

  testWidgets('rows rise in one after the other, 70 ms apart', (WidgetTester tester) async {
    await tester.pumpWidget(
      app(
        const Column(
          children: <Widget>[
            FadeUpIn(child: Text('a')),
            FadeUpIn(index: 1, child: Text('b')),
            FadeUpIn(index: 2, child: Text('c')),
          ],
        ),
      ),
    );
    double opacity(final String t) =>
        tester.widget<Opacity>(find.ancestor(of: find.text(t), matching: find.byType(Opacity)).first).opacity;
    await tester.pump(const Duration(milliseconds: 35));
    expect(opacity('a'), greaterThan(0.0));
    expect(opacity('b'), 0.0);
    await tester.pump(const Duration(milliseconds: 70));
    expect(opacity('b'), greaterThan(0.0));
    expect(opacity('c'), 0.0);
    await tester.pumpAndSettle();
    expect(opacity('a'), 1.0);
    expect(opacity('c'), 1.0);
  });

  testWidgets('a press shrinks to 96 % and springs back', (WidgetTester tester) async {
    int taps = 0;
    await tester.pumpWidget(app(PressScale(onTap: () => taps++, child: const SizedBox(width: 100, height: 60))));
    double scale() => tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
    final TestGesture g = await tester.startGesture(tester.getCenter(find.byType(PressScale)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(scale(), 0.96);
    await g.up();
    await tester.pumpAndSettle();
    expect(scale(), 1.0);
    expect(taps, 1);
  });

  testWidgets('a ring draws itself in from empty', (WidgetTester tester) async {
    await tester.pumpWidget(app(const CalRing(fraction: 0.5)));
    double drawn() => (tester.widget<CustomPaint>(find.byType(CustomPaint).last).painter! as CalRingPainter).fraction;
    expect(drawn(), 0.0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(drawn(), inExclusiveRange(0.0, 0.5));
    await tester.pumpAndSettle();
    expect(drawn(), 0.5);
  });
}
