const double taskSelectionWidth = 44.0;
const double taskRemarkMinWidth = 100.0;
const List<double> taskMinColumnWidths = [
  38.0, 68.0, 50.0, 105.0, 58.0, 54.0, 76.0, 76.0, 76.0, 90.0, 42.0,
];
const List<double> taskPreferredColumnWidths = [
  60.0, 120.0, 80.0, 200.0, 100.0, 80.0, 120.0, 120.0, 120.0, 150.0, 60.0,
];

/// 返回 11 个普通列和最后一个备注列的宽度，列宽总和加选择列后等于 availableWidth。
List<double> computeTaskColumnWidths(double availableWidth) {
  final usable = (availableWidth - taskSelectionWidth)
      .clamp(0.0, double.infinity)
      .toDouble();
  final minimumNonRemark = taskMinColumnWidths.fold<double>(0, (a, b) => a + b);
  final preferredNonRemark = taskPreferredColumnWidths.fold<double>(0, (a, b) => a + b);
  final minimumTotal = minimumNonRemark + taskRemarkMinWidth;
  if (usable <= minimumTotal) {
    final scale = minimumTotal == 0 ? 0 : usable / minimumTotal;
    return [
      ...taskMinColumnWidths.map((width) => width * scale),
      taskRemarkMinWidth * scale,
    ];
  }

  final availableForGrowth = usable - minimumTotal;
  final preferredGrowth = preferredNonRemark - minimumNonRemark;
  final nonRemark = List<double>.generate(taskMinColumnWidths.length, (index) {
    final range = taskPreferredColumnWidths[index] - taskMinColumnWidths[index];
    if (availableForGrowth >= preferredGrowth) return taskPreferredColumnWidths[index];
    return taskMinColumnWidths[index] + availableForGrowth * range / preferredGrowth;
  });
  final used = nonRemark.fold<double>(0, (a, b) => a + b);
  return [...nonRemark, usable - used];
}
