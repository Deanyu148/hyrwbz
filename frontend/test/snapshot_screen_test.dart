import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyrwbz_frontend/models.dart';
import 'package:hyrwbz_frontend/screens/snapshot_screen.dart';
import 'package:hyrwbz_frontend/search_field.dart';

void main() {
  test('snapshot save message ends with current usage', () {
    expect(
      snapshotSavedMessage(3),
      endsWith('（当前已经使用3份）'),
    );
  });

  testWidgets('snapshot screen renders a read-only main-table style view', (tester) async {
    const info = SnapshotInfo(
      snapshotId: 1,
      savedAt: '2026-09-02 12:00:00',
      remark: '检查前',
    );
    final detail = SnapshotDetail(
      snapshotId: 1,
      savedAt: info.savedAt,
      remark: info.remark,
      tasks: [
        Task(
          id: 1,
          meetingNo: '纪要〔2026〕1号',
          taskNo: 1,
          taskDesc: '只读任务',
          dept: '工程部',
          owner: '张三',
          requiredDate: '2026/09/10',
          actualDate: '进行中',
          remark: '快照备注',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SnapshotScreen(snapshot: info, initialDetail: detail),
      ),
    );

    expect(find.text('历史快照'), findsOneWidget);
    expect(find.byType(AppSearchField), findsOneWidget);
    expect(find.byIcon(Icons.filter_alt_rounded), findsOneWidget);
    expect(find.text('只读任务'), findsOneWidget);
    expect(find.text('检查前'), findsOneWidget);
    expect(find.text('只读'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsWidgets);
    expect(find.text('添加条目'), findsNothing);
    expect(find.text('保存'), findsNothing);
  });
}
