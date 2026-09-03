import 'package:flutter/material.dart';
import '../api.dart';
import '../app_widgets.dart';
import '../models.dart';
import '../task_search.dart';
import '../search_field.dart';
import '../snapshot_filter.dart';
import '../table_layout.dart';
import '../task_sort.dart';
import 'filter_screen.dart';

String snapshotSavedMessage(int usedCount) =>
    '历史快照已保存（最多保留 10 份）（当前已经使用$usedCount份）';

class SnapshotScreen extends StatefulWidget {
  final SnapshotInfo snapshot;
  final SnapshotDetail? initialDetail;

  const SnapshotScreen({
    super.key,
    required this.snapshot,
    this.initialDetail,
  });

  @override
  State<SnapshotScreen> createState() => _SnapshotScreenState();
}

class _SnapshotScreenState extends State<SnapshotScreen> {
  static const _columnLabels = [
    '序号',
    '会议纪要号',
    '任务序号',
    '任务内容',
    '责任部门',
    '责任人',
    '计划完成时间',
    '实际完成时间',
    '最后延期',
    '延期理由',
    '附件',
    '备注',
  ];

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  SnapshotDetail? _detail;
  Object? _error;
  FilterReq _filter = const FilterReq();
  List<Task> _filteredTasks = const [];
  TaskSortColumn _sortColumn = TaskSortColumn.meetingNo;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _detail = widget.initialDetail;
    if (_detail == null) {
      _load();
    } else {
      _applyFilters();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _detail = null;
    });
    try {
      final detail = await Api.getSnapshot(widget.snapshot.snapshotId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _applyFilters();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  List<Task> get _tasks => sortTasks(
        _filteredTasks,
        column: _sortColumn,
        ascending: _sortAscending,
      );

  void _applyFilters() {
    final source = _detail?.tasks ?? const <Task>[];
    final query = _searchController.text;
    final filtered = filterSnapshotTasks(source, _filter);
    _filteredTasks = query.trim().isEmpty
        ? filtered
        : filtered
            .where((task) => taskMatchesSearch(task, query))
            .toList();
  }

  void _search(String _) => setState(_applyFilters);

  Future<void> _openFilter() async {
    final result = await showDialog<FilterReq>(
      context: context,
      builder: (_) => FilterScreen(initial: _filter),
    );
    if (result == null || !mounted) return;
    setState(() {
      _filter = result;
      _applyFilters();
    });
  }

  void _sortByIndex(int index) {
    final column = taskSortColumnForIndex(index);
    if (column == null) return;
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

  Widget _sortIcon(int index) {
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

  Widget _header(List<double> widths) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: taskSelectionWidth,
            child: Center(
              child: Tooltip(
                message: '历史快照为只读数据',
                child: Icon(Icons.lock_outline_rounded, size: 18),
              ),
            ),
          ),
          for (var index = 0; index < _columnLabels.length; index++)
            SizedBox(
              width: widths[index],
              child: InkWell(
                onTap: taskSortColumnForIndex(index) == null
                    ? null
                    : () => _sortByIndex(index),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _columnLabels[index],
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      _sortIcon(index),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(int index, Task task, List<double> widths) {
    final lastDelay = task.delays.isEmpty ? null : task.delays.last;
    final values = [
      '${index + 1}',
      task.meetingNo,
      task.taskNo.toString(),
      task.taskDesc,
      task.dept,
      task.owner,
      task.requiredDate,
      task.actualDate,
      lastDelay?.delayDate ?? '',
      lastDelay?.delayReason ?? '',
      '',
      task.remark,
    ];
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: index.isOdd
            ? scheme.surfaceContainerLow.withValues(alpha: 0.55)
            : scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Row(
            children: [
              const SizedBox(
                width: taskSelectionWidth,
                child: Center(
                  child: Icon(Icons.lock_outline_rounded, size: 15),
                ),
              ),
              for (var column = 0; column < values.length; column++)
                Container(
                  width: widths[column],
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 9,
                  ),
                  decoration: column == taskAttachmentColumnIndex
                      ? null
                      : BoxDecoration(
                          border: Border(
                            right: BorderSide(color: scheme.outlineVariant),
                          ),
                        ),
                  child: Tooltip(
                    message: values[column],
                    child: column == taskAttachmentColumnIndex
                        ? task.hasAttachment
                            ? const Align(
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.attach_file_rounded,
                                  size: 19,
                                ),
                              )
                            : const SizedBox.shrink()
                        : Text(
                            values[column],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ),
            ],
          ),
          Positioned(
            left: taskSelectionWidth +
                widths
                    .take(taskAttachmentColumnIndex + 1)
                    .fold<double>(0, (sum, width) => sum + width),
            top: 0,
            bottom: 0,
            width: 1,
            child: ColoredBox(color: scheme.outlineVariant),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      appBar: AppBar(
        title: AppBarSearchTitle(
          title: '历史快照',
          controller: _searchController,
          hintText: '搜索快照任务（空格分词、引号短语、-排除）',
          onChanged: _search,
        ),
        actions: [
          IconButton(
            tooltip: '筛选快照数据',
            onPressed: _openFilter,
            icon: const Icon(Icons.filter_alt_rounded),
          ),
          IconButton(
            tooltip: '重新加载',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          AppSurface(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            elevated: true,
            child: Row(
              children: [
                const Icon(Icons.lock_clock_outlined),
                const SizedBox(width: 10),
                AppStatusPill(
                  icon: Icons.schedule_rounded,
                  label: detail?.savedAt ?? widget.snapshot.savedAt,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    (detail?.remark ?? widget.snapshot.remark).trim().isEmpty
                        ? '无备注'
                        : (detail?.remark ?? widget.snapshot.remark),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                AppStatusPill(
                  icon: Icons.visibility_outlined,
                  label: '只读',
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ],
            ),
          ),
          Expanded(
            child: AppSurface(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: EdgeInsets.zero,
              elevated: true,
              child: _error != null
                  ? AppEmptyState(
                      icon: Icons.error_outline_rounded,
                      title: '快照加载失败',
                      message: _error.toString(),
                      action: FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('重试'),
                      ),
                    )
                  : detail == null
                      ? const Center(child: CircularProgressIndicator())
                      : _tasks.isEmpty
                          ? const AppEmptyState(
                              icon: Icons.history_toggle_off_rounded,
                              title: '快照中没有任务',
                              message: '保存该快照时没有可记录的任务数据。',
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final widths = computeTaskColumnWidths(
                                  constraints.maxWidth,
                                );
                                final tasks = _tasks;
                                return Column(
                                  children: [
                                    _header(widths),
                                    Expanded(
                                      child: Scrollbar(
                                        controller: _scrollController,
                                        interactive: true,
                                        child: ListView.builder(
                                          controller: _scrollController,
                                          itemCount: tasks.length,
                                          itemBuilder: (context, index) =>
                                              _row(index, tasks[index], widths),
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
