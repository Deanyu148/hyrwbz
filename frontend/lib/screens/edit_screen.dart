import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';
import 'date_picker_dialog.dart';

class EditScreen extends StatefulWidget {
  final Task task;
  const EditScreen({super.key, required this.task});

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  late final TextEditingController _meeting;
  late final TextEditingController _taskNo;
  late final TextEditingController _taskDesc;
  late final TextEditingController _dept;
  late final TextEditingController _owner;
  late final TextEditingController _required;
  late final TextEditingController _actual;
  late final TextEditingController _remark;
  bool _lock = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _meeting = TextEditingController(text: t.meetingNo);
    _taskNo = TextEditingController(text: t.taskNo.toString());
    _taskDesc = TextEditingController(text: t.taskDesc);
    _dept = TextEditingController(text: t.dept);
    _owner = TextEditingController(text: t.owner);
    _required = TextEditingController(text: t.requiredDate);
    _actual = TextEditingController(text: t.actualDate);
    _remark = TextEditingController(text: t.remark);
    _loadLock();
  }

  @override
  void dispose() {
    _meeting.dispose();
    _taskNo.dispose();
    _taskDesc.dispose();
    _dept.dispose();
    _owner.dispose();
    _required.dispose();
    _actual.dispose();
    _remark.dispose();
    super.dispose();
  }

  Future<void> _loadLock() async {
    final l = await Api.getLockedMeeting();
    setState(() => _lock = l == widget.task.meetingNo);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final t = Task(
        meetingNo: _meeting.text.trim(),
        taskNo: int.tryParse(_taskNo.text) ?? 1,
        taskDesc: _taskDesc.text,
        dept: _dept.text,
        owner: _owner.text,
        requiredDate: _required.text,
        actualDate: _actual.text,
        remark: _remark.text,
      );
      await Api.updateTask(widget.task.id!, t);
      if (_lock) {
        await Api.setLockedMeeting(_meeting.text.trim());
      } else {
        // 如果当前锁定的就是这个会议号，主动解锁
        final l = await Api.getLockedMeeting();
        if (l == _meeting.text.trim()) {
          await Api.setLockedMeeting('');
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    }
    setState(() => _saving = false);
  }

  Future<void> _pick(TextEditingController c, String title) async {
    final v = await showDialog<String>(
      context: context,
      builder: (_) => DatePickerDialogWidget(initial: c.text, title: title),
    );
    if (v != null) setState(() => c.text = v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('编辑条目 #${widget.task.id}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _meeting,
                      decoration: const InputDecoration(labelText: '会议号'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _taskNo,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '任务号'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _taskDesc,
                decoration: const InputDecoration(labelText: '任务说明'),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: TextField(controller: _dept, decoration: const InputDecoration(labelText: '责任部门'))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: _owner, decoration: const InputDecoration(labelText: '责任人'))),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _required,
                      decoration: const InputDecoration(labelText: '要求完成时间'),
                      onTap: () => _pick(_required, '要求完成时间'),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.calendar_month), onPressed: () => _pick(_required, '要求完成时间')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _actual,
                      decoration: const InputDecoration(labelText: '实际完成时间'),
                      onTap: () => _pick(_actual, '实际完成时间'),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.calendar_month), onPressed: () => _pick(_actual, '实际完成时间')),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _remark,
                decoration: const InputDecoration(labelText: '说明及备注'),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _lock,
                onChanged: (v) => setState(() => _lock = v ?? false),
                title: const Text('锁定当前会议号'),
                subtitle: const Text('锁定后，下一次添加条目自动填入此会议号，直至主动取消'),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
