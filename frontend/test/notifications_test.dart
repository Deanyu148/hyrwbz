import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyrwbz_frontend/notification_model.dart';
import 'package:hyrwbz_frontend/notifications.dart';

NotificationItem notification(int id, {String? message}) => NotificationItem(
      id: id,
      taskId: id,
      meetingNo: '纪要〔2026〕$id号',
      taskNo: id,
      expectedDate: '2026-09-0$id',
      remainingDays: id,
      message: message ?? '通知$id',
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
              height: CompactNotificationPanel.heightForItemCount(6),
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

    expect(CompactNotificationPanel.panelWidth, 390);
    expect(
      tester.getSize(find.byType(CompactNotificationPanel)),
      const Size(390, 498),
    );
    expect(CompactNotificationPanel.heightForItemCount(0), 246);
    expect(CompactNotificationPanel.heightForItemCount(1), 267);
    expect(CompactNotificationPanel.heightForItemCount(2), 423);
    expect(CompactNotificationPanel.heightForItemCount(6), 498);
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

  testWidgets('notification rows grow with wrapped text and keep larger fonts', (tester) async {
    final items = [
      notification(1, message: '短通知'),
      notification(
        2,
        message: '这是一条用于验证通知正文自动换行和高度自动适配的较长通知内容，文字应保持左对齐，并在上下各留出半行文字高度。',
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                width: CompactNotificationPanel.panelWidth,
                height: CompactNotificationPanel.heightForItemCount(2),
                child: CompactNotificationPanel(
                  notifications: items,
                  onMarkAllRead: () async {},
                  onTap: (_) async {},
                ),
              ),
              Expanded(
                child: SizedBox(
                  width: 260,
                  child: NotificationListView(
                    notifications: items,
                    onTap: (_) async {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final compactShort = tester.getSize(
      find.byKey(const ValueKey('compact-notification-1')),
    );
    final compactLong = tester.getSize(
      find.byKey(const ValueKey('compact-notification-2')),
    );
    final fullShort = tester.getSize(
      find.byKey(const ValueKey('full-notification-1')),
    );
    final fullLong = tester.getSize(
      find.byKey(const ValueKey('full-notification-2')),
    );
    expect(compactLong.height, greaterThan(compactShort.height));
    expect(fullLong.height, greaterThan(fullShort.height));

    final compactText = tester.widget<Text>(find.text('短通知').first);
    final fullText = tester.widget<Text>(find.text('短通知').last);
    expect(compactText.style?.fontSize, CompactNotificationPanel.bodyFontSize);
    expect(fullText.style?.fontSize, NotificationListView.bodyFontSize);
    expect(compactText.textAlign, TextAlign.left);
    expect(fullText.textAlign, TextAlign.left);
  });
}
