import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyrwbz_frontend/input_formatters.dart';

void main() {
  test('normalizes common non-English comma characters', () {
    expect(
      normalizeEnglishCommas('部门一，部门二、部门三﹐部门四﹑部门五､部门六،部门七'),
      '部门一,部门二,部门三,部门四,部门五,部门六,部门七',
    );
  });

  test('input formatter normalizes pasted text and keeps cursor position', () {
    const formatter = EnglishCommaTextInputFormatter();
    const text = '张三，李四、王五';
    final result = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: 8),
      ),
    );

    expect(result.text, '张三,李四,王五');
    expect(result.selection.baseOffset, result.text.length);
  });

  test('English commas remain unchanged', () {
    const formatter = EnglishCommaTextInputFormatter();
    const value = TextEditingValue(
      text: '张三,李四',
      selection: TextSelection.collapsed(offset: 5),
    );
    expect(formatter.formatEditUpdate(TextEditingValue.empty, value), same(value));
  });
}
