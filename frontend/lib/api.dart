import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'models.dart';

class Api {
  /// 端口由 main.dart 启动子进程时确定；默认 7790 兜底
  static int port = 7790;
  static String get base => 'http://127.0.0.1:' + port.toString();

  static Future<bool> health({int? port}) async {
    final p = port ?? Api.port;
    try {
      final r = await http.get(Uri.parse('http://127.0.0.1:' + p.toString() + '/api/health'));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Task>> listTasks(FilterReq? filter) async {
    final q = (filter?.toQuery() ?? <String, String>{});
    final u = Uri.parse(base + '/api/tasks').replace(queryParameters: q.isEmpty ? null : q);
    final r = await http.get(u);
    if (r.statusCode != 200) throw Exception(r.body);
    final list = jsonDecode(r.body) as List;
    return list.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Task> createTask(Task t) async {
    final r = await http.post(Uri.parse(base + '/api/tasks'),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode(t.toJson()));
    if (r.statusCode != 200) throw Exception(r.body);
    return Task.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  static Future<void> updateTask(int id, Task t) async {
    final b = Map<String, dynamic>.from(t.toJson());
    b['task_no'] = t.taskNo;
    final r = await http.put(Uri.parse(base + '/api/tasks/' + id.toString()),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode(b));
    if (r.statusCode != 200) throw Exception(r.body);
  }

  static Future<void> deleteTask(int id) async {
    final r = await http.delete(Uri.parse(base + '/api/tasks/' + id.toString()));
    if (r.statusCode != 200) throw Exception(r.body);
  }

  static Future<List<Delay>> listDelays(int taskId) async {
    final r = await http.get(Uri.parse(base + '/api/tasks/' + taskId.toString() + '/delays'));
    if (r.statusCode != 200) throw Exception(r.body);
    final list = jsonDecode(r.body) as List;
    return list.map((e) => Delay.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Delay> createDelay(int taskId, Delay d) async {
    final r = await http.post(Uri.parse(base + '/api/tasks/' + taskId.toString() + '/delays'),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode(d.toJson()));
    if (r.statusCode != 200) throw Exception(r.body);
    return Delay.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  static Future<void> deleteDelay(int id) async {
    final r = await http.delete(Uri.parse(base + '/api/delays/' + id.toString()));
    if (r.statusCode != 200) throw Exception(r.body);
  }

  static Future<String?> getLockedMeeting() async {
    final r = await http.get(Uri.parse(base + '/api/locked-meeting'));
    if (r.statusCode != 200) throw Exception(r.body);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return j['meeting_no'] as String?;
  }

  static Future<void> setLockedMeeting(String? meetingNo) async {
    final r = await http.put(Uri.parse(base + '/api/locked-meeting'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'meeting_no': meetingNo ?? ''}));
    if (r.statusCode != 200) throw Exception(r.body);
  }

  static Future<Map<String, dynamic>> exportExcel(FilterReq? filter, String? outDir) async {
    final body = {
      'filter': filter?.toBody() ?? {},
      if (outDir != null) 'out_dir': outDir,
    };
    final r = await http.post(Uri.parse(base + '/api/export/excel'),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
    if (r.statusCode != 200) throw Exception(r.body);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  static Future<int> createSnapshot() async {
    final r = await http.post(Uri.parse(base + '/api/snapshot'));
    if (r.statusCode != 200) throw Exception(r.body);
    return (jsonDecode(r.body) as Map<String, dynamic>)['snapshot_id'] as int;
  }

  static Future<List<Map<String, dynamic>>> listSnapshots() async {
    final r = await http.get(Uri.parse(base + '/api/snapshots'));
    if (r.statusCode != 200) throw Exception(r.body);
    final list = jsonDecode(r.body) as List;
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  static Future<String> exportDbFile() async {
    final r = await http.get(Uri.parse(base + '/api/db/export'));
    if (r.statusCode != 200) throw Exception(r.body);
    return (jsonDecode(r.body) as Map<String, dynamic>)['path'] as String;
  }

  static Future<void> importDbFile(Uint8List bytes, String filename) async {
    final req = http.MultipartRequest('POST', Uri.parse(base + '/api/db/import'))
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final r = await req.send();
    if (r.statusCode != 200) throw Exception(await r.stream.bytesToString());
  }

  static Future<List<Attachment>> listAttachments(int taskId) async {
    final r = await http.get(Uri.parse(base + '/api/tasks/' + taskId.toString() + '/attachments'));
    if (r.statusCode != 200) throw Exception(r.body);
    final list = jsonDecode(r.body) as List;
    return list.map((e) => Attachment.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<Attachment> uploadAttachment(int taskId, Uint8List bytes, String filename) async {
    final req = http.MultipartRequest('POST', Uri.parse(base + '/api/tasks/' + taskId.toString() + '/attachments'))
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final r = await req.send();
    final body = await r.stream.bytesToString();
    if (r.statusCode != 200) throw Exception(body);
    return Attachment.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  static Future<void> deleteAttachment(int id) async {
    final r = await http.delete(Uri.parse(base + '/api/attachments/' + id.toString()));
    if (r.statusCode != 200) throw Exception(r.body);
  }

  static String downloadAttachmentUrl(int id) {
    return base + '/api/attachments/' + id.toString() + '/download';
  }

  static Future<Map<String, dynamic>> importExcel(Uint8List bytes, String filename) async {
    final req = http.MultipartRequest('POST', Uri.parse(base + '/api/import/excel'))
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final r = await req.send();
    final body = await r.stream.bytesToString();
    if (r.statusCode != 200) throw Exception(body);
    return jsonDecode(body) as Map<String, dynamic>;
  }
}
