import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_app/helpers/haptics.dart';
import 'package:smooth_app/widgets/cal_kit.dart';
import 'package:smooth_app/widgets/smooth_navigation_bar.dart';

/// Where the phone vibrates, and that "off" in Profile means off.
void main() {
  final List<String> platform = <String>[];

  setUp(() {
    Haptics.debugLog.clear();
    Haptics.debugEnabledOverride = true;
    platform.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          platform.add(call.arguments as String);
        }
        return null;
      },
    );
  });

  tearDown(() => Haptics.debugEnabledOverride = null);

  test('each pattern plays the right iOS feedback', () async {
    Haptics.tap();
    Haptics.select();
    Haptics.open();
    Haptics.shutter();
    await Future<void>.delayed(Duration.zero);
    expect(platform, <String>[
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.heavyImpact',
    ]);
  });

  test('success is a light then a medium beat, 90 ms apart', () async {
    Haptics.success();
    await Future<void>.delayed(Duration.zero);
    expect(platform, <String>['HapticFeedbackType.lightImpact']);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(platform, <String>['HapticFeedbackType.lightImpact', 'HapticFeedbackType.mediumImpact']);
  });

  test('nothing vibrates when haptics are off', () async {
    Haptics.debugEnabledOverride = false;
    Haptics.tap();
    Haptics.success();
    Haptics.warning();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(platform, isEmpty);
    expect(Haptics.debugLog, isEmpty);
  });

  testWidgets('a press taps, a choice ticks', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: <Widget>[
            PressScale(onTap: () {}, child: const SizedBox(width: 100, height: 40, child: Text('card'))),
            CalOption(onTap: () {}, child: const Text('choice')),
          ],
        ),
      ),
    );
    await tester.tap(find.text('card'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('choice'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(Haptics.debugLog, <String>['tap', 'select']);
  });

  testWidgets('changing tab ticks; tapping the current tab does not', (WidgetTester tester) async {
    int selected = 0;
    Widget bar() => MaterialApp(
      home: Scaffold(
        bottomNavigationBar: StatefulBuilder(
          builder: (BuildContext context, StateSetter set) => SmoothNavigationBar(
            selectedIndex: selected,
            onDestinationSelected: (int i) => set(() => selected = i),
            onPlus: () {},
            destinations: const <SmoothNavigationDestination>[
              SmoothNavigationDestination(icon: Icon(Icons.home), label: 'Home'),
              SmoothNavigationDestination(icon: Icon(Icons.search), label: 'Search'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(bar());
    await tester.tap(find.text('Home'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(Haptics.debugLog, isEmpty);
    await tester.tap(find.text('Search'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(Haptics.debugLog, <String>['select']);
    expect(selected, 1);
    await tester.tap(find.bySemanticsLabel('Scan a product'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(Haptics.debugLog, <String>['select', 'open']);
  });

  testWidgets('page dots mark the current page', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: CalPageDots(count: 3, index: 1))));
    expect(find.bySemanticsLabel('Page 2 of 3'), findsOneWidget);
  });
}
