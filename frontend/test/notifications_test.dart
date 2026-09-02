import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyrwbz_frontend/notification_model.dart';
import 'package:hyrwbz_frontend/notifications.dart';

NotificationItem notification(int id) => NotificationItem(
      id: id,
      taskId: id,
      meetingNo: '纪要〔2026〕$id号',
      taskNo: id,
      expectedDate: '2026-09-0$id',
      remainingDays: id,
      message: '通知$id',
      notificationDate: '2026-09-02',
      isRead: false,
    );

void main() {
  testWidgets('compact notification panel previews at most four items', (tester) async {
    final notifications = List.generate(6, (index) => notification(index + 1));
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 297,
          child: NotificationListView(
            notifications: notifications,
            compact: true,
            onMarkAllRead: () async {},
            onTap: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('通知1'), findsOneWidget);
    expect(find.text('通知4'), findsOneWidget);
    expect(find.text('通知5'), findsNothing);
    expect(find.text('还有 2 条，点击通知按钮查看全部'), findsOneWidget);
  });
}
