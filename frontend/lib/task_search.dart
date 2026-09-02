import 'models.dart';
import 'search_query.dart';

bool taskMatchesSearch(Task task, String query) {
  return matchesSearchQuery(query, [
    task.meetingNo,
    task.taskNo,
    task.taskDesc,
    task.dept,
    task.owner,
    task.requiredDate,
    task.actualDate,
    task.remark,
    task.hasAttachment ? '有附件' : '无附件',
    for (final delay in task.delays) ...[
      delay.delayDate,
      delay.delayReason,
    ],
  ]);
}
