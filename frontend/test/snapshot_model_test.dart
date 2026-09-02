import 'package:flutter_test/flutter_test.dart';
import 'package:hyrwbz_frontend/models.dart';

void main() {
  test('snapshot models parse remarks, usage and read-only task payload', () {
    final info = SnapshotInfo.fromJson({
      'snapshot_id': 8,
      'saved_at': '2026-09-02 12:00:00',
      'remark': '月度检查前',
    });
    final result = SnapshotCreateResult.fromJson({
      'snapshot_id': 8,
      'used_count': 4,
    });
    final detail = SnapshotDetail.fromJson({
      'snapshot_id': 8,
      'saved_at': '2026-09-02 12:00:00',
      'remark': '月度检查前',
      'tasks': [
        {
          'id': 1,
          'meeting_no': '纪要〔2026〕1号',
          'task_no': 2,
          'task_desc': '快照任务',
          'dept': '工程部',
          'owner': '张三',
          'required_date': '2026/09/10',
          'actual_date': '进行中',
          'remark': '',
          'created_at': '',
          'updated_at': '',
          'has_attachment': false,
          'delays': const [],
        },
      ],
    });

    expect(info.remark, '月度检查前');
    expect(result.usedCount, 4);
    expect(detail.tasks.single.taskDesc, '快照任务');
  });
}
