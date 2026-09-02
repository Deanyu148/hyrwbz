import 'package:flutter_test/flutter_test.dart';
import 'package:hyrwbz_frontend/models.dart';
import 'package:hyrwbz_frontend/snapshot_filter.dart';

Task task({
  required int id,
  required int taskNo,
  required String meetingNo,
  required String requiredDate,
  String dept = '',
  String owner = '',
  bool hasAttachment = false,
  List<Delay> delays = const [],
}) => Task(
      id: id,
      meetingNo: meetingNo,
      taskNo: taskNo,
      taskDesc: '任务$id',
      dept: dept,
      owner: owner,
      requiredDate: requiredDate,
      actualDate: '进行中',
      remark: '',
      hasAttachment: hasAttachment,
      delays: delays,
    );

void main() {
  test('snapshot filtering supports structured conditions and multiple values', () {
    final tasks = [
      task(
        id: 1,
        taskNo: 1,
        meetingNo: '纪要〔2026〕1号',
        requiredDate: '2026/09/10',
        dept: '工程部',
        owner: '张三',
        hasAttachment: true,
        delays: [
          Delay(
            id: 1,
            taskId: 1,
            meetingNo: '纪要〔2026〕1号',
            taskNo: 1,
            delayDate: '2026/09/15',
            delayReason: '等待材料',
            createdAt: '',
          ),
        ],
      ),
      task(
        id: 2,
        taskNo: 2,
        meetingNo: '纪要〔2026〕2号',
        requiredDate: '2026/09/20',
        dept: '综合部',
        owner: '李四',
      ),
    ];

    final result = filterSnapshotTasks(
      tasks,
      const FilterReq(
        dept: '财务部,工程部',
        owner: '王五,张三',
        delayDateFrom: '2026/09/10',
        delayDateTo: '2026/09/20',
        delayIndex: 1,
        hasAttachment: true,
      ),
    );
    expect(result.map((value) => value.id), [1]);
  });
}
