import 'notification_model.dart';
import 'search_query.dart';

bool notificationMatchesSearch(NotificationItem item, String query) {
  return matchesSearchQuery(query, [
    item.message,
    item.meetingNo,
    item.taskNo,
    item.expectedDate,
    item.remainingDays,
    item.notificationDate,
    item.isRead ? '已读' : '未读',
  ]);
}
