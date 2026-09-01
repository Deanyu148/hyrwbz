import 'package:flutter_test/flutter_test.dart';
import 'package:hyrwbz_frontend/table_layout.dart';
import 'package:hyrwbz_frontend/table_layout_store.dart';

void main() {
  test('column widths survive persistence encoding', () {
    final widths = computeTaskColumnWidths(1200);
    final decoded = TaskColumnWidthStore.decode(TaskColumnWidthStore.encode(widths));

    expect(decoded, isNotNull);
    expect(decoded, hasLength(taskColumnCount));
    for (var i = 0; i < widths.length; i++) {
      expect(decoded![i], closeTo(widths[i], 0.001));
    }
  });

  test('invalid persisted column widths are ignored', () {
    expect(TaskColumnWidthStore.decode('{"widths":[10,20]}'), isNull);
    expect(TaskColumnWidthStore.decode('not json'), isNull);
  });
}
