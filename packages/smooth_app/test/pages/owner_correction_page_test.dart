import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_app/pages/owner/owner_correction_page.dart';
import 'package:smooth_app/services/owner_overrides.dart';
import 'package:smooth_app/services/ownership_local_db.dart';

void main() {
  final OwnershipLocalDb db = OwnershipLocalDb.fromJson(<String, dynamic>{
    'strings': <String>['Nestlé'],
    'brands': <String, dynamic>{},
    'by_country': <String, dynamic>{},
    'prefix': <String, dynamic>{},
    'emb': <String, dynamic>{},
    'companies': <String, dynamic>{},
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    OwnerOverrides.instance.resetForTest();
  });

  tearDown(OwnerOverrides.instance.resetForTest);

  Widget page() => MaterialApp(
    home: OwnerCorrectionPage(
      barcode: '1',
      brands: 'Nesquik',
      currentOwner: 'Someone',
      localDb: () async => db,
      ethicsDb: () async => throw StateError('no ethics in this test'),
    ),
  );

  testWidgets('an earlier correction is filled in and can be removed', (WidgetTester tester) async {
    await OwnerOverrides.instance.set(barcode: '1', brands: 'Nesquik', owner: 'Someone');
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Someone'), findsOneWidget);
    expect(find.text('Remove my correction'), findsOneWidget);
    await tester.tap(find.text('Remove my correction'));
    await tester.pumpAndSettle();
    expect(OwnerOverrides.instance.ownerFor(barcode: '1', brands: 'Nesquik'), isNull);
  });

  testWidgets('a new correction starts empty and saves the typed name', (WidgetTester tester) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(find.text('Remove my correction'), findsNothing);
    final FilledButton save = tester.widget(find.widgetWithText(FilledButton, 'Save correction'));
    expect(save.onPressed, isNull);
    await tester.enterText(find.byType(TextField), '  Nestlé ');
    await tester.pump();
    await tester.tap(find.text('Save correction'));
    await tester.pumpAndSettle();
    expect(OwnerOverrides.instance.ownerFor(barcode: '1', brands: 'Nesquik'), 'Nestlé');
  });
}
