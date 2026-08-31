import 'package:flutter/material.dart';
import '../models.dart';
import 'date_picker_dialog.dart';

class FilterScreen extends StatefulWidget {
  final FilterReq initial;
  const FilterScreen({super.key, this.initial = const FilterReq()});

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  late final TextEditingController _meeting;
  late final TextEditingController _taskNo;
  late final TextEditingController _dept;
  late final TextEditingController _owner;
  late final TextEditingController _delayIndex;
  late DateRangeField _required;
  late DateRangeField _actual;
  late DateRangeField _delay;

  @override
  void initState() {
    super.initState();
    _meeting = TextEditingController(text: widget.initial.meetingNo ?? '');
    _taskNo = TextEditingController(text: widget.initial.taskNo?.toString() ?? '');
    _dept = TextEditingController(text: widget.initial.dept ?? '');
    _owner = TextEditingController(text: widget.initial.owner ?? '');
    _delayIndex = TextEditingController(text: widget.initial.delayIndex?.toString() ?? '');
    _required = DateRangeField(
      initialFrom: widget.initial.requiredDateFrom,
      initialTo: widget.initial.requiredDateTo,
      label: '要求完成时间',
    );
    _actual = DateRangeField(
      initialFrom: widget.initial.actualDateFrom,
      initialTo: widget.initial.actualDateTo,
      label: '实际完成时间',
    );
    _delay = DateRangeField(
      initialFrom: widget.initial.delayDateFrom,
      initialTo: widget.initial.delayDateTo,
      label: '延期时间',
    );
  }

  @override
  void dispose() {
    _meeting.dispose();
    _taskNo.dispose();
    _dept.dispose();
    _owner.dispose();
    _delayIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('统计筛选'),
      content: SizedBox(
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _textField(_meeting, '会议号', width: 180),
                  _textField(_taskNo, '任务号', width: 100, isNum: true),
                  _textField(_dept, '责任部门', width: 180),
                  _textField(_owner, '责任人', width: 120),
                  _textField(_delayIndex, '延期次数>=', width: 100, isNum: true),
                ],
              ),
              const Divider(height: 24),
              _required,
              const SizedBox(height: 8),
              _actual,
              const SizedBox(height: 8),
              _delay,
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, const FilterReq()),
          child: const Text('清除'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            int? tn;
            if (_taskNo.text.isNotEmpty) tn = int.tryParse(_taskNo.text);
            int? di;
            if (_delayIndex.text.isNotEmpty) di = int.tryParse(_delayIndex.text);
            final f = FilterReq(
              meetingNo: _meeting.text.isEmpty ? null : _meeting.text,
              taskNo: tn,
              dept: _dept.text.isEmpty ? null : _dept.text,
              owner: _owner.text.isEmpty ? null : _owner.text,
              requiredDateFrom: _required.from,
              requiredDateTo: _required.to,
              actualDateFrom: _actual.from,
              actualDateTo: _actual.to,
              delayDateFrom: _delay.from,
              delayDateTo: _delay.to,
              delayIndex: di,
            );
            Navigator.pop(context, f);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _textField(TextEditingController c, String label,
      {double width = 150, bool isNum = false}) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: c,
        keyboardType: isNum ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }
}
