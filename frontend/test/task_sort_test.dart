import 'package:flutter_test/flutter_test.dart';
import 'package:hyrwbz_frontend/models.dart';
import 'package:hyrwbz_frontend/task_sort.dart';

Task task({
  required String meetingNo,
  required int taskNo,
  String dept = '',
  String owner = '',
  String requiredDate = '',
  String actualDate = '',
  String delayDate = '',
  int id = 0,
}) {
  return Task(
    id: id,
    meetingNo: meetingNo,
    taskNo: taskNo,
    taskDesc: '',
    dept: dept,
    owner: owner,
    requiredDate: requiredDate,
    actualDate: actualDate,
    remark: '',
    delays: delayDate.isEmpty
        ? const []
        : [
            Delay(
              id: id,
              taskId: id,
              meetingNo: meetingNo,
              taskNo: taskNo,
              delayDate: delayDate,
              delayReason: '',
              createdAt: '',
            ),
          ],
  );
}

void main() {
  test('meeting numbers use Chinese pinyin and natural numeric order', () {
    final tasks = [
      task(meetingNo: '纪要〔2026〕10号', taskNo: 1, id: 1),
      task(meetingNo: '纪要〔2025〕9号', taskNo: 1, id: 2),
      task(meetingNo: '纪要〔2026〕2号', taskNo: 1, id: 3),
    ];

    final sorted = sortTasks(
      tasks,
      column: TaskSortColumn.meetingNo,
      ascending: true,
    );
    expect(
      sorted.map((value) => value.meetingNo).toList(),
      ['纪要〔2025〕9号', '纪要〔2026〕2号', '纪要〔2026〕10号'],
    );
  });

  test('dates sort chronologically and empty values come first', () {
    final tasks = [
      task(meetingNo: '纪要〔2026〕1号', taskNo: 1, requiredDate: '2026/10/01', id: 1),
      task(meetingNo: '纪要〔2026〕2号', taskNo: 1, requiredDate: '', id: 2),
      task(meetingNo: '纪要〔2026〕3号', taskNo: 1, requiredDate: '2026/02/01', id: 3),
    ];

    final sorted = sortTasks(
      tasks,
      column: TaskSortColumn.requiredDate,
      ascending: true,
    );
    expect(sorted.map((value) => value.requiredDate).toList(), ['', '2026/02/01', '2026/10/01']);
  });

  test('descending order is the reverse of ascending order', () {
    final tasks = [
      task(meetingNo: '纪要〔2026〕1号', taskNo: 3, dept: '技术部', id: 1),
      task(meetingNo: '纪要〔2026〕2号', taskNo: 1, dept: '工程部', id: 2),
      task(meetingNo: '纪要〔2026〕3号', taskNo: 2, dept: '质量部', id: 3),
    ];

    final ascending = sortTasks(
      tasks,
      column: TaskSortColumn.dept,
      ascending: true,
    );
    final descending = sortTasks(
      tasks,
      column: TaskSortColumn.dept,
      ascending: false,
    );
    expect(
      descending.map((value) => value.id).toList(),
      ascending.map((value) => value.id).toList().reversed.toList(),
    );
  });

  test('unsupported table columns do not have sort mappings', () {
    expect(taskSortColumnForIndex(3), isNull); // 任务内容
    expect(taskSortColumnForIndex(9), isNull); // 延期理由
    expect(taskSortColumnForIndex(10), isNull); // 附件
    expect(taskSortColumnForIndex(11), isNull); // 备注
    expect(taskSortColumnForIndex(1), TaskSortColumn.meetingNo);
  });

  test('sequence sorting follows the current displayed order', () {
    final tasks = [
      task(meetingNo: '纪要〔2026〕2号', taskNo: 1, id: 2),
      task(meetingNo: '纪要〔2026〕1号', taskNo: 1, id: 1),
    ];
    final ascending = sortTasks(
      tasks,
      column: TaskSortColumn.sequence,
      ascending: true,
    );
    final descending = sortTasks(
      tasks,
      column: TaskSortColumn.sequence,
      ascending: false,
    );
    expect(ascending.map((value) => value.id).toList(), [2, 1]);
    expect(descending.map((value) => value.id).toList(), [1, 2]);
  });
}
