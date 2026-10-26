import 'package:flutter/material.dart';

/// Kept in the page's Column, outside the native WebView capture rectangle.
class AttendanceVideoStatus extends StatelessWidget {
  const AttendanceVideoStatus({
    super.key,
    required this.message,
    required this.manual,
    required this.onUseCurrentView,
  });

  final String message;
  final bool manual;
  final VoidCallback onUseCurrentView;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.desktop_windows_outlined,
                size: 20, color: colors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurface,
                      )),
            ),
            if (!manual) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: onUseCurrentView,
                child: const Text('手动选择'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
