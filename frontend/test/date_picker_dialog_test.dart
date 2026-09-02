import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyrwbz_frontend/screens/date_picker_dialog.dart';

void main() {
  testWidgets('selecting a year returns to month mode without finalizing date', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DatePickerDialogWidget(initial: '2026/09/02'),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('month-date-picker')), findsOneWidget);
    expect(find.byKey(const ValueKey('year-date-picker')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('year-selector')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('month-date-picker')), findsNothing);
    expect(find.byKey(const ValueKey('year-date-picker')), findsOneWidget);
    expect(find.byType(YearPicker), findsOneWidget);
    expect(find.byKey(const ValueKey('return-to-month-picker')), findsOneWidget);

    await tester.tap(find.text('2027').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('year-date-picker')), findsNothing);
    expect(find.byKey(const ValueKey('month-date-picker')), findsOneWidget);
    expect(find.text('2027年'), findsOneWidget);
    final fieldBeforeDaySelection =
        tester.widget<TextField>(find.byType(TextField));
    expect(fieldBeforeDaySelection.controller?.text, '2026/09/02');

    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();

    final fieldAfterDaySelection =
        tester.widget<TextField>(find.byType(TextField));
    expect(fieldAfterDaySelection.controller?.text, '2027/09/15');
  });
}
