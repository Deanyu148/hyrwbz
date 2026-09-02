import 'dart:typed_data';
import 'local_rpc.dart';
import 'models.dart';
import 'notification_model.dart';

class AttachmentDownload {
  final String filename;
  final Uint8List bytes;
  const AttachmentDownload(this.filename, this.bytes);
}

class Api {
  static Future<LocalRpcClient> Function()? _clientProvider;

  static void configure(Future<LocalRpcClient> Function() provider) {
    _clientProvider = provider;
  }

  static Future<LocalRpcClient> _client() {
    final provider = _clientProvider;
    if (provider == null) {
      throw const RpcException('not_configured', '本地服务尚未配置');
    }
    return provider();
  }

  static Future<RpcReply> _call(
    String method, {
    Map<String, dynamic> params = const {},
    Uint8List? binary,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final client = await _client();
    return client.call(method, params: params, binary: binary, timeout: timeout);
  }

  static Future<bool> health() async {
    try {
      await _call('system.health', timeout: const Duration(seconds: 3));
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Task>> listTasks(FilterReq? filter) async {
    final reply = await _call('task.list', params: filter?.toBody() ?? const {});
    return (reply.result as List)
        .map((value) => Task.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList();
  }

  static Future<Set<int>> searchTaskIds(String query) async {
    final reply = await _call('search.tasks', params: {'query': query});
    return (reply.result as List)
        .map((value) => (value as num).toInt())
        .toSet();
  }

  static Future<Task> createTask(Task task) async {
    final reply = await _call('task.create', params: task.toJson());
    return Task.fromJson(Map<String, dynamic>.from(reply.result as Map));
  }

  static Future<void> updateTask(int id, Task task) async {
    final body = Map<String, dynamic>.from(task.toJson())..['task_no'] = task.taskNo;
    await _call('task.update', params: {'id': id, 'task': body});
  }

  static Future<void> deleteTask(int id) async {
    await _call('task.delete', params: {'id': id});
  }

  static Future<List<Delay>> listDelays(int taskId) async {
    final reply = await _call('delay.list', params: {'task_id': taskId});
    return (reply.result as List)
        .map((value) => Delay.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList();
  }

  static Future<Delay> createDelay(int taskId, Delay delay) async {
    final reply = await _call('delay.create', params: {
      'task_id': taskId,
      'delay': delay.toJson(),
    });
    return Delay.fromJson(Map<String, dynamic>.from(reply.result as Map));
  }

  static Future<void> deleteDelay(int id) async {
    await _call('delay.delete', params: {'id': id});
  }

  static Future<String?> getLockedMeeting() async {
    final reply = await _call('meeting_lock.get');
    return (reply.result as Map)['meeting_no'] as String?;
  }

  static Future<void> setLockedMeeting(String? meetingNo) async {
    await _call('meeting_lock.set', params: {'meeting_no': meetingNo ?? ''});
  }

  static Future<List<NotificationItem>> listNotifications() async {
    final reply = await _call('notification.list');
    return (reply.result as List)
        .map((value) => NotificationItem.fromJson(
              Map<String, dynamic>.from(value as Map),
            ))
        .toList();
  }

  static Future<List<NotificationItem>> listNotificationHistory({
    String? from,
    String? to,
  }) async {
    final reply = await _call(
      'notification.history',
      params: {
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
      },
    );
    return (reply.result as List)
        .map((value) => NotificationItem.fromJson(
              Map<String, dynamic>.from(value as Map),
            ))
        .toList();
  }

  static Future<void> markNotificationRead(int id) async {
    await _call('notification.mark_read', params: {'id': id});
  }

  static Future<void> markAllNotificationsRead() async {
    await _call('notification.mark_all_read');
  }

  static Future<Map<String, dynamic>> exportExcel(FilterReq? filter, String? outDir) async {
    final reply = await _call(
      'export.excel',
      params: {'filter': filter?.toBody() ?? const {}, if (outDir != null) 'out_dir': outDir},
      timeout: const Duration(minutes: 5),
    );
    return Map<String, dynamic>.from(reply.result as Map);
  }

  static Future<SnapshotCreateResult> createSnapshot(String? remark) async {
    final reply = await _call(
      'snapshot.create',
      params: {
        if (remark != null && remark.trim().isNotEmpty) 'remark': remark.trim(),
      },
    );
    return SnapshotCreateResult.fromJson(
      Map<String, dynamic>.from(reply.result as Map),
    );
  }

  static Future<List<SnapshotInfo>> listSnapshots() async {
    final reply = await _call('snapshot.list');
    return (reply.result as List)
        .map((value) => SnapshotInfo.fromJson(
              Map<String, dynamic>.from(value as Map),
            ))
        .toList();
  }

  static Future<SnapshotDetail> getSnapshot(int snapshotId) async {
    final reply = await _call('snapshot.get', params: {'id': snapshotId});
    return SnapshotDetail.fromJson(
      Map<String, dynamic>.from(reply.result as Map),
    );
  }

  static Future<String> exportDbFile() async {
    final reply = await _call('export.database', timeout: const Duration(minutes: 5));
    return (reply.result as Map)['path'] as String;
  }

  static Future<void> importDbFile(Uint8List bytes, String filename) async {
    await _call(
      'import.database',
      params: {'filename': filename},
      binary: bytes,
      timeout: const Duration(minutes: 5),
    );
  }

  static Future<String> exportAllFiles(String? outDir) async {
    final reply = await _call(
      'export.all_files',
      params: {if (outDir != null) 'out_dir': outDir},
      timeout: const Duration(minutes: 5),
    );
    return (reply.result as Map)['path'] as String;
  }

  static Future<void> importAllFiles(Uint8List bytes, String filename) async {
    await _call(
      'import.all_files',
      params: {'filename': filename},
      binary: bytes,
      timeout: const Duration(minutes: 10),
    );
  }

  static Future<List<Attachment>> listAttachments(int taskId) async {
    final reply = await _call('attachment.list', params: {'task_id': taskId});
    return (reply.result as List)
        .map((value) => Attachment.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList();
  }

  static Future<Attachment> uploadAttachment(
    int taskId,
    Uint8List bytes,
    String filename,
  ) async {
    final reply = await _call(
      'attachment.upload',
      params: {'task_id': taskId, 'filename': filename},
      binary: bytes,
      timeout: const Duration(minutes: 2),
    );
    return Attachment.fromJson(Map<String, dynamic>.from(reply.result as Map));
  }

  static Future<Attachment> updateAttachment(
    int id,
    Uint8List bytes,
    String filename,
  ) async {
    final reply = await _call(
      'attachment.update',
      params: {'id': id, 'filename': filename},
      binary: bytes,
      timeout: const Duration(minutes: 2),
    );
    return Attachment.fromJson(Map<String, dynamic>.from(reply.result as Map));
  }

  static Future<void> deleteAttachment(int id) async {
    await _call('attachment.delete', params: {'id': id});
  }

  static Future<AttachmentDownload> downloadAttachment(int id) async {
    final reply = await _call(
      'attachment.download',
      params: {'id': id},
      timeout: const Duration(minutes: 2),
    );
    return AttachmentDownload((reply.result as Map)['filename'] as String, reply.binary);
  }

  static Future<Map<String, dynamic>> importExcel(
    Uint8List bytes,
    String filename, {
    required bool moveRemarkToDelayReason,
  }) async {
    final reply = await _call(
      'import.excel',
      params: {
        'filename': filename,
        'move_remark_to_delay_reason': moveRemarkToDelayReason,
      },
      binary: bytes,
      timeout: const Duration(minutes: 5),
    );
    return Map<String, dynamic>.from(reply.result as Map);
  }

  static Future<Map<String, dynamic>> exportCsv(FilterReq? filter, String? outDir) async {
    final reply = await _call(
      'export.csv',
      params: {'filter': filter?.toBody() ?? const {}, if (outDir != null) 'out_dir': outDir},
      timeout: const Duration(minutes: 5),
    );
    return Map<String, dynamic>.from(reply.result as Map);
  }

  static Future<Map<String, dynamic>> importCsv(
    Uint8List bytes,
    String filename, {
    required bool moveRemarkToDelayReason,
  }) async {
    final reply = await _call(
      'import.csv',
      params: {
        'filename': filename,
        'move_remark_to_delay_reason': moveRemarkToDelayReason,
      },
      binary: bytes,
      timeout: const Duration(minutes: 5),
    );
    return Map<String, dynamic>.from(reply.result as Map);
  }
}
