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
  late int _attachmentMode;
  // 保存 DateRangeField 的当前值
  String? _requiredFrom, _requiredTo;
  String? _actualFrom, _actualTo;
  String? _delayFrom, _delayTo;

  @override
  void initState() {
    super.initState();
    _meeting = TextEditingController(text: widget.initial.meetingNo ?? '');
    _taskNo = TextEditingController(text: widget.initial.taskNo?.toString() ?? '');
    _dept = TextEditingController(text: widget.initial.dept ?? '');
    _owner = TextEditingController(text: widget.initial.owner ?? '');
    _delayIndex = TextEditingController(text: widget.initial.delayIndex?.toString() ?? '');
    _attachmentMode = widget.initial.hasAttachment == null
        ? 0
        : widget.initial.hasAttachment!
            ? 1
            : 2;
    _requiredFrom = widget.initial.requiredDateFrom;
    _requiredTo = widget.initial.requiredDateTo;
    _actualFrom = widget.initial.actualDateFrom;
    _actualTo = widget.initial.actualDateTo;
    _delayFrom = widget.initial.delayDateFrom;
    _delayTo = widget.initial.delayDateTo;
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
    final dialogWidth = (MediaQuery.sizeOf(context).width - 48)
        .clamp(300.0, 700.0)
        .toDouble();
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      title: const Text('统计筛选'),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _textField(_meeting, '会议纪要号', width: 180),
                  _textField(_taskNo, '任务序号', width: 100, isNum: true),
                  _textField(_dept, '责任部门(逗号分隔)', width: 220),
                  _textField(_owner, '责任人(逗号分隔)', width: 180),
                  _textField(_delayIndex, '延期次数>=', width: 100, isNum: true),
                  SizedBox(
                    width: 150,
                    child: DropdownButtonFormField<int>(
                      value: _attachmentMode,
                      decoration: const InputDecoration(
                        labelText: '附件状态',
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('全部')),
                        DropdownMenuItem(value: 1, child: Text('有附件')),
                        DropdownMenuItem(value: 2, child: Text('无附件')),
                      ],
                      onChanged: (value) {
                        setState(() => _attachmentMode = value ?? 0);
                      },
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              DateRangeField(
                initialFrom: _requiredFrom,
                initialTo: _requiredTo,
                label: '计划完成时间',
                onChanged: (f, t) { _requiredFrom = f; _requiredTo = t; },
              ),
              const SizedBox(height: 8),
              DateRangeField(
                initialFrom: _actualFrom,
                initialTo: _actualTo,
                label: '实际完成时间',
                onChanged: (f, t) { _actualFrom = f; _actualTo = t; },
              ),
              const SizedBox(height: 8),
              DateRangeField(
                initialFrom: _delayFrom,
                initialTo: _delayTo,
                label: '延期时间',
                onChanged: (f, t) { _delayFrom = f; _delayTo = t; },
              ),
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
            final di = _delayIndex.text.trim().isEmpty
                ? null
                : int.tryParse(_delayIndex.text.trim());
            final f = FilterReq(
              meetingNo: _meeting.text.isEmpty ? null : _meeting.text,
              taskNo: tn,
              dept: _dept.text.isEmpty ? null : _dept.text,
              owner: _owner.text.isEmpty ? null : _owner.text,
              requiredDateFrom: _requiredFrom,
              requiredDateTo: _requiredTo,
              actualDateFrom: _actualFrom,
              actualDateTo: _actualTo,
              delayDateFrom: _delayFrom,
              delayDateTo: _delayTo,
              delayIndex: di,
              hasAttachment: _attachmentMode == 0
                  ? null
                  : _attachmentMode == 1,
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
