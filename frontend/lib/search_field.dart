import 'package:flutter/material.dart';

class AppBarSearchTitle extends StatelessWidget {
  static const double searchVerticalOffset = 2;

  final String title;
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
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSearchField.fieldHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );
    return SizedBox(
      height: fieldHeight,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hintText,
          isDense: true,
          filled: true,
          fillColor: scheme.surfaceContainerLow,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: scheme.primary, width: 1.5),
          ),
        ),
      ),
    );
  }
}
