import '../models/course.dart';
import '../models/periods.dart';

/// Merges duplicate fragments and enriches scheduled DOM rows with metadata
/// captured from the portal's JSON responses.
List<Course> normalizePortalCourses(List<Course> input, {int totalWeeks = 18}) {
  String normalized(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '');

  String stableCode(String value) {
    final match = RegExp(r'[A-Za-z]+\d+').firstMatch(value);
    return match == null ? normalized(value) : normalized(match.group(0)!);
  }

  bool sameCourse(Course first, Course second) {
    if (first.courseCode.isNotEmpty && second.courseCode.isNotEmpty) {
      final firstCode = stableCode(first.courseCode);
      final secondCode = stableCode(second.courseCode);
      if (firstCode.isNotEmpty && secondCode.isNotEmpty) {
        return firstCode == secondCode;
      }
    }
    if (first.sourceCourseId.isNotEmpty && second.sourceCourseId.isNotEmpty) {
      if (normalized(first.sourceCourseId) ==
          normalized(second.sourceCourseId)) {
        return true;
      }
    }
    return normalized(first.name).isNotEmpty &&
        normalized(first.name) == normalized(second.name);
  }

  String useful(Iterable<String> values, {String placeholder = ''}) {
    final candidates = values
        .where((value) => value.isNotEmpty && value != placeholder)
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return candidates.isEmpty ? '' : candidates.first;
  }

  final merged = <String, Course>{};
  for (final course in input) {
    final key = [
      course.courseIdentity,
      course.weekday,
      course.startMinutes,
      course.endMinutes,
    ].join('|');
    final previous = merged[key];
    if (previous == null) {
      merged[key] = course;
      continue;
    }

    final weeks = previous.weeksInferred && !course.weeksInferred
        ? course.activeWeeks
        : (!previous.weeksInferred && course.weeksInferred
            ? previous.activeWeeks
            : ({...previous.activeWeeks, ...course.activeWeeks}.toList()
              ..sort()));
    final map = previous.toMap()
      ..['name'] = useful([previous.name, course.name], placeholder: '未命名课程')
      ..['teacher'] = useful([previous.teacher, course.teacher])
      ..['location'] = useful([previous.location, course.location])
      ..['time'] = useful([previous.time, course.time])
      ..['rawWeekText'] = useful([previous.rawWeekText, course.rawWeekText])
      ..['sourceCourseId'] =
          useful([previous.sourceCourseId, course.sourceCourseId])
      ..['courseCode'] = useful([previous.courseCode, course.courseCode])
      ..['activeWeeks'] = weeks
      ..['weeksInferred'] = previous.weeksInferred && course.weeksInferred;
    merged[key] = Course.fromMap(map, totalWeeks: totalWeeks);
  }

  final meetings = merged.values.toList();
  final enriched = <Course>[];
  for (final course in meetings) {
    final related = input.where((candidate) => sameCourse(course, candidate));
    final map = course.toMap()
      ..['name'] =
          useful(related.map((item) => item.name), placeholder: '未命名课程')
      ..['teacher'] = course.teacher.isNotEmpty
          ? course.teacher
          : useful(related.map((item) => item.teacher))
      ..['location'] = course.location.isNotEmpty
          ? course.location
          : useful(related.map((item) => item.location))
      ..['sourceCourseId'] = useful(related.map((item) => item.sourceCourseId))
      ..['courseCode'] = useful(related.map((item) => item.courseCode));
    enriched.add(Course.fromMap(map, totalWeeks: totalWeeks));
  }

  final usable = [
    for (final course in enriched)
      if (course.hasSchedule ||
          !enriched
              .any((other) => other.hasSchedule && sameCourse(course, other)))
        course,
  ];

  bool sameWeeks(Course first, Course second) {
    final a = {...first.activeWeeks};
    final b = {...second.activeWeeks};
    return a.length == b.length && a.containsAll(b);
  }

  bool canJoin(Course first, Course second) {
    String teacherKey(String value) {
      final names = value
          .replaceAll(RegExp(r'^(?:授课教师|任课教师|教师)\s*[:：]?\s*'), '')
          .split(RegExp(r'[、,，;；/|\n]+'))
          .map(normalized)
          .where((name) => name.isNotEmpty)
          .toList()
        ..sort();
      return names.join('|');
    }

    final teacher = teacherKey(first.teacher);
    final location = normalized(first.location);
    return first.hasSchedule &&
        second.hasSchedule &&
        sameCourse(first, second) &&
        first.weekday == second.weekday &&
        teacher.isNotEmpty &&
        location.isNotEmpty &&
        teacher == teacherKey(second.teacher) &&
        location == normalized(second.location) &&
        sameWeeks(first, second) &&
        second.firstPeriod == first.lastPeriod + 1;
  }

  final scheduled = usable.where((course) => course.hasSchedule).toList()
    ..sort((a, b) {
      final day = a.weekday.compareTo(b.weekday);
      if (day != 0) return day;
      final start = a.startMinutes.compareTo(b.startMinutes);
      if (start != 0) return start;
      return a.id.compareTo(b.id);
    });
  final joined = <Course>[];
  for (final course in scheduled) {
    if (joined.isEmpty || !canJoin(joined.last, course)) {
      joined.add(course);
      continue;
    }
    final previous = joined.removeLast();
    final map = previous.toMap()
      ..['endHour'] = course.endHour
      ..['endMinute'] = course.endMinute
      ..['time'] =
          '${clockLabel(previous.startMinutes)}–${clockLabel(course.endMinutes)}'
      ..['canvasCourseId'] = previous.canvasCourseId ?? course.canvasCourseId;
    joined.add(Course.fromMap(map, totalWeeks: totalWeeks));
  }

  return [
    ...joined,
    ...usable.where((course) => !course.hasSchedule),
  ];
}
