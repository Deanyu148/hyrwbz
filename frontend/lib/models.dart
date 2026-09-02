class Delay {
  final int id;
  final int taskId;
  final String meetingNo;
  final int taskNo;
  final String delayDate;
  final String delayReason;
  final String createdAt;
  Delay({
    required this.id,
    required this.taskId,
    required this.meetingNo,
    required this.taskNo,
    required this.delayDate,
    required this.delayReason,
    required this.createdAt,
  });
  factory Delay.fromJson(Map<String, dynamic> j) => Delay(
        id: (j['id'] as num).toInt(),
        taskId: (j['task_id'] as num).toInt(),
        meetingNo: j['meeting_no'] as String? ?? '',
        taskNo: (j['task_no'] as num).toInt(),
        delayDate: j['delay_date'] as String? ?? '',
        delayReason: j['delay_reason'] as String? ?? '',
        createdAt: j['created_at'] as String? ?? '',
      );
  Map<String, dynamic> toJson() => {
        'delay_date': delayDate,
        'delay_reason': delayReason,
      };
}

class Attachment {
  final int id;
  final int taskId;
  final String filename;
  final String storedName;
  final String createdAt;
  Attachment({
    required this.id,
    required this.taskId,
    required this.filename,
    required this.storedName,
    required this.createdAt,
  });
  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
        id: (j['id'] as num).toInt(),
        taskId: (j['task_id'] as num).toInt(),
        filename: j['filename'] as String? ?? '',
        storedName: j['stored_name'] as String? ?? '',
        createdAt: j['created_at'] as String? ?? '',
      );
}

class Task {
  final int? id;
  final String meetingNo;
  final int taskNo;
  final String taskDesc;
  final String dept;
  final String owner;
  final String requiredDate;
  final String actualDate;
  final String remark;
  final String createdAt;
  final String updatedAt;
  final bool hasAttachment;
  final List<Delay> delays;
  Task({
    this.id,
    required this.meetingNo,
    required this.taskNo,
    required this.taskDesc,
    required this.dept,
    required this.owner,
    required this.requiredDate,
    required this.actualDate,
    required this.remark,
    this.createdAt = '',
    this.updatedAt = '',
    this.hasAttachment = false,
    this.delays = const [],
  });
  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id'] == null ? null : (j['id'] as num).toInt(),
        meetingNo: j['meeting_no'] as String? ?? '',
        taskNo: (j['task_no'] as num).toInt(),
        taskDesc: j['task_desc'] as String? ?? '',
        dept: j['dept'] as String? ?? '',
        owner: j['owner'] as String? ?? '',
        requiredDate: j['required_date'] as String? ?? '',
        actualDate: j['actual_date'] as String? ?? '',
        remark: j['remark'] as String? ?? '',
        createdAt: j['created_at'] as String? ?? '',
        updatedAt: j['updated_at'] as String? ?? '',
        hasAttachment: j['has_attachment'] as bool? ?? false,
        delays: (j['delays'] as List? ?? []).map((e) => Delay.fromJson(e as Map<String, dynamic>)).toList(),
      );
  Map<String, dynamic> toJson() => {
        'meeting_no': meetingNo,
        'task_no': taskNo,
        'task_desc': taskDesc,
        'dept': dept,
        'owner': owner,
        'required_date': requiredDate,
        'actual_date': actualDate,
        'remark': remark,
      };
}

class FilterReq {
  final String? meetingNo;
  final int? taskNo;
  final String? dept;
  final String? owner;
  final String? requiredDateFrom;
  final String? requiredDateTo;
  final String? actualDateFrom;
  final String? actualDateTo;
  final String? delayDateFrom;
  final String? delayDateTo;
  final int? delayIndex;
  final int? expectedRemainingDays;
  final bool? hasAttachment;
  const FilterReq({
    this.meetingNo,
    this.taskNo,
    this.dept,
    this.owner,
    this.requiredDateFrom,
    this.requiredDateTo,
    this.actualDateFrom,
    this.actualDateTo,
    this.delayDateFrom,
    this.delayDateTo,
    this.delayIndex,
    this.expectedRemainingDays,
    this.hasAttachment,
  });
  bool get isEmpty =>
      meetingNo == null &&
      taskNo == null &&
      dept == null &&
      owner == null &&
      requiredDateFrom == null &&
      requiredDateTo == null &&
      actualDateFrom == null &&
      actualDateTo == null &&
      delayDateFrom == null &&
      delayDateTo == null &&
      delayIndex == null &&
      expectedRemainingDays == null &&
      hasAttachment == null;
  Map<String, String> toQuery() {
    final m = <String, String>{};
    if (meetingNo != null && meetingNo!.isNotEmpty) m['meeting_no'] = meetingNo!;
    if (taskNo != null) m['task_no'] = taskNo.toString();
    if (dept != null && dept!.isNotEmpty) m['dept'] = dept!;
    if (owner != null && owner!.isNotEmpty) m['owner'] = owner!;
    if (requiredDateFrom != null) m['required_date_from'] = requiredDateFrom!;
    if (requiredDateTo != null) m['required_date_to'] = requiredDateTo!;
    if (actualDateFrom != null) m['actual_date_from'] = actualDateFrom!;
    if (actualDateTo != null) m['actual_date_to'] = actualDateTo!;
    if (delayDateFrom != null) m['delay_date_from'] = delayDateFrom!;
    if (delayDateTo != null) m['delay_date_to'] = delayDateTo!;
    if (delayIndex != null) m['delay_index'] = delayIndex.toString();
    if (expectedRemainingDays != null) {
      m['expected_remaining_days'] = expectedRemainingDays.toString();
    }
    if (hasAttachment != null) m['has_attachment'] = hasAttachment.toString();
    return m;
  }

  Map<String, dynamic> toBody() {
    final m = <String, dynamic>{};
    if (meetingNo != null && meetingNo!.isNotEmpty) m['meeting_no'] = meetingNo;
    if (taskNo != null) m['task_no'] = taskNo;
    if (dept != null && dept!.isNotEmpty) m['dept'] = dept;
    if (owner != null && owner!.isNotEmpty) m['owner'] = owner;
    if (requiredDateFrom != null) m['required_date_from'] = requiredDateFrom;
    if (requiredDateTo != null) m['required_date_to'] = requiredDateTo;
    if (actualDateFrom != null) m['actual_date_from'] = actualDateFrom;
    if (actualDateTo != null) m['actual_date_to'] = actualDateTo;
    if (delayDateFrom != null) m['delay_date_from'] = delayDateFrom;
    if (delayDateTo != null) m['delay_date_to'] = delayDateTo;
    if (delayIndex != null) m['delay_index'] = delayIndex;
    if (expectedRemainingDays != null) {
      m['expected_remaining_days'] = expectedRemainingDays;
    }
    if (hasAttachment != null) m['has_attachment'] = hasAttachment;
    return m;
  }
}
