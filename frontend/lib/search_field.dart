import 'package:flutter/material.dart';

class AppSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  const AppSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hintText,
          isDense: true,
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          prefixIcon: const Icon(Icons.search, size: 20),
          prefixIconConstraints: const BoxConstraints(minWidth: 38),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '清除搜索',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          suffixIconConstraints: const BoxConstraints(minWidth: 38),
          border: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
