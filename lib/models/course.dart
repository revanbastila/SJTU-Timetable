import 'periods.dart';
import 'week_rules.dart';

class Course {
  const Course({
    required this.id,
    required this.name,
    required this.teacher,
    required this.location,
    required this.time,
    required this.weekday,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    required this.activeWeeks,
    required this.rawWeekText,
    required this.courseIdentity,
    this.sourceCourseId = '',
    this.courseCode = '',
    this.canvasCourseId,
    this.weeksInferred = false,
  });

  final String id, name, teacher, location, time;
  final String courseIdentity, sourceCourseId, courseCode, rawWeekText;
  final String? canvasCourseId;
  final List<int> activeWeeks;
  final bool weeksInferred;
  final int weekday, startHour, startMinute, endHour, endMinute;

  int get startMinutes => startHour * 60 + startMinute;
  int get endMinutes => endHour * 60 + endMinute;
  bool get hasSchedule =>
      weekday >= 1 &&
      weekday <= 7 &&
      startHour >= 0 &&
      startHour < 24 &&
      startMinute >= 0 &&
      startMinute < 60 &&
      endHour >= 0 &&
      endHour < 24 &&
      endMinute >= 0 &&
      endMinute < 60 &&
      endMinutes > startMinutes;
  int get firstPeriod => periodEnds.indexWhere((end) => end > startMinutes) + 1;
  int get lastPeriod =>
      periodStarts.lastIndexWhere((start) => start < endMinutes) + 1;
  bool isActiveInWeek(int week) => activeWeeks.contains(week);

  Course copyWith({String? canvasCourseId, bool clearCanvasCourse = false}) =>
      Course(
        id: id,
        name: name,
        teacher: teacher,
        location: location,
        time: time,
        weekday: weekday,
        startHour: startHour,
        startMinute: startMinute,
        endHour: endHour,
        endMinute: endMinute,
        activeWeeks: activeWeeks,
        rawWeekText: rawWeekText,
        courseIdentity: courseIdentity,
        sourceCourseId: sourceCourseId,
        courseCode: courseCode,
        canvasCourseId:
            clearCanvasCourse ? null : (canvasCourseId ?? this.canvasCourseId),
        weeksInferred: weeksInferred,
      );

  factory Course.fromMap(Map<String, dynamic> map,
      {int index = 0, int totalWeeks = 18}) {
    String normalizedKey(Object? value) => '${value ?? ''}'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '');

    String compact(dynamic value) {
      if (value == null) return '';
      if (value is String || value is num || value is bool) {
        return '$value'.replaceAll(RegExp(r'\s+'), ' ').trim();
      }
      if (value is List) {
        return value.map(compact).where((item) => item.isNotEmpty).join('、');
      }
      if (value is Map) {
        const preferred = [
          'name',
          '姓名',
          '名称',
          'xm',
          'jsxm',
          'jsmc',
          'teacherName',
          'text',
          'label',
          'value',
          'title'
        ];
        for (final wanted in preferred) {
          for (final entry in value.entries) {
            if (normalizedKey(entry.key) == normalizedKey(wanted)) {
              final rendered = compact(entry.value);
              if (rendered.isNotEmpty) return rendered;
            }
          }
        }
        return value.values
            .map(compact)
            .where((item) => item.isNotEmpty)
            .join('、');
      }
      return '$value'.trim();
    }

    String field(List<String> keys) {
      final aliases = keys.map(normalizedKey).where((key) => key.isNotEmpty);
      for (final alias in aliases) {
        for (final entry in map.entries) {
          if (normalizedKey(entry.key) == alias) {
            final rendered = compact(entry.value);
            if (rendered.isNotEmpty) return rendered;
          }
        }
      }
      const suffixAliases = {
        'kcmc',
        'kcm',
        'kch',
        'jsxm',
        'jsmc',
        'skjs',
        'skjsxm',
        'rkjs',
        'rkjsxm',
        'skdd',
        'jxcd',
        'jxdd',
        'jasmc',
        'sksj',
        'xqj',
        'ksjc',
        'jsjc',
        'zcmc',
        'jxbid',
        'kcid',
      };
      for (final alias in aliases) {
        if (!suffixAliases.contains(alias)) continue;
        for (final entry in map.entries) {
          final key = normalizedKey(entry.key);
          if (key.endsWith(alias)) {
            final rendered = compact(entry.value);
            if (rendered.isNotEmpty) return rendered;
          }
        }
      }
      return '';
    }

    int number(dynamic value) => int.tryParse('$value') ?? 0;
    final rawName =
        field(['name', 'courseName', 'course_name', '课程名称', '课程名', 'KCMC']);
    var code = field(
        ['courseCode', 'course_code', 'code', '课程代码', '课程编号', '课号', 'KCH']);
    var name = rawName;
    final bracketedCode = RegExp(
      r'^(.*?)\s*[（(【\[]\s*([A-Za-z][A-Za-z0-9._-]*\d[A-Za-z0-9._-]*)\s*[）)】\]]\s*$',
    ).firstMatch(name);
    if (bracketedCode != null) {
      name = bracketedCode[1]!.trim();
      code = bracketedCode[2]!.trim();
    } else if (code.isNotEmpty) {
      name = name
          .replaceFirst(
              RegExp(
                r'[\s（(【\[]*' + RegExp.escape(code) + r'[）)】\]]*\s*$',
                caseSensitive: false,
              ),
              '')
          .trim();
    } else {
      final trailing = RegExp(
        r'^(.*?)\s+[（(【\[]?([A-Za-z][A-Za-z0-9._-]{3,})[）)】\]]?\s*$',
      ).firstMatch(name);
      final candidate = trailing?[2] ?? '';
      if (trailing != null &&
          RegExp(r'[A-Za-z]').hasMatch(candidate) &&
          RegExp(r'\d').hasMatch(candidate)) {
        name = trailing[1]!.trim();
        code = candidate;
      }
    }
    final time = field(['time', 'schedule', '上课时间', 'SKSJ']);
    final dayText = field(['weekday', 'dayOfWeek', '星期', 'XQJ']);
    final dayMatch =
        RegExp(r'(?:星期|礼拜|周)\s*([一二三四五六日天1-7])').firstMatch('$dayText $time');
    var day = number(dayText);
    if (day == 0 && dayMatch != null) {
      final token = dayMatch[1]!;
      day = int.tryParse(token) ??
          (token == '天' ? 7 : '一二三四五六日'.indexOf(token) + 1);
    }
    if (day < 1 || day > 7) day = 0;
    final sections =
        RegExp(r'(?:第\s*)?(\d{1,2})(?:\s*[-~～—–至、,]\s*(\d{1,2}))?\s*节')
            .firstMatch(time);
    final startPeriodText = field(['startPeriod', '开始节次', '起始节次', 'KSJC']);
    final endPeriodText = field(['endPeriod', '结束节次', '终止节次', 'JSJC']);
    final first =
        number(startPeriodText.isNotEmpty ? startPeriodText : sections?[1]);
    final last = number(endPeriodText.isNotEmpty
        ? endPeriodText
        : (sections?[2] ?? sections?[1] ?? first));
    final clocks = RegExp(r'(\d{1,2})[:：](\d{2})').allMatches(time).toList();
    int clock(int i) =>
        int.parse(clocks[i][1]!) * 60 + int.parse(clocks[i][2]!);
    var start = -60;
    var end = -60;
    if (map['startHour'] != null && map['endHour'] != null) {
      start = number(map['startHour']) * 60 + number(map['startMinute']);
      end = number(map['endHour']) * 60 + number(map['endMinute']);
    } else if (clocks.length >= 2) {
      start = clock(0);
      end = clock(1);
    } else if (first >= 1 &&
        first <= periodStarts.length &&
        last >= first &&
        last <= periodEnds.length) {
      start = periodStarts[first - 1];
      end = periodEnds[last - 1];
    }

    final savedWeeks = map['activeWeeks'];
    final explicitWeekText =
        field(['rawWeekText', 'weeks', 'weekText', '上课周次', '周次', 'ZCMC']);
    final parsedRule = parseWeekRule(
      explicitWeekText.isEmpty ? time : explicitWeekText,
      totalWeeks: totalWeeks,
    );
    final activeWeeks = savedWeeks is List
        ? savedWeeks.map((value) => number(value)).where((v) => v > 0).toList()
        : parsedRule.weeks;
    final sourceCourseId = field([
      'sourceCourseId',
      'portalCourseId',
      'courseId',
      'course_id',
      '教学班ID',
      '教学班编号',
      '课程ID',
      'JXBID',
      'KCID',
    ]);
    final identity = field(['courseIdentity']).isNotEmpty
        ? field(['courseIdentity'])
        : (_identity(sourceCourseId.isNotEmpty
                    ? sourceCourseId
                    : (code.isNotEmpty ? code : name))
                .isNotEmpty
            ? _identity(sourceCourseId.isNotEmpty
                ? sourceCourseId
                : (code.isNotEmpty ? code : name))
            : 'portalunknown$index');
    return Course(
      id: field(['id']).isEmpty
          ? 'portal-$index-$identity-$day-$start'
          : field(['id']),
      name: name.isEmpty ? '未命名课程' : name,
      teacher: field([
        'teacher',
        'teacherName',
        'teacher_name',
        'teachers',
        'instructor',
        'instructors',
        '任课教师',
        '授课教师',
        '教师',
        '老师',
        '教师姓名',
        '教师名称',
        '教师列表',
        'SKJS',
        'SKJSXM',
        'RKJS',
        'RKJSXM',
        'XM',
        'JSXM',
        'JSMC',
      ]),
      location: field([
        'location',
        'classroom',
        'room',
        'building',
        '上课地点',
        '上课教室',
        '教室',
        '地点',
        '课室',
        '教学楼',
        '教室名称',
        'JASMC',
        'SKDD',
        'JXCD',
        'JXDD',
      ]),
      time: time,
      weekday: day,
      startHour: start ~/ 60,
      startMinute: start < 0 ? 0 : start % 60,
      endHour: end ~/ 60,
      endMinute: end < 0 ? 0 : end % 60,
      activeWeeks: activeWeeks.isEmpty
          ? List<int>.generate(totalWeeks, (i) => i + 1)
          : activeWeeks,
      rawWeekText: field(['rawWeekText']).isNotEmpty
          ? field(['rawWeekText'])
          : (explicitWeekText.isNotEmpty
              ? explicitWeekText
              : parsedRule.rawText),
      courseIdentity: identity,
      sourceCourseId: sourceCourseId,
      courseCode: code,
      canvasCourseId:
          field(['canvasCourseId']).isEmpty ? null : field(['canvasCourseId']),
      weeksInferred: map['weeksInferred'] is bool
          ? map['weeksInferred'] as bool
          : parsedRule.inferred,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'teacher': teacher,
        'location': location,
        'time': time,
        'weekday': weekday,
        'startHour': startHour,
        'startMinute': startMinute,
        'endHour': endHour,
        'endMinute': endMinute,
        'activeWeeks': activeWeeks,
        'rawWeekText': rawWeekText,
        'courseIdentity': courseIdentity,
        'sourceCourseId': sourceCourseId,
        'courseCode': courseCode,
        'canvasCourseId': canvasCourseId,
        'weeksInferred': weeksInferred,
      };

  static String _identity(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');

  static List<Course> demo() => [];
}
