import 'dart:io';
import 'dart:typed_data';

String sanitizeAttachmentFileName(String filename) {
  final sanitized = filename
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_')
      .trim();
  if (sanitized.isEmpty || sanitized == '.' || sanitized == '..') {
    return 'attachment';
  }
  return sanitized;
}

Future<File> createAttachmentWorkingCopy(
  int attachmentId,
  String filename,
  Uint8List bytes,
) async {
  final directory = Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'hyrwbz_attachment_preview${Platform.pathSeparator}'
    '${attachmentId}_${DateTime.now().microsecondsSinceEpoch}',
  );
  await directory.create(recursive: true);
  final file = File(
    '${directory.path}${Platform.pathSeparator}'
    '${sanitizeAttachmentFileName(filename)}',
  );
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<void> launchAttachmentFile(String path) async {
  if (Platform.isWindows) {
    await Process.start(
      'rundll32.exe',
      ['url.dll,FileProtocolHandler', path],
      mode: ProcessStartMode.detached,
    );
  } else if (Platform.isMacOS) {
    await Process.start('open', [path], mode: ProcessStartMode.detached);
  } else {
    await Process.start('xdg-open', [path], mode: ProcessStartMode.detached);
  }
}
