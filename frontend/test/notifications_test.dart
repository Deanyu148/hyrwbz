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
  testWidgets('compact panel has strict size and previews only two items', (tester) async {
    final notifications = List.generate(6, (index) => notification(index + 1));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: CompactNotificationPanel.panelWidth,
              height: 166,
              child: CompactNotificationPanel(
                notifications: notifications,
                onMarkAllRead: () async {},
                onTap: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(CompactNotificationPanel.panelWidth, 130);
    expect(
      tester.getSize(find.byType(CompactNotificationPanel)),
      const Size(130, 166),
    );
    expect(CompactNotificationPanel.heightForItemCount(0), 82);
    expect(CompactNotificationPanel.heightForItemCount(1), 89);
    expect(CompactNotificationPanel.heightForItemCount(2), 141);
    expect(CompactNotificationPanel.heightForItemCount(6), 166);
    expect(find.text('通知1'), findsOneWidget);
    expect(find.text('通知2'), findsOneWidget);
    expect(find.text('通知3'), findsNothing);
    expect(find.text('还有 4 条'), findsOneWidget);
    expect(find.byIcon(Icons.done_all), findsOneWidget);
  });

  testWidgets('full notification list is not limited by compact preview rules', (tester) async {
    final notifications = List.generate(6, (index) => notification(index + 1));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationListView(
            notifications: notifications,
            onTap: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('通知1'), findsOneWidget);
    expect(find.text('通知6'), findsOneWidget);
    expect(find.textContaining('还有'), findsNothing);
  });
}
