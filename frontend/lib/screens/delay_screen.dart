import 'package:flutter/material.dart';
import '../api.dart';
import '../app_widgets.dart';
import '../models.dart';
import 'date_picker_dialog.dart';

class DelayScreen extends StatefulWidget {
  final Task task;
  const DelayScreen({super.key, required this.task});

  @override
  State<DelayScreen> createState() => _DelayScreenState();
}

class _DelayScreenState extends State<DelayScreen> {
  List<Delay> _delays = [];
  bool _loading = true;
  late TextEditingController _date;
  late TextEditingController _reason;

  @override
  void initState() {
    super.initState();
    _date = TextEditingController();
    _reason = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _date.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final delays = await Api.listDelays(widget.task.id!);
      if (!mounted) return;
      setState(() {
        _delays = delays;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast('加载延期失败: $error');
    }
  }

  void _toast(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _add() async {
    if (_date.text.isEmpty) {
      _toast('请输入延期日期');
      return;
    }
    try {
      final d = Delay(
        id: 0,
        taskId: widget.task.id!,
        meetingNo: widget.task.meetingNo,
        taskNo: widget.task.taskNo,
        delayDate: _date.text,
        delayReason: _reason.text,
        createdAt: '',
      );
      await Api.createDelay(widget.task.id!, d);
      _date.clear();
      _reason.clear();
      await _load();
    } catch (e) {
      _toast('添加失败: $e');
    }
  }

  Future<void> _del(Delay d) async {
    try {
      await Api.deleteDelay(d.id);
      await _load();
    } catch (e) {
      _toast('删除失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: AppSectionTitle(
        icon: Icons.more_time_rounded,
        title: '延期记录',
        subtitle: '${widget.task.meetingNo} / ${widget.task.taskNo}',
      ),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _date,
                    decoration: const InputDecoration(labelText: '延期日期/状态'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.calendar_month),
                  onPressed: () async {
                    final v = await showDialog<String>(
                      context: context,
                      builder: (_) => DatePickerDialogWidget(initial: _date.text, title: '延期日期'),
                    );
                    if (v != null) setState(() => _date.text = v);
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: _reason,
                    decoration: const InputDecoration(labelText: '延期理由'),
                  ),
                ),
                FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('添加')),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())
            else
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _delays.length,
                    itemBuilder: (_, i) {
                      final d = _delays[_delays.length - 1 - i];
                      return ListTile(
                        leading: CircleAvatar(child: Text('${_delays.length - i}')),
                        title: Text(d.delayDate),
                        subtitle: Text(d.delayReason),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _del(d),
                        ),
                      );
                    },
                  ),
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: Text('最多保留 20 条，当前 ${_delays.length} 条', style: const TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ],
    );
  }
}
