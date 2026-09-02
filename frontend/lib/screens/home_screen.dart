
import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../api.dart';
import '../app_widgets.dart';
import '../input_formatters.dart';
import '../models.dart';
import '../notifications.dart';
import '../search_field.dart';
import '../task_search.dart';
import '../table_layout.dart';
import '../table_layout_store.dart';
import '../task_sort.dart';
import 'edit_screen.dart';
import 'delay_screen.dart';
import 'filter_screen.dart';
import 'snapshot_screen.dart';
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
  List<Task> _allTasks = [];
  List<Task> _tasks = [];
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  Set<int>? _searchTaskIds;
  int _searchRequest = 0;
  bool _searching = false;
  bool _loading = true;
  FilterReq _filter = const FilterReq();
  String _filterSummary = '';
  bool _backendOk = true;
  final Set<int> _selectedIds = <int>{};

  List<Task> get _selectedTasks => _allTasks
      .where((task) => task.id != null && _selectedIds.contains(task.id))
      .toList();
  List<double>? _columnWidths;
  List<double>? _savedColumnWidths;
  double? _tableAvailableWidth;
  TaskSortColumn _sortColumn = TaskSortColumn.meetingNo;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _savedColumnWidths = TaskColumnWidthStore.load();
    _ensureBackend();
  }

  @override
  void dispose() {
    _persistColumnWidths();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }


  Future<void> _ensureBackend() async {
    final ok = await Api.health();
    if (!mounted) return;
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
    if (mounted) setState(() => _loading = true);
    try {
      final tasks = await Api.listTasks(_filter);
      final query = _searchController.text.trim();
      final searchIds =
          query.isEmpty ? null : await Api.searchTaskIds(query);
      if (!mounted) return;
      setState(() {
        _allTasks = tasks;
        final validIds = tasks.where((task) => task.id != null).map((task) => task.id!).toSet();
        _selectedIds.removeWhere((id) => !validIds.contains(id));
        _searchTaskIds = searchIds;
        _searching = false;
        _rebuildVisibleTasks();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载失败: $error')),
      );
    }
  }

  void _rebuildVisibleTasks() {
    final query = _searchController.text.trim();
    final matched = query.isEmpty
        ? List<Task>.from(_allTasks)
        : _searchTaskIds == null
            ? _allTasks
                .where((task) => taskMatchesSearch(task, query))
                .toList()
            : _allTasks
                .where((task) => _searchTaskIds!.contains(task.id))
                .toList();
    _tasks = sortTasks(
      matched,
      column: _sortColumn,
      ascending: _sortAscending,
    );
  }

  void _searchTasks(String value) {
    _searchDebounce?.cancel();
    final request = ++_searchRequest;
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _searchTaskIds = null;
        _searching = false;
        _rebuildVisibleTasks();
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 240), () async {
      try {
        final ids = await Api.searchTaskIds(query);
        if (!mounted || request != _searchRequest ||
            _searchController.text.trim() != query) {
          return;
        }
        setState(() {
          _searchTaskIds = ids;
          _searching = false;
          _rebuildVisibleTasks();
        });
      } catch (_) {
        if (!mounted || request != _searchRequest) return;
        setState(() {
          // 索引服务异常时保留本地搜索兜底，不影响用户继续使用。
          _searchTaskIds = null;
          _searching = false;
          _rebuildVisibleTasks();
        });
      }
    });
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
    final sel = _selectedTasks;
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
    _selectedIds.clear();
    await _reload();
  }

  Future<void> _openDelayScreen(Task task) async {
    await showDialog<void>(
      context: context,
      builder: (_) => DelayScreen(task: task),
    );
    if (mounted) await _reload();
  }

  Future<void> _addDelay() async {
    final sel = _selectedTasks;
    if (sel.length != 1) {
      _toast('请选中一条条目后添加延期');
      return;
    }
    await _openDelayScreen(sel.first);
    _selectedIds.clear();
  }

  Future<void> _delDelay() async {
    final sel = _selectedTasks;
    if (sel.length != 1) {
      _toast('请选中一条条目查看/删除延期');
      return;
    }
    await _openDelayScreen(sel.first);
    _selectedIds.clear();
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
    if (f.expectedRemainingDays != null) {
      p.add('期望剩余天数<=${f.expectedRemainingDays}天');
    }
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

  Future<void> _openNotificationTask(int taskId) async {
    Task? task;
    for (final value in _tasks) {
      if (value.id == taskId) {
        task = value;
        break;
      }
    }
    if (task == null) {
      try {
        final tasks = await Api.listTasks(null);
        for (final value in tasks) {
          if (value.id == taskId) {
            task = value;
            break;
          }
        }
      } catch (error) {
        if (mounted) _toast('加载通知对应条目失败: $error');
        return;
      }
    }
    if (task != null && mounted) await _viewTask(task);
  }

  Future<void> _openNotificationScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationScreen(onOpenTask: _openNotificationTask),
      ),
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

  Future<bool?> _askImportRemarkMode() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('导入选项'),
        content: const Text(
          '是否将导入文件中的“备注”移动到数据库的“延期理由”？\n\n'
          '仅当该行填写了“延期时间”时才会移动；没有延期时间的备注仍保留在任务备注中。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消导入'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('是，移动'),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('否，保留备注'),
          ),
        ],
      ),
    );
  }

  Future<void> _importExcel() async {
    final moveRemarkToDelayReason = await _askImportRemarkMode();
    if (moveRemarkToDelayReason == null || !mounted) return;
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );
    if (res == null || res.files.single.path == null) return;
    final path = res.files.single.path!;
    final bytes = await File(path).readAsBytes();
    try {
      final result = await Api.importExcel(
        bytes,
        res.files.single.name,
        moveRemarkToDelayReason: moveRemarkToDelayReason,
      );
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
    final moveRemarkToDelayReason = await _askImportRemarkMode();
    if (moveRemarkToDelayReason == null || !mounted) return;
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (res == null || res.files.single.path == null) return;
    final path = res.files.single.path!;
    final bytes = await File(path).readAsBytes();
    try {
      final result = await Api.importCsv(
        bytes,
        res.files.single.name,
        moveRemarkToDelayReason: moveRemarkToDelayReason,
      );
      _toast('导入成功: 共导入 ${result['imported']} 条记录');
      await _reload();
    } catch (e) {
      _toast('导入失败: $e');
    }
  }

  Future<void> _saveSnapshot() async {
    final controller = TextEditingController();
    final request = await showDialog<_SnapshotSaveRequest>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const AppSectionTitle(
          icon: Icons.save_as_rounded,
          title: '保存历史快照',
          subtitle: '保存当前全部任务及延期数据',
        ),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
              labelText: '备注（可选）',
              hintText: '可填写本次快照的用途或说明，默认不填写',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(
              dialogContext,
              _SnapshotSaveRequest(controller.text.trim()),
            ),
            icon: const Icon(Icons.save_rounded),
            label: const Text('保存快照'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (request == null) return;
    try {
      final result = await Api.createSnapshot(
        request.remark.isEmpty ? null : request.remark,
      );
      if (!mounted) return;
      _toast(snapshotSavedMessage(result.usedCount));
    } catch (error) {
      if (mounted) _toast('保存快照失败: $error');
    }
  }

  Future<void> _viewSnapshots() async {
    List<SnapshotInfo> snapshots;
    try {
      snapshots = await Api.listSnapshots();
    } catch (error) {
      if (mounted) _toast('加载历史快照失败: $error');
      return;
    }
    if (!mounted) return;
    if (snapshots.isEmpty) {
      _toast('暂无历史快照（当前已经使用0份）');
      return;
    }
    final selected = await showDialog<SnapshotInfo>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const AppSectionTitle(
          icon: Icons.history_rounded,
          title: '选择历史快照',
          subtitle: '点击一份快照进入只读查看界面',
        ),
        content: SizedBox(
          width: 560,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: snapshots.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final snapshot = snapshots[index];
                return ListTile(
                  leading: CircleAvatar(child: Text('${index + 1}')),
                  title: Text(snapshot.savedAt),
                  subtitle: Text(
                    snapshot.remark.trim().isEmpty ? '无备注' : snapshot.remark,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(dialogContext, snapshot),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SnapshotScreen(snapshot: selected),
      ),
    );
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

  Future<void> _exportAllFiles() async {
    final outDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择导出目录（取消则使用默认目录）',
    );
    try {
      final path = await Api.exportAllFiles(outDir);
      _toast('数据库和附件已打包导出: $path');
    } catch (e) {
      _toast('导出所有文件失败: $e');
    }
  }

  Future<void> _importAllFiles() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (res == null || res.files.single.path == null) return;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('导入所有文件'),
        content: const Text('将使用 ZIP 中的数据库和附件替换当前数据，是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('继续导入'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final path = res.files.single.path!;
    final bytes = await File(path).readAsBytes();
    try {
      await Api.importAllFiles(bytes, res.files.single.name);
      _selectedIds.clear();
      _toast('数据库和附件导入成功');
      await _reload();
    } catch (e) {
      _toast('导入所有文件失败: $e');
    }
  }

  // ---- Responsive and resizable table builders ----

  List<double> _resolveColumnWidths(double availableWidth) {
    final widthChanged = _tableAvailableWidth == null ||
        (_tableAvailableWidth! - availableWidth).abs() > 0.01;
    if (_columnWidths == null || widthChanged) {
      _columnWidths = fitTaskColumnWidths(
        availableWidth,
        _columnWidths ?? _savedColumnWidths,
      );
      _savedColumnWidths = null;
      _tableAvailableWidth = availableWidth;
    }
    return _columnWidths!;
  }

  void _resizeColumn(int dividerIndex, double delta) {
    final widths = _columnWidths;
    final availableWidth = _tableAvailableWidth;
    if (widths == null || availableWidth == null || delta == 0) return;
    setState(() {
      _columnWidths = resizeTaskColumnWidths(
        widths,
        dividerIndex,
        delta,
        availableWidth,
      );
    });
  }

  void _persistColumnWidths() {
    final widths = _columnWidths;
    if (widths != null) TaskColumnWidthStore.saveSync(widths);
  }

  void _sortByTableIndex(int index) {
    final column = taskSortColumnForIndex(index);
    if (column == null) return;
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
      _rebuildVisibleTasks();
    });
  }

  Icon _sortIcon(int index) {
    final column = taskSortColumnForIndex(index);
    if (column == null) {
      return Icon(Icons.unfold_more, size: 16, color: Colors.grey.shade300);
    }
    final active = _sortColumn == column;
    return Icon(
      active
          ? (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
          : Icons.unfold_more,
      size: 16,
      color: active ? Theme.of(context).colorScheme.primary : Colors.grey,
    );
  }

  Widget _buildHeaderRow(List<double> widths) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: taskSelectionWidth,
            child: Checkbox(
              value: _tasks.isNotEmpty &&
                  _tasks.every((task) => _selectedIds.contains(task.id)),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedIds.clear();
                    _selectedIds.addAll(
                      _tasks.where((task) => task.id != null).map((task) => task.id!),
                    );
                  } else {
                    _selectedIds.clear();
                  }
                });
              },
            ),
          ),
          for (int i = 0; i < _columnLabels.length; i++)
            _buildHeaderCell(widths[i], _columnLabels[i], i),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(double width, String label, int index) {
    final sortable = taskSortColumnForIndex(index) != null;
    return SizedBox(
      width: width,
      child: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: sortable ? () => _sortByTableIndex(index) : null,
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  _sortIcon(index),
                ],
              ),
            ),
          ),
          if (index < _columnLabels.length - 1)
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: 9,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeLeftRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (details) =>
                      _resizeColumn(index, details.delta.dx),
                  onHorizontalDragEnd: (_) => _persistColumnWidths(),
                  onHorizontalDragCancel: _persistColumnWidths,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDataRow(int index, Task t, List<double> widths) {
    final lastDelay = t.delays.isNotEmpty ? t.delays.last : null;
    final isSelected = t.id != null && _selectedIds.contains(t.id);
    final cellTexts = [
      '${index + 1}', t.meetingNo, t.taskNo.toString(), t.taskDesc, t.dept,
      t.owner, t.requiredDate, t.actualDate, lastDelay?.delayDate ?? '',
      lastDelay?.delayReason ?? '', t.hasAttachment ? '有' : '无', t.remark,
    ];
    final scheme = Theme.of(context).colorScheme;
    final rowColor = isSelected
        ? scheme.primary.withValues(alpha: 0.10)
        : index.isOdd
            ? scheme.surfaceContainerLow.withValues(alpha: 0.55)
            : scheme.surface;
    return Container(
      decoration: BoxDecoration(
        color: rowColor,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: taskSelectionWidth,
            child: Checkbox(
              value: isSelected,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    if (t.id != null) _selectedIds.add(t.id!);
                  } else {
                    _selectedIds.remove(t.id);
                  }
                });
              },
            ),
          ),
          for (int i = 0; i < cellTexts.length; i++)
            Container(
              width: widths[i],
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: GestureDetector(
                onTap: () => _viewTask(t),
                onDoubleTap: () => i == 8 || i == 9
                    ? _openDelayScreen(t)
                    : _editTask(t),
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
        final scheme = Theme.of(context).colorScheme;
        Widget action(
          IconData icon,
          String label,
          VoidCallback callback, {
          bool primary = false,
        }) {
          if (compact) {
            return IconButton(
              icon: Icon(icon),
              tooltip: label,
              color: primary ? scheme.primary : scheme.onSurfaceVariant,
              onPressed: callback,
            );
          }
          return primary
              ? FilledButton.icon(
                  onPressed: callback,
                  icon: Icon(icon),
                  label: Text(label),
                )
              : OutlinedButton.icon(
                  onPressed: callback,
                  icon: Icon(icon),
                  label: Text(label),
                );
        }

        return Row(
          children: [
            action(Icons.add_rounded, '添加条目', _addTask, primary: true),
            const SizedBox(width: 8),
            action(Icons.delete_outline_rounded, '删除条目', _deleteSelected),
            const SizedBox(width: 8),
            action(Icons.more_time_rounded, '添加延期', _addDelay),
            const SizedBox(width: 8),
            action(Icons.history_toggle_off_rounded, '查看/删除延期', _delDelay),
            const SizedBox(width: 14),
            if (_filterSummary.isNotEmpty)
              Flexible(
                child: AppStatusPill(
                  icon: Icons.filter_alt_rounded,
                  label: _filterSummary,
                  color: scheme.secondary,
                ),
              )
            else
              const Spacer(),
            if (_filterSummary.isNotEmpty) const Spacer(),
            if (_selectedIds.isNotEmpty) ...[
              AppStatusPill(
                icon: Icons.check_circle_outline_rounded,
                label: '已选 ${_selectedIds.length} 条',
                color: scheme.tertiary,
              ),
              const SizedBox(width: 8),
            ],
            AppStatusPill(
              icon: Icons.dataset_outlined,
              label: '共 ${_tasks.length} 条',
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AppBarSearchTitle(
          title: '会议任务管理跟踪系统',
          controller: _searchController,
          hintText: '搜索任务（空格分词、引号短语、-排除）',
          onChanged: _searchTasks,
          loading: _searching,
        ),
        actions: [
          NotificationButton(
            onOpenScreen: _openNotificationScreen,
            onOpenTask: _openNotificationTask,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _reload, tooltip: '刷新'),
          IconButton(icon: const Icon(Icons.filter_alt), onPressed: _openFilter, tooltip: '统计筛选'),
          _ClickMenuButton(
            icon: Icons.history_rounded,
            tooltip: '历史快照',
            items: [
              _MenuEntry(
                icon: Icons.save_as_rounded,
                label: '保存历史快照',
                onTap: _saveSnapshot,
              ),
              _MenuEntry(
                icon: Icons.manage_history_rounded,
                label: '查看历史快照',
                onTap: _viewSnapshots,
              ),
            ],
          ),
          _ClickMenuButton(
            icon: Icons.file_download,
            tooltip: '导出',
            items: [
              _MenuEntry(icon: Icons.table_view, label: '导出Excel', onTap: _exportExcel),
              _MenuEntry(icon: Icons.text_snippet, label: '导出CSV', onTap: _exportCsv),
              _MenuEntry(icon: Icons.storage, label: '导出数据库', onTap: _exportDb),
              _MenuEntry(icon: Icons.archive_outlined, label: '导出所有文件', onTap: _exportAllFiles),
            ],
          ),
          _ClickMenuButton(
            icon: Icons.upload_file,
            tooltip: '导入',
            items: [
              _MenuEntry(icon: Icons.table_view, label: '导入Excel', onTap: _importExcel),
              _MenuEntry(icon: Icons.text_snippet, label: '导入CSV', onTap: _importCsv),
              _MenuEntry(icon: Icons.storage, label: '导入数据库', onTap: _importDb),
              _MenuEntry(icon: Icons.unarchive_outlined, label: '导入所有文件', onTap: _importAllFiles),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          AppSurface(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            radius: 14,
            elevated: true,
            child: _buildActionBar(),
          ),
          if (!_backendOk)
            const AppInfoBanner(
              icon: Icons.cloud_off_rounded,
              message: '本地服务未连接，请确认 hyrwbz_backend.exe 位于应用目录。',
              color: Colors.redAccent,
            ),
          Expanded(
            child: AppSurface(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: EdgeInsets.zero,
              radius: 14,
              elevated: true,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _tasks.isEmpty
                      ? AppEmptyState(
                          icon: Icons.assignment_outlined,
                          title: '暂无任务数据',
                          message: _filterSummary.isEmpty
                              ? '点击“添加条目”创建第一条会议任务。'
                              : '当前筛选条件下没有匹配的任务，请调整筛选条件。',
                          action: _filterSummary.isEmpty
                              ? FilledButton.icon(
                                  onPressed: _addTask,
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('添加条目'),
                                )
                              : OutlinedButton.icon(
                                  onPressed: _openFilter,
                                  icon: const Icon(Icons.tune_rounded),
                                  label: const Text('调整筛选'),
                                ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final widths =
                                _resolveColumnWidths(constraints.maxWidth);
                            return Column(
                              children: [
                                _buildHeaderRow(widths),
                                Expanded(
                                  child: Scrollbar(
                                    child: ListView.builder(
                                      itemCount: _tasks.length,
                                      itemBuilder: (context, index) =>
                                          _buildDataRow(
                                        index,
                                        _tasks[index],
                                        widths,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
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
    _actual = TextEditingController(text: '进行中');
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
        dept: normalizeEnglishCommas(_dept.text),
        owner: normalizeEnglishCommas(_owner.text),
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
      title: const AppSectionTitle(
        icon: Icons.add_task_rounded,
        title: '添加条目',
        subtitle: '填写任务信息并可同时添加附件',
      ),
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
                  Expanded(
                    child: TextField(
                      controller: _dept,
                      inputFormatters: const [EnglishCommaTextInputFormatter()],
                      decoration: const InputDecoration(labelText: '责任部门'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _owner,
                      inputFormatters: const [EnglishCommaTextInputFormatter()],
                      decoration: const InputDecoration(labelText: '责任人'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _required,
                      decoration: const InputDecoration(labelText: '计划完成时间'),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.calendar_month), onPressed: () => _pick(_required, '计划完成时间')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _actual,
                      decoration: const InputDecoration(labelText: '实际完成时间'),
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
      title: AppSectionTitle(
        icon: Icons.assignment_outlined,
        title: '条目详情',
        subtitle: '${task.meetingNo} / ${task.taskNo}',
      ),
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

class _SnapshotSaveRequest {
  final String remark;
  const _SnapshotSaveRequest(this.remark);
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
