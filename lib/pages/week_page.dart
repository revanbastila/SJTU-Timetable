import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/app_theme.dart';
import '../models/course.dart';
import '../models/periods.dart';
import '../models/week_rules.dart';
import '../state/app_controller.dart';
import 'course_detail_page.dart';
import 'portal_sync_page.dart';

class WeekPage extends StatelessWidget {
  const WeekPage({super.key, required this.app});
  final AppController app;
  static const _days = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: app,
        builder: (context, _) {
          final currentWeek = app.currentAcademicWeekInTerm;
          final monday = mondayForAcademicWeek(app.termStart, app.selectedWeek);
          final sunday = monday.add(const Duration(days: 6));
          final visible = app
              .coursesForWeek(app.selectedWeek)
              .where((course) => course.hasSchedule)
              .toList();
          return SafeArea(
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
                child: Row(children: [
                  DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: app.selectedWeek,
                      icon: Icon(
                        Icons.arrow_drop_down_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      menuWidth: 190,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                      selectedItemBuilder: (context) => [
                        for (var week = 1; week <= app.totalWeeks; week++)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('第 $week 周'),
                          ),
                      ],
                      items: [
                        for (var week = 1; week <= app.totalWeeks; week++)
                          DropdownMenuItem(
                            value: week,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('第 $week 周'),
                                if (currentWeek == week) ...[
                                  const SizedBox(width: 5),
                                  Text(
                                    '（本周）',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) app.selectWeek(value);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${DateFormat('M.d').format(monday)}–${DateFormat('M.d').format(sunday)}',
                      key: const Key('week-date-range'),
                      style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                  if (currentWeek == null)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        app.currentTermStatus,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (currentWeek == app.selectedWeek)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        '本周',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: '同步教务与 Canvas',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PortalSyncPage(
                          username: app.username,
                          password: '',
                          app: app,
                          rememberMe: app.rememberMe,
                        ),
                      ),
                    ),
                    color: app.themeChoice
                        .primaryFor(Theme.of(context).brightness),
                    icon: const Icon(Icons.sync_rounded),
                  ),
                ]),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => _Timetable(
                    courses: visible,
                    viewportWidth: constraints.maxWidth,
                    colorFor: (course) => Color(app.courseColorValue(course)),
                    onCourseTap: (course) => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            CourseDetailPage(app: app, course: course),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          );
        },
      );
}

class _Timetable extends StatelessWidget {
  const _Timetable({
    required this.courses,
    required this.viewportWidth,
    required this.colorFor,
    required this.onCourseTap,
  });
  final List<Course> courses;
  final double viewportWidth;
  final Color Function(Course) colorFor;
  final ValueChanged<Course> onCourseTap;

  static const gutter = 46.0;
  static const headerHeight = 42.0;
  static const rowHeight = 66.0;

  @override
  Widget build(BuildContext context) {
    final dayWidth = (viewportWidth - gutter) / 5;
    final gridHeight = periodStarts.length * rowHeight;
    final scheme = Theme.of(context).colorScheme;
    // `outlineVariant` is generated from the selected theme in the app theme
    // factory; keep the grid on the same low-saturation accent in both modes.
    final gridLine = scheme.outlineVariant;
    return SingleChildScrollView(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: gutter,
          child: Column(children: [
            Container(
              height: headerHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                border: Border(
                  right: BorderSide(color: gridLine),
                  bottom: BorderSide(color: gridLine),
                ),
              ),
              child: Text('节次',
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
            for (var i = 0; i < periodStarts.length; i++)
              Container(
                height: rowHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  border: Border(
                    right: BorderSide(color: gridLine),
                    bottom: BorderSide(color: gridLine),
                  ),
                ),
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${i + 1}',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface)),
                    const SizedBox(height: 3),
                    Text(
                      '${clockLabel(periodStarts[i])}\n${clockLabel(periodEnds[i])}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 8.5,
                        height: 1.08,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: dayWidth * 7,
              child: Column(children: [
                Row(children: [
                  for (var day = 1; day <= 7; day++)
                    Container(
                      width: dayWidth,
                      height: headerHeight,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLowest,
                        border: Border(
                          right: BorderSide(color: gridLine),
                          bottom: BorderSide(color: gridLine),
                        ),
                      ),
                      child: Text(
                        WeekPage._days[day - 1],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: day > 5 && DateTime.now().weekday == day
                              ? Theme.of(context).colorScheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ]),
                SizedBox(
                  height: gridHeight,
                  child: Stack(children: [
                    Column(children: [
                      for (var period = 0;
                          period < periodStarts.length;
                          period++)
                        Row(children: [
                          for (var day = 0; day < 7; day++)
                            Container(
                              width: dayWidth,
                              height: rowHeight,
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerLowest,
                                border: Border(
                                  right: BorderSide(color: gridLine),
                                  bottom: BorderSide(color: gridLine),
                                ),
                              ),
                            ),
                        ]),
                    ]),
                    for (final course in courses.where((course) =>
                        course.firstPeriod > 0 &&
                        course.lastPeriod >= course.firstPeriod))
                      _positionedCourse(course, dayWidth),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _positionedCourse(Course course, double dayWidth) {
    final lane = _laneFor(course);
    final laneWidth = dayWidth / lane.count;
    return Positioned(
      left: (course.weekday - 1) * dayWidth + lane.index * laneWidth + 2,
      top: (course.firstPeriod - 1) * rowHeight + 2,
      width: laneWidth - 4,
      height: (course.lastPeriod - course.firstPeriod + 1) * rowHeight - 4,
      child: Material(
        color: colorFor(course),
        borderRadius: BorderRadius.circular(7),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onCourseTap(course),
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.15,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < rowHeight * 1.35;
                final nameStyle = TextStyle(
                  color: Colors.white,
                  fontSize: compact ? 9.6 : 10.5,
                  height: 1.08,
                  fontWeight: FontWeight.w800,
                );
                final nameLines = _textLineCount(
                  context,
                  course.name,
                  nameStyle,
                  constraints.maxWidth - 11,
                );
                final blankLines = (4 - nameLines).clamp(0, 3);
                final titleLineHeight =
                    (nameStyle.fontSize ?? 10.5) * (nameStyle.height ?? 1);
                return Padding(
                  padding: const EdgeInsets.fromLTRB(6, 5, 5, 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.name,
                        key: ValueKey('course-name-${course.id}'),
                        softWrap: true,
                        style: nameStyle,
                      ),
                      SizedBox(
                        key: ValueKey('course-title-space-${course.id}'),
                        height: blankLines * titleLineHeight,
                      ),
                      if (course.location.isNotEmpty) ...[
                        SizedBox(height: compact ? 2 : 4),
                        Text(
                          _locationLines(course.location),
                          softWrap: true,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: compact ? 8.2 : 9,
                            height: 1.1,
                          ),
                        ),
                      ],
                      if (course.teacher.isNotEmpty) ...[
                        SizedBox(height: compact ? 2 : 4),
                        Text(
                          _teacherLines(course.teacher),
                          softWrap: true,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: compact ? 8.2 : 9,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  int _textLineCount(
    BuildContext context,
    String text,
    TextStyle style,
    double maxWidth,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth);
    return painter.computeLineMetrics().length.clamp(1, 1000);
  }

  String _locationLines(String value) {
    final compact = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    final match = RegExp(
      r'^(.+?[\u4e00-\u9fff])\s*([A-Za-z]*\d[A-Za-z0-9._-]*)$',
    ).firstMatch(compact);
    return match == null ? compact : '${match[1]}\n${match[2]}';
  }

  String _teacherLines(String value) => value
      .split(RegExp(r'[，,、；;/]+'))
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .join('\n');

  ({int index, int count}) _laneFor(Course course) {
    final overlaps = courses.where((other) {
      if (other.weekday != course.weekday) return false;
      return other.firstPeriod <= course.lastPeriod &&
          course.firstPeriod <= other.lastPeriod;
    }).toList()
      ..sort((a, b) {
        final time = a.firstPeriod.compareTo(b.firstPeriod);
        return time != 0 ? time : a.id.compareTo(b.id);
      });
    return (
      index: overlaps.indexWhere((item) => item.id == course.id),
      count: overlaps.length
    );
  }
}
