import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyrwbz_frontend/screens/date_picker_dialog.dart';

void main() {
  testWidgets('clicking the year replaces the month calendar with year mode', (tester) async {
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
    expect(find.byType(CalendarDatePicker), findsOneWidget);
  });
}
