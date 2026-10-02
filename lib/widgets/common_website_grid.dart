import 'package:flutter/material.dart';

/// Displays the existing website entries without replacing their routes,
/// authentication flags, or callbacks. Rows grow for long/scaled labels.
class CommonWebsiteGrid extends StatelessWidget {
  const CommonWebsiteGrid({super.key, required this.tiles});
  final List<ListTile> tiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(children: [
        for (var start = 0; start < tiles.length; start += 3) ...[
          if (start > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (var column = 0; column < 3; column++) ...[
                if (column > 0) const SizedBox(width: 10),
                Expanded(
                  child: start + column < tiles.length
                      ? _tile(
                          tiles[start + column], start + column, theme, scheme)
                      : const SizedBox.shrink(),
                ),
              ],
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _tile(ListTile tile, int index, ThemeData theme, ColorScheme scheme) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: scheme.outlineVariant),
    );
    return Material(
      key: ValueKey('website-grid-tile-$index'),
      color: scheme.surfaceContainerLow,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: tile.onTap,
        customBorder: shape,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 112),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            child:
                Column(mainAxisAlignment: MainAxisAlignment.start, children: [
              if (tile.leading != null) tile.leading!,
              const SizedBox(height: 9),
              DefaultTextStyle.merge(
                style: theme.textTheme.labelLarge?.copyWith(
                    fontSize: 13, height: 1.3, color: scheme.onSurface),
                textAlign: TextAlign.center,
                child: tile.title ?? const SizedBox.shrink(),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
