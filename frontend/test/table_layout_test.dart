import 'package:flutter_test/flutter_test.dart';
import 'package:hyrwbz_frontend/table_layout.dart';

void main() {
  for (final width in [900.0, 1200.0, 1600.0]) {
    test('task columns fill $width pixels', () {
      final columns = computeTaskColumnWidths(width);
      expect(columns.length, 12);
      final total = columns.fold<double>(taskSelectionWidth, (a, b) => a + b);
      expect(total, closeTo(width, 0.001));
    });
  }

  test('only remark grows after preferred widths are reached', () {
    final preferredWidth = taskSelectionWidth +
        taskPreferredColumnWidths.fold<double>(0, (a, b) => a + b) +
        taskRemarkMinWidth;
    final base = computeTaskColumnWidths(preferredWidth);
    final wide = computeTaskColumnWidths(preferredWidth + 300);
    for (var i = 0; i < taskPreferredColumnWidths.length; i++) {
      expect(base[i], closeTo(taskPreferredColumnWidths[i], 0.001));
      expect(wide[i], closeTo(base[i], 0.001));
    }
    expect(wide.last - base.last, closeTo(300, 0.001));
  });
}
