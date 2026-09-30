import '../models/canvas_data.dart';
import '../models/course.dart';

class CourseMatcher {
  static List<Course> apply(
    List<Course> courses,
    List<CanvasCourseData> canvasCourses, {
    Map<String, String> manualMappings = const {},
  }) {
    return courses.map((course) {
      final code = _normalize(course.courseCode);
      if (code.isNotEmpty) {
        final exactCode = canvasCourses
            .where((item) => _normalize(item.courseCode) == code)
            .toList();
        if (exactCode.length == 1) {
          return course.copyWith(canvasCourseId: exactCode.single.id);
        }
        final baseCode = _baseCode(course.courseCode);
        if (baseCode.isNotEmpty) {
          final baseMatches = canvasCourses
              .where((item) => _baseCode(item.courseCode) == baseCode)
              .toList();
          if (baseMatches.length == 1) {
            return course.copyWith(canvasCourseId: baseMatches.single.id);
          }
        }
      }
      final sourceId = _normalize(course.sourceCourseId);
      if (sourceId.isNotEmpty) {
        final externalIdMatches = canvasCourses.where((item) {
          final sisId = _normalize(item.sisCourseId);
          final integrationId = _normalize(item.integrationId);
          return sisId == sourceId || integrationId == sourceId;
        }).toList();
        if (externalIdMatches.length == 1) {
          return course.copyWith(canvasCourseId: externalIdMatches.single.id);
        }
      }
      final name = _normalizeName(course.name);
      if (name.isNotEmpty) {
        final exactName = canvasCourses
            .where((item) => _normalizeName(item.name) == name)
            .toList();
        if (exactName.length == 1) {
          return course.copyWith(canvasCourseId: exactName.single.id);
        }
      }
      final manual = manualMappings[course.courseIdentity];
      if (manual != null && canvasCourses.any((item) => item.id == manual)) {
        return course.copyWith(canvasCourseId: manual);
      }
      final scored = canvasCourses
          .map((item) => (item, _dice(name, _normalizeName(item.name))))
          .where((entry) => entry.$2 >= .90)
          .toList()
        ..sort((a, b) => b.$2.compareTo(a.$2));
      if (scored.length == 1 ||
          (scored.isNotEmpty &&
              (scored.length == 1 || scored[0].$2 - scored[1].$2 >= .10))) {
        return course.copyWith(canvasCourseId: scored.first.$1.id);
      }
      return course.copyWith(clearCanvasCourse: true);
    }).toList();
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]'), '');

  static String _baseCode(String value) {
    final match = RegExp(r'[A-Za-z]+\d+').firstMatch(value);
    return match == null ? '' : _normalize(match.group(0)!);
  }

  static String _normalizeName(String value) {
    var cleaned = value
        .replaceAll(
            RegExp(r'[（(【\[][^）)】\]]*(?:班|section|教学班)[^）)】\]]*[）)】\]]',
                caseSensitive: false),
            '')
        .replaceAll(RegExp(r'(?:教学班|班级?)\s*\d+$'), '')
        .replaceAll(
            RegExp(
                r'(^|\s)20\d{2}\s*[-_/年]\s*20?\d{2}(?:\s*[-_/]\s*[123])?(?=\s|$)'),
            ' ')
        .trim();
    cleaned = cleaned
        .replaceAll(
            RegExp(r'^\s*[A-Za-z][A-Za-z0-9._-]*\d[A-Za-z0-9._-]*\s+'), '')
        .replaceAll(
            RegExp(r'\s+[A-Za-z][A-Za-z0-9._-]*\d[A-Za-z0-9._-]*\s*$'), '');
    return _normalize(cleaned);
  }

  static double _dice(String a, String b) {
    if (a == b) return 1;
    if (a.length < 2 || b.length < 2) return 0;
    final pairs = <String, int>{};
    for (var i = 0; i < a.length - 1; i++) {
      final pair = a.substring(i, i + 2);
      pairs[pair] = (pairs[pair] ?? 0) + 1;
    }
    var overlap = 0;
    for (var i = 0; i < b.length - 1; i++) {
      final pair = b.substring(i, i + 2);
      final count = pairs[pair] ?? 0;
      if (count > 0) {
        overlap++;
        pairs[pair] = count - 1;
      }
    }
    return 2 * overlap / (a.length + b.length - 2);
  }
}
