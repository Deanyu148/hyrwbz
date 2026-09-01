
import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../api.dart';
import '../models.dart';
import '../table_layout.dart';
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
    '责任人', '计划完成时间', '实际完成时间', '最后延期', '延期理由', '附件', '备注',
  ];
  List<Task> _tasks = [];
  bool _loading = true;
  FilterReq _filter = const FilterReq();
  String _filterSummary = '';
  bool _backendOk = true;
  final List<Task> _selected = [];

  @override
  void initState() {
    super.initState();
    _ensureBackend();
  }


  Future<void> _ensureBackend() async {
    final ok = await Api.health();
    setState(() {
      _backendOk = ok;
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
    if (f.hasAttachment != null) {
      p.add(f.hasAttachment! ? '有附件' : '无附件');
    }
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

  Future<void> _exportCsv() async {
    String? outDir;
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: '选择导出目录（取消则使用默认目录）');
    outDir = dir;
    try {
      final res = await Api.exportCsv(_filter, outDir);
      _toast('已导出: ${res['path']}');
    } catch (e) {
      _toast('导出失败: $e');
    }
  }

  Future<void> _importCsv() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (res == null || res.files.single.path == null) return;
    final path = res.files.single.path!;
    final bytes = await File(path).readAsBytes();
    try {
      final result = await Api.importCsv(bytes, res.files.single.name);
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

  // ---- Responsive table builders ----

  Widget _buildHeaderRow(List<double> widths) {
    return Container(
      color: Colors.grey[200],
      child: Row(
        children: [
          SizedBox(
            width: taskSelectionWidth,
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
            _buildHeaderCell(widths[i], _columnLabels[i]),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(double width, String label) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildDataRow(int index, Task t, List<double> widths) {
    final lastDelay = t.delays.isNotEmpty ? t.delays.last : null;
    final isSelected = _selected.any((x) => x.id == t.id);
    final cellTexts = [
      '${index + 1}', t.meetingNo, t.taskNo.toString(), t.taskDesc, t.dept,
      t.owner, t.requiredDate, t.actualDate, lastDelay?.delayDate ?? '',
      lastDelay?.delayReason ?? '', t.hasAttachment ? '有' : '无', t.remark,
    ];
    return Container(
      color: isSelected ? Colors.blue.withValues(alpha: 0.1) : null,
      child: Row(
        children: [
          SizedBox(
            width: taskSelectionWidth,
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
            SizedBox(
              width: widths[i],
              child: GestureDetector(
                onTap: () => _viewTask(t),
                onDoubleTap: () => _editTask(t),
                onLongPress: () => _viewTask(t),
                child: Tooltip(
                  message: cellTexts[i],
                  waitDuration: const Duration(milliseconds: 500),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Text(cellTexts[i], maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }


  Widget _buildActionBar() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 1050;
        Widget action(IconData icon, String label, VoidCallback callback, {bool primary = false}) {
          if (compact) {
            return IconButton(icon: Icon(icon), tooltip: label, onPressed: callback);
          }
          return primary
              ? FilledButton.icon(onPressed: callback, icon: Icon(icon), label: Text(label))
              : OutlinedButton.icon(onPressed: callback, icon: Icon(icon), label: Text(label));
        }

        return Row(
          children: [
            action(Icons.add, '添加条目', _addTask, primary: true),
            const SizedBox(width: 6),
            action(Icons.delete_outline, '删除条目', _deleteSelected),
            const SizedBox(width: 6),
            action(Icons.more_time, '添加延期', _addDelay),
            const SizedBox(width: 6),
            action(Icons.history_toggle_off, '查看/删除延期', _delDelay),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _filterSummary.isEmpty ? '' : '筛选: $_filterSummary',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(width: 8),
            Text('共 ${_tasks.length} 条', style: const TextStyle(color: Colors.grey)),
          ],
        );
      },
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
          _ClickMenuButton(
            icon: Icons.file_download,
            tooltip: '导出',
            items: [
              _MenuEntry(icon: Icons.table_view, label: '导出Excel', onTap: _exportExcel),
              _MenuEntry(icon: Icons.text_snippet, label: '导出CSV', onTap: _exportCsv),
              _MenuEntry(icon: Icons.storage, label: '导出数据库', onTap: _exportDb),
            ],
          ),
          _ClickMenuButton(
            icon: Icons.upload_file,
            tooltip: '导入',
            items: [
              _MenuEntry(icon: Icons.table_view, label: '导入Excel', onTap: _importExcel),
              _MenuEntry(icon: Icons.text_snippet, label: '导入CSV', onTap: _importCsv),
              _MenuEntry(icon: Icons.storage, label: '导入数据库', onTap: _importDb),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.black.withValues(alpha: 0.04),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: _buildActionBar(),
          ),
          if (!_backendOk)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('本地服务未连接，请确认 hyrwbz_backend.exe 位于应用目录。', style: TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _tasks.isEmpty
                    ? const Center(child: Text('暂无数据，点击「添加条目」开始'))
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final widths = computeTaskColumnWidths(constraints.maxWidth);
                          return Column(
                            children: [
                              _buildHeaderRow(widths),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: _tasks.length,
                                  itemBuilder: (context, index) =>
                                      _buildDataRow(index, _tasks[index], widths),
                                ),
                              ),
                            ],
                          );
                        },
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
                  decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
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
              _row('附件', task.hasAttachment ? '有' : '无'),
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

/// 菜单项数据
class _MenuEntry {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuEntry({required this.icon, required this.label, required this.onTap});
}

/// 仅点击打开的下拉菜单，鼠标悬停不会改变菜单状态。
class _ClickMenuButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final List<_MenuEntry> items;
  const _ClickMenuButton({required this.icon, required this.tooltip, required this.items});

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final item in items)
          MenuItemButton(
            leadingIcon: Icon(item.icon, size: 18),
            onPressed: item.onTap,
            child: Text(item.label),
          ),
      ],
      builder: (context, controller, child) => IconButton(
        icon: Icon(icon),
        tooltip: tooltip,
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}
