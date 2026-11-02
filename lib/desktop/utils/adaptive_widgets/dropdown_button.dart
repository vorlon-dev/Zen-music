// ZenMusic · vorlon-dev

import 'package:flutter/material.dart';

class AdaptiveDropdownMenuItem<T> {
  final T value;
  final Widget child;
  const AdaptiveDropdownMenuItem({
    required this.value,
    required this.child,
  });
}

class AdaptiveDropdownButton<T> extends StatelessWidget {
  final T value;
  final List<AdaptiveDropdownMenuItem<T>> items;
  final void Function(T?)? onChanged;

  const AdaptiveDropdownButton({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T>(
      value: value,
      items: items
          .map((item) => DropdownMenuItem<T>(
        value: item.value,
        child: item.child,
      ))
          .toList(),
      onChanged: onChanged,
    );
  }
}
