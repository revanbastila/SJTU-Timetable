import 'dart:convert';

import 'course.dart';
import 'periods.dart';

/// A display-only projection. Imported courses and calendar consumers stay intact.
List<Course> semesterTimetableCourses(List<Course> courses) {
  final groups = <String, List<Course>>{};
  for (final course in courses.where((course) => course.hasSchedule)) {
    final key = jsonEncode([
      course.courseIdentity,
      course.name,
      course.teacher,
      course.location,
      course.weekday,
    ]);
    (groups[key] ??= []).add(course);
  }
  final result = <Course>[];
  for (final group in groups.values) {
    final slots = <String, Course>{};
    for (final course in group) {
      final key = '${course.startMinutes}:${course.endMinutes}';
      final previous = slots[key];
      slots[key] = previous == null
          ? course
          : _displayCourse(
              previous,
              weeks: {...previous.activeWeeks, ...course.activeWeeks}.toList(),
              rawWeekText: '${previous.rawWeekText},${course.rawWeekText}',
            );
    }
    final ordered = slots.values.toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    final joined = <Course>[];
    for (final course in ordered) {
      final previous = joined.isEmpty ? null : joined.last;
      final weeks = course.activeWeeks.toSet();
      if (previous != null &&
          weeks.length == previous.activeWeeks.toSet().length &&
          weeks.containsAll(previous.activeWeeks) &&
          course.firstPeriod > 0 &&
          previous.lastPeriod > 0 &&
          course.firstPeriod <= previous.lastPeriod + 1) {
        joined[joined.length - 1] = _displayCourse(
          previous,
          endMinutes: course.endMinutes > previous.endMinutes
              ? course.endMinutes
              : previous.endMinutes,
        );
      } else {
        joined.add(course);
      }
    }
    for (final course in joined) {
      // Preserve the source ID so course details still observe live Canvas links.
      result.add(_displayCourse(course));
    }
  }
  return result;
}

Course _displayCourse(
  Course source, {
  List<int>? weeks,
  int? endMinutes,
  String? rawWeekText,
}) {
  final sortedWeeks = (weeks ?? source.activeWeeks).toSet().toList()..sort();
  final end = endMinutes ?? source.endMinutes;
  return Course(
    id: source.id,
    name: source.name,
    teacher: source.teacher,
    location: source.location,
    time: endMinutes == null
        ? source.time
        : '${clockLabel(source.startMinutes)}–${clockLabel(end)}',
    weekday: source.weekday,
    startHour: source.startHour,
    startMinute: source.startMinute,
    endHour: end ~/ 60,
    endMinute: end % 60,
    activeWeeks: sortedWeeks,
    rawWeekText: rawWeekText ?? source.rawWeekText,
    courseIdentity: source.courseIdentity,
    sourceCourseId: source.sourceCourseId,
    courseCode: source.courseCode,
    canvasCourseId: source.canvasCourseId,
    weeksInferred: source.weeksInferred,
  );
}

String semesterCourseWeeks(Course course) {
  final weeks = course.activeWeeks.where((week) => week > 0).toSet().toList()
    ..sort();
  if (weeks.isEmpty) return course.rawWeekText;
  if (weeks.length == 1) return '第${weeks.single}周';
  bool sequence(int step) => List.generate(
        weeks.length - 1,
        (i) => i,
      ).every((i) => weeks[i + 1] - weeks[i] == step);
  if (sequence(1)) return '${weeks.first}-${weeks.last}周';
  // Explicit discrete week lists remain discrete, even if they happen to have
  // a regular stride. Declared odd/even rules retain their parity annotation.
  final declaresParity = RegExp(r'[单双]\s*周').hasMatch(course.rawWeekText);
  final discrete = RegExp(r'[,，、]').hasMatch(course.rawWeekText);
  if (sequence(2) && (declaresParity || !discrete)) {
    return '${weeks.first}-${weeks.last}周（${weeks.first.isOdd ? '单' : '双'}周）';
  }
  final ranges = <String>[];
  var start = weeks.first;
  var end = start;
  void appendRange() {
    ranges.add(start == end ? '$start周' : '$start-$end周');
  }

  for (final week in weeks.skip(1)) {
    if (week == end + 1) {
      end = week;
    } else {
      appendRange();
      start = end = week;
    }
  }
  appendRange();
  return ranges.join('，');
}
