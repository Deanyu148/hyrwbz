class NotificationItem {
  final int id;
  final int taskId;
  final String meetingNo;
  final int taskNo;
  final String expectedDate;
  final int remainingDays;
  final String message;
  final String notificationDate;
  final bool isRead;

  const NotificationItem({
    required this.id,
    required this.taskId,
    required this.meetingNo,
    required this.taskNo,
    required this.expectedDate,
    required this.remainingDays,
    required this.message,
    required this.notificationDate,
    required this.isRead,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) => NotificationItem(
        id: (json['id'] as num).toInt(),
        taskId: (json['task_id'] as num).toInt(),
        meetingNo: json['meeting_no'] as String? ?? '',
        taskNo: (json['task_no'] as num).toInt(),
        expectedDate: json['expected_date'] as String? ?? '',
        remainingDays: (json['remaining_days'] as num).toInt(),
        message: json['message'] as String? ?? '',
        notificationDate: json['notification_date'] as String? ?? '',
        isRead: json['is_read'] as bool? ?? false,
      );
}
