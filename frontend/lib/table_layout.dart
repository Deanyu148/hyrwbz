const double taskSelectionWidth = 44.0;
const double taskRemarkMinWidth = 100.0;
const List<double> taskMinColumnWidths = [
  38.0,
  68.0,
  50.0,
  105.0,
  58.0,
  54.0,
  76.0,
  76.0,
  76.0,
  90.0,
  42.0,
];
const List<double> taskPreferredColumnWidths = [
  60.0,
  120.0,
  80.0,
  200.0,
  100.0,
  80.0,
  120.0,
  120.0,
  120.0,
  150.0,
  60.0,
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
  return _finishTotal([...nonRemark, usable - used], usable);
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
  return _finishTotal(fitted, usable);
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
  if (dividerIndex < 0 || dividerIndex >= remarkIndex) return fitted;

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
