import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smooth_app/pages/scan/result/result_sheet_parts.dart';
import 'package:smooth_app/widgets/company_logo.dart';

/// The bundled logo shows, also when the name arrives after the first
/// frame (the owner is looked up while the sheet is already open), and a
/// rebuild does not send it back to the placeholder.
void main() {
  setUp(() {
    LogoIndex.instance.online = false;
    LogoIndex.instance.resetForTest();
  });

  Future<void> settle(final WidgetTester tester) async {
    for (int i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('a known company shows its bundled logo', (WidgetTester tester) async {
    expect(await tester.runAsync(() => LogoIndex.instance.bundled(<String>['Nestlé'])), isNotNull);
    await tester.pumpWidget(const MaterialApp(home: Center(child: CompanyLogo(names: <String>['Nestlé']))));
    await settle(tester);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('the logo follows a name that arrives later', (WidgetTester tester) async {
    Widget app(final List<String?> names) => MaterialApp(home: Center(child: CompanyLogo(names: names)));
    await tester.pumpWidget(app(const <String?>[]));
    await settle(tester);
    expect(find.byType(Image), findsNothing);
    await tester.pumpWidget(app(const <String?>['Nestlé']));
    await settle(tester);
    expect(find.byType(Image), findsOneWidget);
    // Same names again: still the logo, no placeholder in between.
    await tester.pumpWidget(app(const <String?>['Nestlé']));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('the result sheet shows the owner logo', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OwnerResultHeader(
            ownerName: 'Nestlé',
            logoNames: const <String?>['Nestlé'],
            onTap: () {},
            subtitle: 'Nesquik · 1 kg',
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.byType(Image), findsOneWidget);
  });
}
