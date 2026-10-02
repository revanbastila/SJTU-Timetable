import 'package:flutter/material.dart';

/// Eight shortcuts only. The full list retains all original entries/callbacks.
class CommonWebsiteGrid extends StatelessWidget {
  const CommonWebsiteGrid(
      {super.key,
      required this.tiles,
      this.iconForTile,
      this.useThemeLabelColor = false,
      this.topPadding = 10});
  final List<ListTile> tiles;
  final IconData? Function(ListTile)? iconForTile;
  // TEMPORARY 1.14.22.4 visual test; remove with the title toggle.
  final bool useThemeLabelColor;
  final double topPadding;

  String _label(ListTile tile) {
    final fullName = (tile.title as Text).data ?? '';
    return switch (fullName) {
      'Canvas教学平台' => 'Canvas',
      '传承·交大' => '传承交大',
      _ => fullName,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = tiles.take(8).toList();
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 6.0;
      final side = (constraints.maxWidth - gap * 3) / 4;
      final iconSize = (side * .42).clamp(22.0, 34.0);
      // Previously the 21px glyph was fitted with its 38px backing tile.
      // Double that glyph alone, centered on the unchanged layout slot.
      final glyphSize = iconSize * 21 / 38 * 2;
      final topInset = (side * .10).clamp(6.0, 10.0);
      final labelHeight = side - topInset - 4 - iconSize - 4;
      final scaler = MediaQuery.textScalerOf(context);
      final inheritedStyle = DefaultTextStyle.of(context).style;
      // Four glyphs plus 0.8 glyph of clearance on each side. Keep one size
      // for all labels, including with accessibility text scaling.
      var fontSize = (side / 5.6 / scaler.scale(1)).clamp(5.0, 14.5);
      TextStyle style({bool adjusted = false}) => TextStyle(
          fontSize: fontSize * (adjusted ? 1.1 : 1),
          // Preserve the font's shaping/kerning; compress the existing tracking.
          letterSpacing:
              adjusted ? (inheritedStyle.letterSpacing ?? 0) * .9 : null,
          height: 1.1,
          fontWeight: FontWeight.w400,
          color: useThemeLabelColor ? scheme.primary : scheme.onSurface);
      // One consistent size for all labels, without ellipsis or changing squares.
      while (fontSize > 5) {
        final fits = entries.every((tile) {
          final painter = TextPainter(
              text: TextSpan(text: _label(tile), style: style()),
              textDirection: Directionality.of(context),
              maxLines: 1,
              textScaler: scaler)
            ..layout(maxWidth: side - 8);
          final fits =
              painter.height <= labelHeight && !painter.didExceedMaxLines;
          painter.dispose();
          return fits;
        });
        if (fits) break;
        fontSize -= .25;
      }
      return Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: Column(children: [
          for (var start = 0; start < entries.length; start += 4) ...[
            if (start > 0) const SizedBox(height: gap),
            Row(children: [
              for (var column = 0; column < 4; column++) ...[
                if (column > 0) const SizedBox(width: gap),
                SizedBox(
                  width: side,
                  height: side,
                  child: start + column >= entries.length
                      ? null
                      : Material(
                          key: ValueKey('website-grid-tile-${start + column}'),
                          color: scheme.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: scheme.outlineVariant)),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: entries[start + column].onTap,
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(4, topInset, 4, 4),
                              child: Column(children: [
                                SizedBox(
                                    key: ValueKey(
                                        'website-icon-slot-${start + column}'),
                                    width: iconSize,
                                    height: iconSize,
                                    child: OverflowBox(
                                      minWidth: glyphSize,
                                      maxWidth: glyphSize,
                                      minHeight: glyphSize,
                                      maxHeight: glyphSize,
                                      child: Icon(
                                        iconForTile?.call(
                                                entries[start + column]) ??
                                            (entries[start + column].leading
                                                    is Icon
                                                ? (entries[start + column]
                                                        .leading as Icon)
                                                    .icon
                                                : null),
                                        key: ValueKey(
                                            'website-icon-${start + column}'),
                                        size: glyphSize,
                                        color: scheme.primary,
                                      ),
                                    )),
                                const SizedBox(height: 4),
                                Expanded(
                                    child: Center(
                                        child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: SizedBox(
                                    width: side - 8,
                                    child: Text(_label(entries[start + column]),
                                        maxLines: 1,
                                        softWrap: false,
                                        textAlign: TextAlign.center,
                                        style: style(adjusted: true)),
                                  ),
                                ))),
                              ]),
                            ),
                          ),
                        ),
                ),
              ],
            ]),
          ],
        ]),
      );
    });
  }
}
