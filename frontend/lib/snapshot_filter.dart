import 'models.dart';

List<Task> filterSnapshotTasks(Iterable<Task> tasks, FilterReq filter) =>
    tasks.where((task) => snapshotTaskMatchesFilter(task, filter)).toList();

bool snapshotTaskMatchesFilter(Task task, FilterReq filter) {
  if (filter.meetingNo != null &&
      !task.meetingNo.contains(filter.meetingNo!.trim())) {
    return false;
  }
  if (filter.taskNo != null && task.taskNo != filter.taskNo) return false;
  if (!_matchesAny(task.dept, filter.dept)) return false;
  if (!_matchesAny(task.owner, filter.owner)) return false;
  if (!_matchesDateRange(
    task.requiredDate,
    filter.requiredDateFrom,
    filter.requiredDateTo,
  )) {
    return false;
  }
  if (!_matchesDateRange(
    task.actualDate,
    filter.actualDateFrom,
    filter.actualDateTo,
  )) {
    return false;
  }
  if (filter.delayDateFrom != null || filter.delayDateTo != null) {
    final hasMatchingDelay = task.delays.any(
      (delay) => _matchesDateRange(
        delay.delayDate,
        filter.delayDateFrom,
        filter.delayDateTo,
      ),
    );
    if (!hasMatchingDelay) return false;
  }
  if (filter.delayIndex != null &&
      task.delays.length < filter.delayIndex!) {
    return false;
  }
  if (filter.expectedRemainingDays != null &&
      !_withinRemainingDays(task, filter.expectedRemainingDays!)) {
    return false;
  }
  if (filter.hasAttachment != null &&
      task.hasAttachment != filter.hasAttachment) {
    return false;
  }
  return true;
}

bool _matchesAny(String value, String? query) {
  if (query == null || query.trim().isEmpty) return true;
  final parts = query
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty);
  return parts.any(value.contains);
}

bool _matchesDateRange(String value, String? from, String? to) {
  if (from == null && to == null) return true;
  final date = _parseDate(value);
  if (date == null) return false;
  final lower = from == null ? null : _parseDate(from);
  final upper = to == null ? null : _parseDate(to);
  if (from != null && lower == null) return false;
  if (to != null && upper == null) return false;
  if (lower != null && date.isBefore(lower)) return false;
  if (upper != null && date.isAfter(upper)) return false;
  return true;
}

bool _withinRemainingDays(Task task, int maximumDays) {
  final value = task.delays.isEmpty ? task.requiredDate : task.delays.last.delayDate;
  final expected = _parseDate(value);
  if (expected == null) return false;
  final today = DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);
  final expectedDate = DateTime(expected.year, expected.month, expected.day);
  return expectedDate.difference(todayDate).inDays <= maximumDays;
}

DateTime? _parseDate(String value) => DateTime.tryParse(
      value.trim().replaceAll('/', '-'),
    );
