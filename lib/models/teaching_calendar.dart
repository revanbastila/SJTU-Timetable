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
}

/// The only rule interpreter. Native widgets consume its dated results.
class TeachingCalendar {
  const TeachingCalendar.empty()
      : version = '',
        updatedAt = '',
        fingerprint = '',
        rules = const {};
  TeachingCalendar._(this.version, this.updatedAt, this.fingerprint,
      Map<String, TeachingDateRule> rules)
      : rules = Map.unmodifiable(rules);
  final String version;
  final String updatedAt, fingerprint;
  final Map<String, TeachingDateRule> rules;

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
          (day is! int ||
              day < 1 ||
              day > 7 ||
              (week != null && (week is! int || week < 1 || week > 60)))) {
        throw const FormatException('invalid makeup weekday/week');
      }
      rules[key] = TeachingDateRule(date, type as String,
          row['name'] is String ? row['name'] as String : '',
          useWeekday: type == 'makeup' ? day as int : null,
          useWeek: type == 'makeup' ? week as int? : null);
    }
    return TeachingCalendar._('$version', '${raw['updated_at'] ?? ''}',
        sha256.convert(utf8.encode(jsonEncode(raw))).toString(), rules);
  }

  TeachingDateRule? ruleFor(DateTime date) => rules[calendarDateKey(date)];

  List<Course> getEffectiveCoursesForDate(DateTime date, List<Course> original,
      DateTime termStart, int totalWeeks) {
    date = calendarCivilDate(date);
    final rule = ruleFor(date);
    if (rule?.emptyMessage != null) return const [];
    // The remote calendar spans multiple semesters. A source-week override
    // selects a week within this term, not a different semester's courses.
    final actualWeek = academicWeekInTerm(date, termStart, totalWeeks);
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
