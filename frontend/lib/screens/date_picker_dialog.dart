import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// 日期选择对话框：同时提供日期选择框与手动键盘输入框，二者同步。
class DatePickerDialogWidget extends StatefulWidget {
  final String? initial;
  final String title;
  const DatePickerDialogWidget({super.key, this.initial, this.title = '选择日期'});

  @override
  State<DatePickerDialogWidget> createState() => _S();
}

class _S extends State<DatePickerDialogWidget> {
  late TextEditingController _ctrl;
  DateTime? _picked;

  @override
  void initState() {
    super.initState();
    final s = widget.initial ?? '';
    if (s.isNotEmpty) {
      try {
        _picked = DateFormat('yyyy/MM/dd').parseStrict(s);
      } catch (_) {
        _picked = null;
      }
    }
    _ctrl = TextEditingController(text: s);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _set(DateTime d) {
    setState(() {
      _picked = d;
      _ctrl.text = DateFormat('yyyy/MM/dd').format(d);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  decoration: const InputDecoration(
                    labelText: 'YYYY/MM/DD',
                    hintText: '2026/08/31',
                  ),
                  onChanged: (v) {
                    if (v.length == 10) {
                      try {
                        final d = DateFormat('yyyy/MM/dd').parseStrict(v);
                        setState(() => _picked = d);
                      } catch (_) {}
                    }
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.calendar_month),
                onPressed: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _picked ?? now,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) _set(d);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          CalendarDatePicker(
            initialDate: _picked ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
            onDateChanged: _set,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('取消')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.isEmpty ? null : _ctrl.text),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 起止日期选择行：两个输入框 + 两个日历按钮
class DateRangeField extends StatefulWidget {
  final String? initialFrom;
  final String? initialTo;
  final String label;
  const DateRangeField({super.key, this.initialFrom, this.initialTo, this.label = '日期范围'});

  @override
  State<DateRangeField> createState() => _DateRangeFieldState();
}

class _DateRangeFieldState extends State<DateRangeField> {
  late TextEditingController _from;
  late TextEditingController _to;

  @override
  void initState() {
    super.initState();
    _from = TextEditingController(text: widget.initialFrom ?? '');
    _to = TextEditingController(text: widget.initialTo ?? '');
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _pick(bool from) async {
    final v = await showDialog<String>(
      context: context,
      builder: (_) => DatePickerDialogWidget(
        initial: from ? _from.text : _to.text,
        title: from ? '开始日期' : '结束日期',
      ),
    );
    if (v == null) return;
    setState(() {
      if (from) {
        _from.text = v;
      } else {
        _to.text = v;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(widget.label)),
        SizedBox(
          width: 120,
          child: TextField(
            controller: _from,
            decoration: const InputDecoration(hintText: '开始'),
            onTap: () => _pick(true),
            readOnly: false,
          ),
        ),
        IconButton(icon: const Icon(Icons.date_range), onPressed: () => _pick(true)),
        const Text('~'),
        SizedBox(
          width: 120,
          child: TextField(
            controller: _to,
            decoration: const InputDecoration(hintText: '结束'),
            onTap: () => _pick(false),
            readOnly: false,
          ),
        ),
        IconButton(icon: const Icon(Icons.date_range), onPressed: () => _pick(false)),
      ],
    );
  }

  String? get from => _from.text.isEmpty ? null : _from.text;
  String? get to => _to.text.isEmpty ? null : _to.text;
}
