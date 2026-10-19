import 'package:flutter/material.dart';

/// Shared geometry for all three settings menus, with a right-aligned trigger
/// and left-aligned options. Popup routes remain within the screen's safe area.
class SettingsDropdown<T> extends StatelessWidget {
  const SettingsDropdown(
      {super.key,
      required this.value,
      required this.options,
      required this.onChanged});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
        fontSize: 14, fontWeight: FontWeight.w400, color: scheme.onSurface);
    return PopupMenuButton<T>(
      tooltip: '选择${options[value]}',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 176, maxWidth: 176),
      menuPadding: const EdgeInsets.symmetric(vertical: 8),
      padding: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final option in options.entries)
          PopupMenuItem<T>(
              value: option.key,
              height: 48,
              padding: EdgeInsets.zero,
              child: Container(
                  height: 48,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  color: option.key == value ? scheme.primaryContainer : null,
                  child: Text(option.value, style: style))),
      ],
      child: SizedBox(
          width: 100,
          height: 48,
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Flexible(
                child: Text(options[value] ?? '',
                    style: style, textAlign: TextAlign.right)),
            Icon(Icons.arrow_drop_down,
                color: scheme.onSurfaceVariant, size: 24),
          ])),
    );
  }
}
