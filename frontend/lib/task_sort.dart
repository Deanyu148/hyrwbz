import 'package:pinyin/pinyin.dart';
import 'models.dart';

enum TaskSortColumn {
  sequence,
  meetingNo,
  taskNo,
  dept,
  owner,
  requiredDate,
  actualDate,
  lastDelayDate,
}

const List<TaskSortColumn?> taskSortColumnsByTableIndex = [
  TaskSortColumn.sequence,
  TaskSortColumn.meetingNo,
  TaskSortColumn.taskNo,
  null,
  TaskSortColumn.dept,
  TaskSortColumn.owner,
  TaskSortColumn.requiredDate,
  TaskSortColumn.actualDate,
  TaskSortColumn.lastDelayDate,
  null,
  null,
  null,
];

TaskSortColumn? taskSortColumnForIndex(int index) =>
    index >= 0 && index < taskSortColumnsByTableIndex.length
        ? taskSortColumnsByTableIndex[index]
        : null;

List<Task> sortTasks(
  List<Task> tasks, {
  required TaskSortColumn column,
  required bool ascending,
}) {
  final originalOrder = <Task, int>{
    for (var index = 0; index < tasks.length; index++) tasks[index]: index,
  };
  final sorted = List<Task>.from(tasks);
  sorted.sort((left, right) {
    final comparison = _compareTask(left, right, column, originalOrder);
    if (comparison != 0) return ascending ? comparison : -comparison;
    // Keep equal values stable. This also prevents rows from jumping when a
    // user toggles between fields with identical values.
    final stable = originalOrder[left]!.compareTo(originalOrder[right]!);
    return ascending ? stable : -stable;
  });
  return sorted;
}

int _compareTask(
  Task left,
  Task right,
  TaskSortColumn column,
  Map<Task, int> originalOrder,
) {
  switch (column) {
    case TaskSortColumn.sequence:
      // The visible sequence is the current source order, not task_no.
      return originalOrder[left]!.compareTo(originalOrder[right]!);
    case TaskSortColumn.meetingNo:
      return compareNaturalChinese(left.meetingNo, right.meetingNo);
    case TaskSortColumn.taskNo:
      return left.taskNo.compareTo(right.taskNo);
    case TaskSortColumn.dept:
      return compareNaturalChinese(left.dept, right.dept);
    case TaskSortColumn.owner:
      return compareNaturalChinese(left.owner, right.owner);
    case TaskSortColumn.requiredDate:
      return compareDateOrText(left.requiredDate, right.requiredDate);
    case TaskSortColumn.actualDate:
      return compareDateOrText(left.actualDate, right.actualDate);
    case TaskSortColumn.lastDelayDate:
      return compareDateOrText(_lastDelayDate(left), _lastDelayDate(right));
  }
}

String _lastDelayDate(Task task) =>
    task.delays.isEmpty ? '' : task.delays.last.delayDate;

int compareDateOrText(String left, String right) {
  final empty = _compareEmpty(left, right);
  if (empty != null) return empty;
  final leftDate = _parseDate(left);
  final rightDate = _parseDate(right);
  if (leftDate != null && rightDate != null) {
    return leftDate.compareTo(rightDate);
  }
  if (leftDate != null) return -1;
  if (rightDate != null) return 1;
  return compareNaturalChinese(left, right);
}

DateTime? _parseDate(String value) {
  final match = RegExp(r'^(\d{4})[/-](\d{1,2})[/-](\d{1,2})$')
      .firstMatch(value.trim());
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}

int compareNaturalChinese(String left, String right) {
  final empty = _compareEmpty(left, right);
  if (empty != null) return empty;
  return _compareNatural(_pinyinKey(left), _pinyinKey(right));
}

int? _compareEmpty(String left, String right) {
  final leftEmpty = left.trim().isEmpty;
  final rightEmpty = right.trim().isEmpty;
  if (leftEmpty == rightEmpty) return null;
  return leftEmpty ? -1 : 1;
}

String _pinyinKey(String value) => PinyinHelper.getPinyinE(
      value.trim(),
      separator: '',
      defPinyin: '#',
      format: PinyinFormat.WITHOUT_TONE,
    ).toLowerCase();

int _compareNatural(String left, String right) {
  final leftParts = RegExp(r'\d+|\D+')
      .allMatches(left)
      .map((match) => match.group(0)!)
      .toList();
  final rightParts = RegExp(r'\d+|\D+')
      .allMatches(right)
      .map((match) => match.group(0)!)
      .toList();
  final count = leftParts.length < rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < count; index++) {
    final leftPart = leftParts[index];
    final rightPart = rightParts[index];
    final leftIsNumber = RegExp(r'^\d+$').hasMatch(leftPart);
    final rightIsNumber = RegExp(r'^\d+$').hasMatch(rightPart);
    final comparison = leftIsNumber && rightIsNumber
        ? _compareNumberText(leftPart, rightPart)
        : leftPart.compareTo(rightPart);
    if (comparison != 0) return comparison;
  }
  return leftParts.length.compareTo(rightParts.length);
}

int _compareNumberText(String left, String right) {
  final normalizedLeft = left.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  final normalizedRight = right.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  final lengthComparison = normalizedLeft.length.compareTo(normalizedRight.length);
  if (lengthComparison != 0) return lengthComparison;
  final valueComparison = normalizedLeft.compareTo(normalizedRight);
  if (valueComparison != 0) return valueComparison;
  return left.length.compareTo(right.length);
}
