const double taskSelectionWidth = 44.0;
const double taskRemarkMinWidth = 100.0;
const double taskAttachmentColumnWidth = 72.0;
const int taskAttachmentColumnIndex = 10;

// 最小宽度按表头文字和右侧排序图标预留，保证正常最小窗口下表头完整显示。
const List<double> taskMinColumnWidths = [
  64.0,
  110.0,
  86.0,
  88.0,
  88.0,
  76.0,
  112.0,
  112.0,
  88.0,
  88.0,
  taskAttachmentColumnWidth,
];
const List<double> taskPreferredColumnWidths = [
  72.0,
  130.0,
  96.0,
  220.0,
  110.0,
  90.0,
  130.0,
  130.0,
  105.0,
  160.0,
  taskAttachmentColumnWidth,
];

const int taskColumnCount = 12;

List<double> get taskAllMinColumnWidths => [
      ...taskMinColumnWidths,
      taskRemarkMinWidth,
    ];

double _usableTaskWidth(double availableWidth) =>
    (availableWidth - taskSelectionWidth).clamp(0.0, double.infinity).toDouble();

List<double> _finishTotal(List<double> widths, double target) {
  if (widths.isEmpty) return widths;
  final result = List<double>.from(widths);
  final total = result.fold<double>(0, (sum, width) => sum + width);
  result[result.length - 1] += target - total;
  return result;
}

List<double> _minimumsForUsableWidth(double usableWidth) {
  final minimums = taskAllMinColumnWidths;
  final minimumTotal = minimums.fold<double>(0, (sum, width) => sum + width);
  if (usableWidth >= minimumTotal || minimumTotal == 0) return minimums;
  final scale = usableWidth / minimumTotal;
  return minimums.map((width) => width * scale).toList();
}

bool isValidTaskColumnWidths(List<double>? widths) {
  if (widths == null || widths.length != taskColumnCount) return false;
  return widths.every((width) => width.isFinite && width > 0);
}

List<double> _lockAttachmentColumn(List<double> widths, double target) {
  final minimumTotal = taskAllMinColumnWidths.fold<double>(
    0,
    (sum, width) => sum + width,
  );
  if (target < minimumTotal) return widths;
  final result = List<double>.from(widths);
  result[taskAttachmentColumnIndex] = taskAttachmentColumnWidth;
  return _finishTotal(result, target);
}

/// 返回 11 个普通列和最后一个备注列的默认宽度。
/// 所有数据列宽度之和加选择列宽度后严格等于 [availableWidth]。
List<double> computeTaskColumnWidths(double availableWidth) {
  final usable = _usableTaskWidth(availableWidth);
  final minimums = taskAllMinColumnWidths;
  final minimumTotal = minimums.fold<double>(0, (sum, width) => sum + width);
  if (usable <= minimumTotal) {
    return _finishTotal(_minimumsForUsableWidth(usable), usable);
  }

  final minimumNonRemark =
      taskMinColumnWidths.fold<double>(0, (sum, width) => sum + width);
  final preferredNonRemark =
      taskPreferredColumnWidths.fold<double>(0, (sum, width) => sum + width);
  final availableForGrowth = usable - minimumTotal;
  final preferredGrowth = preferredNonRemark - minimumNonRemark;
  final nonRemark = List<double>.generate(taskMinColumnWidths.length, (index) {
    final range =
        taskPreferredColumnWidths[index] - taskMinColumnWidths[index];
    if (availableForGrowth >= preferredGrowth) {
      return taskPreferredColumnWidths[index];
    }
    return taskMinColumnWidths[index] +
        availableForGrowth * range / preferredGrowth;
  });
  final used = nonRemark.fold<double>(0, (sum, width) => sum + width);
  return _lockAttachmentColumn(
    _finishTotal([...nonRemark, usable - used], usable),
    usable,
  );
}

/// 把已保存或当前列宽适配到新的窗口宽度。
///
/// 在满足最小列宽的前提下，按各列超出最小宽度的比例分配空间，
/// 因而相同窗口宽度下可以精确恢复用户拖动后的列宽；窗口缩放时总宽度
/// 仍会与窗口内容宽度保持一致。
List<double> fitTaskColumnWidths(
  double availableWidth,
  List<double>? currentWidths,
) {
  if (!isValidTaskColumnWidths(currentWidths)) {
    return computeTaskColumnWidths(availableWidth);
  }

  final usable = _usableTaskWidth(availableWidth);
  final minimums = _minimumsForUsableWidth(usable);
  final minimumTotal = minimums.fold<double>(0, (sum, width) => sum + width);
  if (usable <= minimumTotal + 0.001) {
    return _finishTotal(minimums, usable);
  }

  final extras = List<double>.generate(
    taskColumnCount,
    (index) => (currentWidths![index] - taskAllMinColumnWidths[index])
        .clamp(0.0, double.infinity)
        .toDouble(),
  );
  final extraTotal = extras.fold<double>(0, (sum, width) => sum + width);
  if (extraTotal <= 0.001) return computeTaskColumnWidths(availableWidth);

  final availableExtra = usable -
      taskAllMinColumnWidths.fold<double>(0, (sum, width) => sum + width);
  final fitted = List<double>.generate(
    taskColumnCount,
    (index) => taskAllMinColumnWidths[index] +
        availableExtra * extras[index] / extraTotal,
  );
  return _lockAttachmentColumn(_finishTotal(fitted, usable), usable);
}

/// 拖动第 [dividerIndex] 个分隔线时，只调整该分隔线左侧栏目。
///
/// 为保持表格总宽度与窗口一致，所有宽度差额统一由最后的“备注”栏吸收；
/// 分隔线右侧的相邻栏目以及其他普通栏目宽度均保持不变。
List<double> resizeTaskColumnWidths(
  List<double> currentWidths,
  int dividerIndex,
  double delta,
  double availableWidth,
) {
  final fitted = fitTaskColumnWidths(availableWidth, currentWidths);
  const remarkIndex = taskColumnCount - 1;
  if (dividerIndex < 0 ||
      dividerIndex >= remarkIndex ||
      dividerIndex == taskAttachmentColumnIndex) {
    return fitted;
  }

  final minimums = _minimumsForUsableWidth(_usableTaskWidth(availableWidth));
  final columnWidth = fitted[dividerIndex];
  final remarkWidth = fitted[remarkIndex];
  final minimumDelta = minimums[dividerIndex] - columnWidth;
  final maximumDelta = remarkWidth - minimums[remarkIndex];
  final applied = delta.clamp(minimumDelta, maximumDelta).toDouble();

  final resized = List<double>.from(fitted);
  resized[dividerIndex] = columnWidth + applied;
  resized[remarkIndex] = remarkWidth - applied;
  return _finishTotal(resized, _usableTaskWidth(availableWidth));
}

const List<String> taskColumnHeaderLabels = [
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

double _estimateTaskCellWidth(String value) {
  var width = 16.0;
  for (final rune in value.runes) {
    width += rune <= 0x7f ? 8.0 : 14.0;
  }
  return width;
}

/// 根据表头和当前数据内容自动计算列宽。
/// 备注列仍然吸收剩余宽度，保证表格总宽度与窗口一致。
List<double> autoFitTaskColumnWidths(
  double availableWidth,
  List<List<String>> rows,
) {
  final usable = _usableTaskWidth(availableWidth);
  final minimums = _minimumsForUsableWidth(usable);
  final desired = List<double>.generate(taskColumnCount - 1, (index) {
    if (index == taskAttachmentColumnIndex) {
      return taskAttachmentColumnWidth;
    }
    var width = _estimateTaskCellWidth(taskColumnHeaderLabels[index]);
    for (final row in rows) {
      if (index < row.length) {
        width = width > _estimateTaskCellWidth(row[index])
            ? width
            : _estimateTaskCellWidth(row[index]);
      }
    }
    return width.clamp(minimums[index], 320.0).toDouble();
  });
  final minimumNonRemark = minimums
      .take(taskColumnCount - 1)
      .fold<double>(0, (sum, width) => sum + width);
  final minimumTotal = minimums.fold<double>(0, (sum, width) => sum + width);
  final desiredNonRemark = desired.fold<double>(0, (sum, width) => sum + width);
  if (usable <= minimumTotal) {
    return _finishTotal(minimums, usable);
  }
  final targetNonRemark = usable - minimums.last;
  if (desiredNonRemark <= targetNonRemark) {
    return _finishTotal(
      [...desired, usable - desiredNonRemark],
      usable,
    );
  }

  final extraAvailable = targetNonRemark - minimumNonRemark;
  final desiredExtra = desiredNonRemark - minimumNonRemark;
  if (desiredExtra <= 0.001) {
    return _finishTotal([...minimums.take(taskColumnCount - 1), minimums.last], usable);
  }
  final fitted = List<double>.generate(
    taskColumnCount - 1,
    (index) => minimums[index] +
        extraAvailable * (desired[index] - minimums[index]) / desiredExtra,
  );
  return _finishTotal([...fitted, taskRemarkMinWidth], usable);
}
