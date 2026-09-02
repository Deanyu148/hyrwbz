import 'package:flutter_test/flutter_test.dart';
import 'package:hyrwbz_frontend/table_layout.dart';

void expectFillsWidth(List<double> columns, double width) {
  final total = columns.fold<double>(taskSelectionWidth, (sum, value) => sum + value);
  expect(total, closeTo(width, 0.001));
}

void main() {
  for (final width in [900.0, 1200.0, 1600.0]) {
    test('task columns fill $width pixels', () {
      final columns = computeTaskColumnWidths(width);
      expect(columns.length, taskColumnCount);
      expectFillsWidth(columns, width);
    });
  }

  test('only remark grows after preferred widths are reached', () {
    final preferredWidth = taskSelectionWidth +
        taskPreferredColumnWidths.fold<double>(0, (sum, width) => sum + width) +
        taskRemarkMinWidth;
    final base = computeTaskColumnWidths(preferredWidth);
    final wide = computeTaskColumnWidths(preferredWidth + 300);
    for (var i = 0; i < taskPreferredColumnWidths.length; i++) {
      expect(base[i], closeTo(taskPreferredColumnWidths[i], 0.001));
      expect(wide[i], closeTo(base[i], 0.001));
    }
    expect(wide.last - base.last, closeTo(300, 0.001));
  });

  test('dragging changes only the selected column and the remark column', () {
    const width = 1600.0;
    final original = computeTaskColumnWidths(width);
    final resized = resizeTaskColumnWidths(original, 3, 25, width);

    expect(resized[3] - original[3], closeTo(25, 0.001));
    expect(original.last - resized.last, closeTo(25, 0.001));
    for (var i = 0; i < resized.length; i++) {
      if (i != 3 && i != taskColumnCount - 1) {
        expect(resized[i], closeTo(original[i], 0.001));
      }
    }
    expectFillsWidth(resized, width);
  });

  test('dragging wider stops when the remark column reaches its minimum width', () {
    const width = 1600.0;
    final original = computeTaskColumnWidths(width);
    final resized = resizeTaskColumnWidths(original, 0, 10000, width);

    expect(resized.last, closeTo(taskAllMinColumnWidths.last, 0.001));
    expect(resized[1], closeTo(original[1], 0.001));
    expectFillsWidth(resized, width);
  });

  test('dragging narrower grows only the remark column', () {
    const width = 1600.0;
    final original = computeTaskColumnWidths(width);
    final resized = resizeTaskColumnWidths(original, 5, -10, width);

    expect(original[5] - resized[5], closeTo(10, 0.001));
    expect(resized.last - original.last, closeTo(10, 0.001));
    for (var i = 0; i < resized.length; i++) {
      if (i != 5 && i != taskColumnCount - 1) {
        expect(resized[i], closeTo(original[i], 0.001));
      }
    }
    expectFillsWidth(resized, width);
  });

  test('custom widths are restored exactly at the same window width', () {
    const width = 1600.0;
    final original = computeTaskColumnWidths(width);
    final custom = resizeTaskColumnWidths(original, 5, 20, width);
    final restored = fitTaskColumnWidths(width, custom);

    for (var i = 0; i < custom.length; i++) {
      expect(restored[i], closeTo(custom[i], 0.001));
    }
    expectFillsWidth(restored, width);
  });

  test('custom widths scale to a resized window and still fill it', () {
    const oldWidth = 1200.0;
    const newWidth = 1500.0;
    final custom = resizeTaskColumnWidths(
      computeTaskColumnWidths(oldWidth),
      7,
      -18,
      oldWidth,
    );
    final resizedWindow = fitTaskColumnWidths(newWidth, custom);

    expectFillsWidth(resizedWindow, newWidth);
    for (var i = 0; i < resizedWindow.length; i++) {
      expect(resizedWindow[i], greaterThanOrEqualTo(taskAllMinColumnWidths[i]));
    }
  });
  test('auto fit uses content widths and keeps the remark column as the remainder', () {
    const width = 1600.0;
    final fitted = autoFitTaskColumnWidths(width, [
      [
        '1',
        '纪要〔2026〕1号',
        '1',
        '这是一条很长的任务内容，用于自动调整列宽',
        '工程部',
        '张三',
        '2026/09/10',
        '进行中',
        '',
        '',
        '',
        '备注',
      ],
    ]);

    expect(fitted[3], greaterThan(taskPreferredColumnWidths[3]));
    expect(fitted.last, greaterThanOrEqualTo(taskRemarkMinWidth));
    expectFillsWidth(fitted, width);
  });

  test('attachment column stays at its locked narrow width and cannot be dragged', () {
    const width = 1600.0;
    final original = computeTaskColumnWidths(width);
    expect(original[taskAttachmentColumnIndex], taskAttachmentColumnWidth);

    final resized = resizeTaskColumnWidths(
      original,
      taskAttachmentColumnIndex,
      80,
      width,
    );
    expect(resized[taskAttachmentColumnIndex], taskAttachmentColumnWidth);
    expect(resized, original);
    expectFillsWidth(resized, width);
  });

}
