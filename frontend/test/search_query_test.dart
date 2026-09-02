import 'package:flutter_test/flutter_test.dart';
import 'package:hyrwbz_frontend/models.dart';
import 'package:hyrwbz_frontend/notification_model.dart';
import 'package:hyrwbz_frontend/notification_search.dart';
import 'package:hyrwbz_frontend/search_query.dart';
import 'package:hyrwbz_frontend/task_search.dart';

void main() {
  test('search query uses AND terms, quoted phrases and exclusions', () {
    const values = ['工程部', '张三', '计划 完成'];
    expect(matchesSearchQuery('工程 张三', values), isTrue);
    expect(matchesSearchQuery('工程 李四', values), isFalse);
    expect(matchesSearchQuery('"计划 完成"', values), isTrue);
    expect(matchesSearchQuery('工程 -张三', values), isFalse);
    expect(matchesSearchQuery('工程 -李四', values), isTrue);
    expect(matchesSearchQuery('ZHANG', const ['zhang san']), isTrue);
  });

  test('task search covers task fields and delay history', () {
    final task = Task(
      id: 1,
      meetingNo: '纪要〔2026〕8号',
      taskNo: 3,
      taskDesc: '完成设备验收',
      dept: '工程部',
      owner: '张三',
      requiredDate: '2026/09/08',
      actualDate: '进行中',
      remark: '等待材料',
      hasAttachment: true,
      delays: [
        Delay(
          id: 1,
          taskId: 1,
          meetingNo: '纪要〔2026〕8号',
          taskNo: 3,
          delayDate: '2026/09/10',
          delayReason: '天气原因',
          createdAt: '',
        ),
      ],
    );

    expect(taskMatchesSearch(task, '工程 张三'), isTrue);
    expect(taskMatchesSearch(task, '2026/09/10 天气'), isTrue);
    expect(taskMatchesSearch(task, '有附件 -已完成'), isTrue);
    expect(taskMatchesSearch(task, '李四'), isFalse);
  });

  test('notification search covers message, task, date and read state', () {
    const item = NotificationItem(
      id: 1,
      taskId: 9,
      meetingNo: '纪要〔2026〕9号',
      taskNo: 2,
      expectedDate: '2026-09-03',
      remainingDays: 1,
      message: '距期望完成时间1天。',
      notificationDate: '2026-09-02',
      isRead: false,
    );

    expect(notificationMatchesSearch(item, '纪要 1天'), isTrue);
    expect(notificationMatchesSearch(item, '未读 2026-09-03'), isTrue);
    expect(notificationMatchesSearch(item, '-未读'), isFalse);
  });
}
