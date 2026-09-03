import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyrwbz_frontend/screens/filter_screen.dart';
import 'package:hyrwbz_frontend/search_field.dart';

void main() {
  testWidgets('filter inputs use complete labels without comma hint', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: FilterScreen()),
      ),
    );

    for (final label in [
      '会议纪要号',
      '任务序号',
      '责任部门',
      '责任人',
      '延期次数≥',
      '附件状态',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.textContaining('逗号分隔'), findsNothing);
    expect(find.text('期望剩余天数'), findsNothing);
    expect(find.byType(AppFilterField), findsNWidgets(5));
    expect(tester.takeException(), isNull);
  });
}
