import 'package:flutter/services.dart';

final RegExp _nonEnglishCommaPattern = RegExp(r'[，、﹐﹑､،]');

/// 将中文输入法及常见输入法产生的逗号类字符统一转换为英文逗号。
String normalizeEnglishCommas(String value) =>
    value.replaceAll(_nonEnglishCommaPattern, ',');

class EnglishCommaTextInputFormatter extends TextInputFormatter {
  const EnglishCommaTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    final normalized = normalizeEnglishCommas(newValue.text);
    if (normalized == newValue.text) return newValue;
    return newValue.copyWith(text: normalized);
  }
}
