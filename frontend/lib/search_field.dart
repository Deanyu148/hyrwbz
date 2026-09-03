import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_widgets.dart';

class AppBarSearchTitle extends StatelessWidget {
  /// 主界面标题可单独放大，标题宽度始终为搜索框预留空间。
  static const double searchVerticalOffset = 2;
  static const double titleWidthReserveForSearch = 180;

  final String title;
  final double titleFontSizeDelta;
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final bool loading;

  const AppBarSearchTitle({
    super.key,
    required this.title,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.titleFontSizeDelta = 0,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseTitleStyle = theme.appBarTheme.titleTextStyle ??
        theme.textTheme.titleLarge ??
        const TextStyle(fontSize: 20);
    final titleStyle = baseTitleStyle.copyWith(
      fontSize: (baseTitleStyle.fontSize ?? 20) + titleFontSizeDelta,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxTitleWidth = constraints.maxWidth.isFinite
            ? (constraints.maxWidth - 18 - titleWidthReserveForSearch)
                .clamp(0.0, 360.0)
                .toDouble()
            : 360.0;
        return SizedBox(
          height: AppSearchField.fieldHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxTitleWidth),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Transform.translate(
                  offset: const Offset(0, searchVerticalOffset),
                  child: AppSearchField(
                    controller: controller,
                    hintText: hintText,
                    onChanged: onChanged,
                    loading: loading,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class AppSearchField extends StatelessWidget {
  static const double fieldHeight = 38;

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final bool loading;

  const AppSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: fieldHeight,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: appInputDecoration(
          context,
          hintText: hintText,
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: scheme.primary),
          prefixIconConstraints: const BoxConstraints(minWidth: 40),
          suffixIcon: loading
              ? const Padding(
                  padding: EdgeInsets.all(11),
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清除搜索',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                    ),
          suffixIconConstraints: const BoxConstraints(minWidth: 40),
          compact: true,
        ),
      ),
    );
  }
}

/// 与添加/编辑窗口共享标准高度、浮动标签、填充色和边框样式的普通输入框。
/// 用于筛选弹窗，搜索栏仍使用独立的紧凑布局。
class AppFilterField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const AppFilterField({
    super.key,
    required this.controller,
    required this.hintText,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: appInputDecoration(
        context,
        labelText: hintText,
      ),
    );
  }
}
