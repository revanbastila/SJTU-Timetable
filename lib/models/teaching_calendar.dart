import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;

import 'course.dart';
import 'week_rules.dart';

bool _zonesReady = false;
tz.Location _shanghai() {
  if (!_zonesReady) {
    data.initializeTimeZones();
    _zonesReady = true;
  }
  return tz.getLocation('Asia/Shanghai');
}

DateTime shanghaiNow() => tz.TZDateTime.now(_shanghai());
DateTime calendarCivilDate(DateTime date) {
  // Plain local date values are civil timetable dates, not UTC instants.
  final value = date.isUtc || date is tz.TZDateTime
      ? tz.TZDateTime.from(date, _shanghai())
      : date;
  return DateTime(value.year, value.month, value.day);
}

DateTime nextShanghaiMidnight(DateTime now) =>
    tz.TZDateTime(_shanghai(), now.year, now.month, now.day + 1);
String calendarDateKey(DateTime date) {
  final day = calendarCivilDate(date);
  return '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}

class TeachingDateRule {
  const TeachingDateRule(this.date, this.type, this.name,
      {this.useWeekday, this.useWeek});
  final DateTime date;
  final String type, name;
  final int? useWeekday, useWeek;
  String get label => switch (type) {
        'holiday' => '放假',
        'no_class' => '停课',
        _ => '调休',
      };
  String? get emptyMessage => switch (type) {
        'holiday' => '今日放假，暂无课程',
        'no_class' => '今日停课',
        _ => null,
      };
  String? get makeupMessage {
    if (type != 'makeup') return null;
    final day = useWeekday;
    if (day == null || day < 1 || day > 7) return '今日调休，请注意课程安排';
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '今日调休，请按${weekdays[day - 1]}课程安排上课';
  }
}

/// Remote semester metadata. Dates are Shanghai civil dates, including years
/// on both sides of New Year; exam weeks are labels only.
class TeachingSemester {
  TeachingSemester(this.id, this.name, this.startDate, this.endDate,
      this.firstWeekStart, this.totalWeeks, Iterable<int> examWeeks)
      : examWeeks = List.unmodifiable(examWeeks.toSet().toList()..sort());
  final String id, name;
  final DateTime startDate, endDate, firstWeekStart;
  final int totalWeeks;
  final List<int> examWeeks;

  bool contains(DateTime date) {
    final day = calendarCivilDate(date);
    return !day.isBefore(startDate) && !day.isAfter(endDate);
  }

  int? weekFor(DateTime date) {
    final day = calendarCivilDate(date);
    if (!contains(day) || day.isBefore(firstWeekStart)) return null;
    return (day.difference(firstWeekStart).inDays ~/ 7 + 1)
        .clamp(1, totalWeeks);
  }

  factory TeachingSemester.parse(String id, Map raw, String academicYear) {
    DateTime date(String field) {
      final value = raw[field];
      final parsed = value is String ? DateTime.tryParse(value) : null;
      if (parsed == null || calendarDateKey(parsed) != value) {
        throw FormatException('invalid semester $id $field');
      }
      return calendarCivilDate(parsed);
    }

    final start = date('start_date');
    final end = date('end_date');
    final first = date('first_week_start');
    final weeks = raw['total_weeks'];
    final exams = raw['exam_weeks'] ?? const [];
    if (start.isAfter(end) ||
        first.isAfter(end) ||
        first.weekday != DateTime.monday ||
        end.difference(first).inDays > 420 ||
        weeks is! int ||
        weeks < 1 ||
        weeks > 60 ||
        exams is! List ||
        exams.any((week) => week is! int || week < 1 || week > weeks)) {
      throw FormatException('invalid semester $id metadata');
    }
    final label =
        switch (id) { 'fall' => '秋季学期', 'spring' => '春季学期', _ => '夏季学期' };
    return TeachingSemester(
        id,
        raw['name'] is String && (raw['name'] as String).trim().isNotEmpty
            ? raw['name'] as String
            : '$academicYear$label',
        start,
        end,
        first,
        weeks,
        exams.cast<int>());
  }
}

/// The only rule interpreter. Native widgets consume its dated results.
class TeachingCalendar {
  const TeachingCalendar.empty()
      : version = '',
        updatedAt = '',
        fingerprint = '',
        academicYear = '',
        semesters = const {},
        rules = const {};
  TeachingCalendar._(
      this.version,
      this.updatedAt,
      this.fingerprint,
      Map<String, TeachingDateRule> rules,
      this.academicYear,
      Map<String, TeachingSemester> semesters)
      : rules = Map.unmodifiable(rules),
        semesters = Map.unmodifiable(semesters);
  final String version;
  final String updatedAt, fingerprint;
  final Map<String, TeachingDateRule> rules;
  final String academicYear;
  final Map<String, TeachingSemester> semesters;

  factory TeachingCalendar.parse(String text) {
    final raw = jsonDecode(text);
    if (raw is! Map || raw['rules'] is! List) {
      throw const FormatException('calendar must contain rules');
    }
    final version = raw['version'];
    if (!((version is int && version >= 0) ||
        (version is String && version.trim().isNotEmpty))) {
      throw const FormatException('calendar version is invalid');
    }
    final entries = raw['rules'] as List;
    if (entries.length > 5000) {
      throw const FormatException('too many calendar rules');
    }
    final rules = <String, TeachingDateRule>{};
    for (final row in entries) {
      if (row is! Map || row['date'] is! String) {
        throw const FormatException('invalid calendar date');
      }
      final key = row['date'] as String;
      final date = DateTime.tryParse(key);
      if (date == null ||
          calendarDateKey(date) != key ||
          rules.containsKey(key)) {
        throw const FormatException('invalid or duplicate calendar date');
      }
      final type = row['type'];
      if (!const ['holiday', 'no_class', 'makeup'].contains(type)) {
        throw const FormatException('unsupported calendar rule');
      }
      final day = row['use_weekday'];
      final week = row['use_week'];
      if (type == 'makeup' &&
          ((day != null && (day is! int || day < 1 || day > 7)) ||
              (week != null && (week is! int || week < 1 || week > 60)))) {
        throw const FormatException('invalid makeup weekday/week');
      }
      rules[key] = TeachingDateRule(date, type as String,
          row['name'] is String ? row['name'] as String : '',
          useWeekday: type == 'makeup' ? day as int? : null,
          useWeek: type == 'makeup' ? week as int? : null);
    }
    final academicYear =
        raw['academic_year'] is String ? raw['academic_year'] as String : '';
    final semesters = <String, TeachingSemester>{};
    final semesterData = raw['semesters'];
    if (semesterData != null) {
      if (semesterData is! Map) {
        throw const FormatException('invalid semesters');
      }
      for (final id in ['fall', 'spring', 'summer']) {
        final value = semesterData[id];
        if (value == null) continue;
        if (value is! Map) throw FormatException('invalid semester $id');
        final semester = TeachingSemester.parse(id, value, academicYear);
        if (semesters.values.any((other) =>
            !semester.endDate.isBefore(other.startDate) &&
            !semester.startDate.isAfter(other.endDate))) {
          throw const FormatException('overlapping semesters');
        }
        semesters[id] = semester;
      }
    }
    return TeachingCalendar._(
        '$version',
        '${raw['updated_at'] ?? ''}',
        sha256.convert(utf8.encode(jsonEncode(raw))).toString(),
        rules,
        academicYear,
        semesters);
  }

  TeachingSemester? semesterFor(DateTime date) {
    for (final semester in semesters.values) {
      if (semester.contains(date)) return semester;
    }
    return null;
  }

  TeachingSemester? semesterForTerm(DateTime firstMonday) {
    for (final semester in semesters.values) {
      if (semester.firstWeekStart == calendarCivilDate(firstMonday)) {
        return semester;
      }
    }
    return null;
  }

  int? weekForDate(DateTime date, DateTime termStart, int totalWeeks) {
    final semester = semesterForTerm(termStart);
    return semester != null
        ? semester.weekFor(date)
        : academicWeekInTerm(calendarCivilDate(date), termStart, totalWeeks);
  }

  /// Shared date horizon for reminders and precomputed native widget days.
  Iterable<DateTime> datesForTerm(DateTime start, int weeks) sync* {
    start = calendarCivilDate(start);
    final end = semesterForTerm(start)?.endDate ??
        DateTime(start.year, start.month, start.day + weeks * 7 - 1);
    for (var day = start;
        !day.isAfter(end);
        day = DateTime(day.year, day.month, day.day + 1)) {
      yield day;
    }
  }

  TeachingDateRule? ruleFor(DateTime date) => rules[calendarDateKey(date)];

  List<Course> getEffectiveCoursesForDate(DateTime date, List<Course> original,
      DateTime termStart, int totalWeeks) {
    date = calendarCivilDate(date);
    final rule = ruleFor(date);
    if (rule?.emptyMessage != null) return const [];
    // The remote calendar spans multiple semesters. A source-week override
    // selects a week within this term, not a different semester's courses.
    final actualWeek = weekForDate(date, termStart, totalWeeks);
    if (actualWeek == null) return const [];
    final week = rule?.useWeek ?? actualWeek;
    if (week < 1 || week > totalWeeks) return const [];
    final weekday = rule?.useWeekday ?? date.weekday;
    final result = original
        .where((course) =>
            course.hasSchedule &&
            course.weekday == weekday &&
            course.isActiveInWeek(week))
        .toList();
    result.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return result;
  }
}
