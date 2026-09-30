import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/periods.dart';

class CourseTile extends StatelessWidget {
  const CourseTile(
      {super.key, required this.course, this.highlight = false, this.onTap});

  final Course course;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final highlightSurface =
        dark ? scheme.primaryContainer : _softThemeColor(scheme.primary, .94);
    final highlightBorder = dark
        ? scheme.primary.withValues(alpha: .58)
        : _softThemeColor(scheme.primary, .79);
    final normalBorder =
        dark ? scheme.outlineVariant : _softThemeColor(scheme.primary, .91);
    final surface = highlight
        ? highlightSurface
        : (dark ? scheme.surfaceContainer : Colors.white);
    final accent = highlight || dark
        ? scheme.primary
        : _softThemeColor(scheme.primary, .70);
    final header =
        Theme.of(context).appBarTheme.foregroundColor ?? scheme.primary;
    return Material(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: highlight ? highlightBorder : normalBorder)),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                    width: 58,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(clockLabel(course.startMinutes),
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: highlight
                                      ? scheme.primary
                                      : (dark ? scheme.onSurface : header))),
                          const SizedBox(height: 4),
                          Text(clockLabel(course.endMinutes),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: dark
                                      ? scheme.onSurfaceVariant
                                      : Color.alphaBlend(
                                          scheme.primary.withValues(alpha: .67),
                                          Colors.white))),
                        ])),
                Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(top: 6, right: 13),
                    decoration:
                        BoxDecoration(color: accent, shape: BoxShape.circle)),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(course.name,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface)),
                      const SizedBox(height: 9),
                      Wrap(spacing: 13, runSpacing: 5, children: [
                        if (course.location.isNotEmpty)
                          _Meta(
                              icon: Icons.location_on_outlined,
                              text: course.location,
                              color: scheme.primary),
                        if (course.teacher.isNotEmpty)
                          _Meta(
                              icon: Icons.person_outline,
                              text: course.teacher,
                              color: scheme.primary),
                      ]),
                    ])),
              ]),
            )));
  }
}

Color _softThemeColor(Color color, double whiteMix) =>
    Color.lerp(color, Colors.white, whiteMix)!;

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: color))
      ]);
}
