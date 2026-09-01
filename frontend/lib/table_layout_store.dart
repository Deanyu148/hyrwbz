import 'dart:convert';
import 'dart:io';
import 'table_layout.dart';

class TaskColumnWidthStore {
  static File get file {
    final appData = Platform.environment['APPDATA'];
    final base = appData == null || appData.isEmpty
        ? File(Platform.resolvedExecutable).parent
        : Directory(appData);
    return File(
      '${base.path}${Platform.pathSeparator}hyrwbz'
      '${Platform.pathSeparator}task_column_widths_v1.json',
    );
  }

  static List<double>? load() {
    try {
      final target = file;
      if (!target.existsSync()) return null;
      return decode(target.readAsStringSync());
    } catch (_) {
      return null;
    }
  }

  static void saveSync(List<double> widths) {
    if (!isValidTaskColumnWidths(widths)) return;
    try {
      final target = file;
      target.parent.createSync(recursive: true);
      final temporary = File('${target.path}.tmp');
      temporary.writeAsStringSync(encode(widths), flush: true);
      if (target.existsSync()) target.deleteSync();
      temporary.renameSync(target.path);
    } catch (_) {}
  }

  static String encode(List<double> widths) => jsonEncode({
        'version': 1,
        'widths': widths,
      });

  static List<double>? decode(String source) {
    try {
      final json = jsonDecode(source) as Map<String, dynamic>;
      final values = json['widths'] as List<dynamic>?;
      if (values == null) return null;
      final widths = values.map((value) => (value as num).toDouble()).toList();
      return isValidTaskColumnWidths(widths) ? widths : null;
    } catch (_) {
      return null;
    }
  }
}
