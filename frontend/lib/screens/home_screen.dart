import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api.dart';
import '../models.dart';
import 'edit_screen.dart';
import 'delay_screen.dart';
import 'filter_screen.dart';
import 'date_picker_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _columnLabels = [
    '序号', '会议纪要号', '任务序号', '任务内容', '责任部门',
    '责任人', '计划完成时间', '实际完成时间', '最后延期', '延期理由', '备注',
  ];
  static const _defaultWidths = [
    60.0, 120.0, 80.0, 200.0, 100.0, 80.0, 120.0, 120.0, 120.0, 150.0, 150.0
  ];

  List<Task> _tasks = [];
  bool _loading = true;
  FilterReq _filter = const FilterReq();
  String _filterSummary = '';
  bool _backendOk = true;
  bool _checking = false;
  final List<Task> _selected = [];
  List<double> _colWidths = List.from(_defaultWidths);

  @override
  void initState() {
    super.initState();
    _loadColWidths();
    _ensureBackend();
  }

  Future<void> _loadColWidths() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('col_widths');
    if (saved != null) {
      try {
        final list = (jsonDecode(saved) as List).map((e) => (e as num).toDouble()).toList();
        if (list.length == _defaultWidths.length) {
          setState(() => _colWidths = list);
        }
      } catch (_) {}
    }
  }

  Future<void> _saveColWidths() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('col_widths', jsonEncode(_colWidths));
  }

  Future<void> _ensureBackend() async {
    setState(() => _checking = true);
    final ok = await Api.health();
    setState(() {
      _backendOk = ok;
      _checking = false;
    });
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('无法连接后端服务。请确保已启动后端程序。'),
        duration: Duration(seconds: 6),
      ));
      return;
    }
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      _tasks = await Api.listTasks(_filter);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加载失败: $e')));
    }
    setState(() => _loading = false);
  }

  void _toast(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _addTask() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddTaskDialog(),
    );
    if (res == true) {
      await _reload();
    }
  }

  Future<void> _deleteSelected() async {
    final sel = _selected;
    if (sel.isEmpty) {
      _toast('请先选择要删除的条目');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('将删除选中的 ${sel.length} 条记录及其延期记录，确定？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('确定删除')),
        ],
      ),
    );
    if (ok != true) return;
    for (final t in sel) {
      try {
        await Api.deleteTask(t.id!);
      } catch (e) {
        _toast('删除失败 ${t.meetingNo}/${t.taskNo}: $e');
      }
    }
    _selected.clear();
    await _reload();
  }

  Future<void> _addDelay() async {
    final sel = _selected;
    if (sel.length != 1) {
      _toast('请选中一条条目后添加延期');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => DelayScreen(task: sel.first),
    );
    _selected.clear();
    await _reload();
  }

  Future<void> _delDelay() async {
    final sel = _selected;
    if (sel.length != 1) {
      _toast('请选中一条条目查看/删除延期');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => DelayScreen(task: sel.first),
    );
    _selected.clear();
    await _reload();
  }

  Future<void> _openFilter() async {
    final res = await showDialog<FilterReq>(
      context: context,
      builder: (_) => FilterScreen(initial: _filter),
    );
    if (res == null) return;
    setState(() {
      _filter = res;
      _filterSummary = _buildSummary(res);
    });
    await _reload();
  }

  String _buildSummary(FilterReq f) {
    if (f.isEmpty) return '';
    final p = <String>[];
    if (f.meetingNo != null) p.add('会议纪要号~${f.meetingNo}');
    if (f.taskNo != null) p.add('任务序号=${f.taskNo}');
    if (f.dept != null) p.add('部门~${f.dept}');
    if (f.owner != null) p.add('责任人~${f.owner}');
    if (f.requiredDateFrom != null || f.requiredDateTo != null) {
      p.add('计划完成[${f.requiredDateFrom ?? ''}~${f.requiredDateTo ?? ''}]');
    }
    if (f.actualDateFrom != null || f.actualDateTo != null) {
      p.add('实际时间[${f.actualDateFrom ?? ''}~${f.actualDateTo ?? ''}]');
    }
    if (f.delayDateFrom != null || f.delayDateTo != null) {
      p.add('延期时间[${f.delayDateFrom ?? ''}~${f.delayDateTo ?? ''}]');
    }
    if (f.delayIndex != null) p.add('延期次数>=${f.delayIndex}');
    return p.join(', ');
  }

  Future<void> _viewTask(Task t) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ViewTaskDialog(task: t),
    );
  }

  Future<void> _editTask(Task t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => EditScreen(task: t),
    );
    if (ok == true) {
      await _reload();
    }
  }

  Future<void> _exportExcel() async {
    String? outDir;
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: '选择导出目录（取消则使用默认目录）');
    outDir = dir;
    try {
      final res = await Api.exportExcel(_filter, outDir);
      _toast('已导出: ${res['path']}（共 ${(res['sheets'] as List).length} 个 Sheet）');
    } catch (e) {
      _toast('导出失败: $e');
    }
  }

  Future<void> _importExcel() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );
    if (res == null || res.files.single.path == null) return;
    final path = res.files.single.path!;
    final bytes = await File(path).readAsBytes();
    try {
      final result = await Api.importExcel(bytes, res.files.single.name);
      _toast('导入成功: 共导入 ${result['imported']} 条记录');
      await _reload();
    } catch (e) {
      _toast('导入失败: $e');
    }
  }

  Future<void> _saveSnapshot() async {
    try {
      await Api.createSnapshot();
      _toast('历史快照已保存（最多保留 5 份）');
    } catch (e) {
      _toast('保存快照失败: $e');
    }
  }

  Future<void> _exportDb() async {
    try {
      final p = await Api.exportDbFile();
      _toast('数据库已导出: $p');
    } catch (e) {
      _toast('导出失败: $e');
    }
  }

  Future<void> _importDb() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db', 'sqlite'],
    );
    if (res == null || res.files.single.path == null) return;
    final path = res.files.single.path!;
    final bytes = await File(path).readAsBytes();
    try {
      await Api.importDbFile(bytes, res.files.single.name);
      _toast('数据库导入成功');
      await _reload();
    } catch (e) {
      _toast('导入失败: $e');
    }
  }

  // ---- Custom resizable table builders ----

  Widget _buildHeaderRow() {
    return Container(
      color: Colors.grey[200],
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Checkbox(
              value: _tasks.isNotEmpty && _selected.length == _tasks.length,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selected.clear();
                    _selected.addAll(_tasks);
                  } else {
                    _selected.clear();
                  }
                });
              },
            ),
          ),
          for (int i = 0; i < _columnLabels.length; i++)
            _buildHeaderCell(i, _columnLabels[i]),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(int index, String label) {
    return SizedBox(
      width: _colWidths[index],
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[400]!),
            ),
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    _colWidths[index] = (_colWidths[index] + details.delta.dx).clamp(40.0, 500.0);
                  });
                },
                onHorizontalDragEnd: (_) => _saveColWidths(),
                child: Container(
                  width: 6,
                  color: Colors.transparent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataRow(int index, Task t) {
    final lastDelay = t.delays.isNotEmpty ? t.delays.last : null;
    final isSelected = _selected.any((x) => x.id == t.id);
    final cellTexts = [
      '${index + 1}',
      t.meetingNo,
      t.taskNo.toString(),
      t.taskDesc,
      t.dept,
      t.owner,
      t.requiredDate,
      t.actualDate,
      lastDelay?.delayDate ?? '',
      lastDelay?.delayReason ?? '',
      t.remark,
    ];
    return Container(
      color: isSelected ? Colors.blue.withOpacity(0.1) : null,
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Checkbox(
              value: isSelected,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selected.add(t);
                  } else {
                    _selected.removeWhere((x) => x.id == t.id);
                  }
                });
              },
            ),
          ),
          for (int i = 0; i < cellTexts.length; i++)
            GestureDetector(
              onTap: () => _viewTask(t),
              onDoubleTap: () => _editTask(t),
              onLongPress: () => _viewTask(t),
              child: Container(
                width: _colWidths[i],
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Text(cellTexts[i]),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('会议任务管理跟踪系统'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _reload, tooltip: '刷新'),
          IconButton(icon: const Icon(Icons.filter_alt), onPressed: _openFilter, tooltip: '统计筛选'),
          IconButton(icon: const Icon(Icons.history), onPressed: _saveSnapshot, tooltip: '保存历史快照'),
          IconButton(icon: const Icon(Icons.file_download), onPressed: _exportExcel, tooltip: '导出Excel'),
          IconButton(icon: const Icon(Icons.upload_file), onPressed: _importExcel, tooltip: '导入Excel'),
          IconButton(icon: const Icon(Icons.download), onPressed: _exportDb, tooltip: '导出数据库'),
          IconButton(icon: const Icon(Icons.upload), onPressed: _importDb, tooltip: '导入数据库'),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.black.withOpacity(0.04),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                FilledButton.icon(onPressed: _addTask, icon: const Icon(Icons.add), label: const Text('添加条目')),
                const SizedBox(width: 8),
                OutlinedButton.icon(onPressed: _deleteSelected, icon: const Icon(Icons.delete_outline), label: const Text('删除条目')),
                const SizedBox(width: 8),
                OutlinedButton.icon(onPressed: _addDelay, icon: const Icon(Icons.more_time), label: const Text('添加延期')),
                const SizedBox(width: 8),
                OutlinedButton.icon(onPressed: _delDelay, icon: const Icon(Icons.history_toggle_off), label: const Text('查看/删除延期')),
                const SizedBox(width: 16),
                if (_filterSummary.isNotEmpty)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text('筛选: $_filterSummary', style: const TextStyle(color: Colors.grey)),
                    ),
                  )
                else
                  const Spacer(),
                Text('共 ${_tasks.length} 条', style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          if (!_backendOk)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('后端未连接，请在应用目录运行后端程序或检查端口。', style: TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _tasks.isEmpty
                    ? const Center(child: Text('暂无数据，点击「添加条目」开始'))
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              _buildHeaderRow(),
                              ..._tasks.asMap().entries.map((e) => _buildDataRow(e.key, e.value)),
                            ],
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _AddTaskDialog extends StatefulWidget {
  const _AddTaskDialog();
  @override
  State<_AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends State<_AddTaskDialog> {
  late final TextEditingController _meeting;
  late final TextEditingController _taskDesc;
  late final TextEditingController _dept;
  late final TextEditingController _owner;
  late final TextEditingController _required;
  late final TextEditingController _actual;
  late final TextEditingController _remark;
  String? _lockedMeeting;
  bool _saving = false;
  final List<_PendingFile> _pendingFiles = [];

  @override
  void initState() {
    super.initState();
    _meeting = TextEditingController();
    _taskDesc = TextEditingController();
    _dept = TextEditingController();
    _owner = TextEditingController();
    _required = TextEditingController();
    _actual = TextEditingController();
    _remark = TextEditingController();
    _loadLocked();
  }

  @override
  void dispose() {
    _meeting.dispose();
    _taskDesc.dispose();
    _dept.dispose();
    _owner.dispose();
    _required.dispose();
    _actual.dispose();
    _remark.dispose();
    super.dispose();
  }

  Future<void> _loadLocked() async {
    try {
      final l = await Api.getLockedMeeting();
      setState(() {
        _lockedMeeting = l;
        if (l != null && l.isNotEmpty) _meeting.text = l;
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    if (_meeting.text.isEmpty) {
      _toast('会议纪要号不能为空');
      return;
    }
    setState(() => _saving = true);
    try {
      final t = Task(
        meetingNo: _meeting.text.trim(),
        taskNo: 0,
        taskDesc: _taskDesc.text,
        dept: _dept.text,
        owner: _owner.text,
        requiredDate: _required.text,
        actualDate: _actual.text,
        remark: _remark.text,
      );
      final created = await Api.createTask(t);
      for (final pf in _pendingFiles) {
        try {
          await Api.uploadAttachment(created.id!, pf.bytes, pf.name);
        } catch (_) {}
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _toast('添加失败: $e');
    }
    setState(() => _saving = false);
  }

  void _toast(String s) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _pick(TextEditingController c, String title) async {
    final v = await showDialog<String>(
      context: context,
      builder: (_) => DatePickerDialogWidget(initial: c.text, title: title),
    );
    if (v != null) setState(() => c.text = v);
  }

  Future<void> _pickAttachment() async {
    final res = await FilePicker.platform.pickFiles();
    if (res == null || res.files.isEmpty) return;
    final file = res.files.first;
    if (file.path == null) return;
    final bytes = await File(file.path!).readAsBytes();
    setState(() {
      _pendingFiles.add(_PendingFile(name: file.name, bytes: bytes));
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加条目'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_lockedMeeting != null && _lockedMeeting!.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: Row(
                    children: [
                      const Icon(Icons.lock, size: 16),
                      const SizedBox(width: 6),
                      Expanded(child: Text('会议纪要号已自动填入（锁定：$_lockedMeeting）')),
                    ],
                  ),
                ),
              TextField(
                controller: _meeting,
                decoration: const InputDecoration(labelText: '会议纪要号 *'),
                enabled: _lockedMeeting == null || _lockedMeeting!.isEmpty,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _taskDesc,
                decoration: const InputDecoration(labelText: '任务内容'),
                maxLines: 3,
                minLines: 3,
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
                      decoration: const InputDecoration(labelText: '计划完成时间'),
                      onTap: () => _pick(_required, '计划完成时间'),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.calendar_month), onPressed: () => _pick(_required, '计划完成时间')),
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
              TextField(controller: _remark, decoration: const InputDecoration(labelText: '备注'), maxLines: 2),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('附件', style: TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    onPressed: _pickAttachment,
                    tooltip: '添加附件',
                  ),
                ],
              ),
              if (_pendingFiles.isEmpty)
                const Padding(padding: EdgeInsets.all(8), child: Text('暂无附件'))
              else
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _pendingFiles.length,
                    itemBuilder: (_, i) => ListTile(
                      leading: const Icon(Icons.attachment),
                      title: Text(_pendingFiles[i].name),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() => _pendingFiles.removeAt(i)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('添加')),
      ],
    );
  }
}

class _PendingFile {
  final String name;
  final Uint8List bytes;
  _PendingFile({required this.name, required this.bytes});
}

class _ViewTaskDialog extends StatelessWidget {
  final Task task;
  const _ViewTaskDialog({required this.task});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('条目详情 - ${task.meetingNo}/${task.taskNo}'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row('会议纪要号', task.meetingNo),
              _row('任务序号', task.taskNo.toString()),
              _row('任务内容', task.taskDesc),
              _row('责任部门', task.dept),
              _row('责任人', task.owner),
              _row('计划完成时间', task.requiredDate),
              _row('实际完成时间', task.actualDate),
              _row('备注', task.remark),
              const Divider(height: 24),
              Text('延期记录（共 ${task.delays.length} 条）',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (task.delays.isEmpty)
                const Text('无延期记录')
              else
                ...task.delays.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${e.key + 1}. '),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('延期${e.key + 1}: ${e.value.delayDate}'),
                            Text('理由${e.key + 1}: ${e.value.delayReason}'),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text('$label：')),
          Expanded(child: Text(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }
}
