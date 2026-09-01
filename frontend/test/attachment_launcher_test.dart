import 'package:flutter_test/flutter_test.dart';
import 'package:hyrwbz_frontend/attachment_launcher.dart';

void main() {
  test('attachment preview names are safe for local file paths', () {
    expect(
      sanitizeAttachmentFileName(r'报价\2026:03?.xlsx'),
      '报价_2026_03_.xlsx',
    );
    expect(sanitizeAttachmentFileName(''), 'attachment');
    expect(sanitizeAttachmentFileName('..'), 'attachment');
  });
}
