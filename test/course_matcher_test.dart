import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/models/canvas_data.dart';
import 'package:jiaotong_course/models/course.dart';
import 'package:jiaotong_course/services/course_matcher.dart';

CanvasCourseData canvasCourse(
  String id,
  String name, {
  String code = '',
  String sisCourseId = '',
  String integrationId = '',
}) =>
    CanvasCourseData(
      id: id,
      name: name,
      courseCode: code,
      syllabusHtml: '',
      announcements: const [],
      people: const [],
      sisCourseId: sisCourseId,
      integrationId: integrationId,
    );

void main() {
  test('section course code matches a unique Canvas base code', () {
    final result = CourseMatcher.apply(
      [
        Course.fromMap({
          'name': '刑事程序法',
          'courseCode': 'LAW6548-19000-X01',
          'time': '周一第1-2节',
        })
      ],
      [canvasCourse('8', '刑事程序法', code: 'LAW6548')],
    );
    expect(result.single.canvasCourseId, '8');
  });
  test('course code wins over name', () {
    final course = Course.fromMap(
        {'name': '算法', 'courseCode': 'CS101', 'time': '周一第1-2节'});
    final result = CourseMatcher.apply(
        [course], [canvasCourse('9', '完全不同', code: 'CS101')]);
    expect(result.single.canvasCourseId, '9');
  });

  test('normalized name wins over a stale manual mapping', () {
    final course = Course.fromMap({'name': '机器学习（1班）', 'time': '周一第1-2节'});
    final candidates = [canvasCourse('1', '机器学习'), canvasCourse('2', '机器学习导论')];
    expect(
        CourseMatcher.apply([course], candidates).single.canvasCourseId, '1');
    expect(
      CourseMatcher.apply([course], candidates,
          manualMappings: {course.courseIdentity: '2'}).single.canvasCourseId,
      '1',
    );
  });

  test('SIS and integration IDs match portal IDs but Canvas numeric IDs do not',
      () {
    final sisCourse = Course.fromMap({
      'sourceCourseId': 'PORTAL-42',
      'name': '未能按名称匹配',
      'time': '周一第1-2节',
    });
    final result = CourseMatcher.apply([
      sisCourse,
    ], [
      canvasCourse('PORTAL-42', '不同课程'),
      canvasCourse('9', '另一门课程', sisCourseId: 'portal-42'),
    ]);
    expect(result.single.canvasCourseId, '9');
  });

  test('term, class suffix and trailing course code are ignored in names', () {
    final course = Course.fromMap({
      'name': '机器学习 LAW6001',
      'time': '周一第1-2节',
    });
    final result = CourseMatcher.apply(
      [course],
      [canvasCourse('3', '2026-2027-1 机器学习（1班）')],
    );
    expect(result.single.canvasCourseId, '3');
  });

  test('manual mapping remains a fallback for otherwise unmatched courses', () {
    final course = Course.fromMap({'name': '专题研讨', 'time': '周一第1-2节'});
    final result = CourseMatcher.apply(
      [course],
      [canvasCourse('8', '完全不同的课程')],
      manualMappings: {course.courseIdentity: '8'},
    );
    expect(result.single.canvasCourseId, '8');
  });

  test('an unmatched course is retried on the next Canvas sync', () {
    final course = Course.fromMap({
      'name': '知识产权法 LAW6010',
      'time': '周一第1-2节',
    });
    expect(
        CourseMatcher.apply([course], const []).single.canvasCourseId, isNull);
    final retried = CourseMatcher.apply(
      [course],
      [canvasCourse('10', '知识产权法', code: 'LAW6010')],
    );
    expect(retried.single.canvasCourseId, '10');
  });

  test('ambiguous fuzzy candidates are rejected', () {
    final course = Course.fromMap({'name': '高级人工智能', 'time': '周一第1-2节'});
    final candidates = [
      canvasCourse('1', '高级人工智能A'),
      canvasCourse('2', '高级人工智能B'),
    ];
    expect(CourseMatcher.apply([course], candidates).single.canvasCourseId,
        isNull);
  });

  test('Canvas association never changes portal timetable fields', () {
    final course = Course.fromMap({
      'sourceCourseId': 'portal-42',
      'name': '编译原理',
      'teacher': '王老师',
      'location': '东中院2-201',
      'time': '周三第3-4节',
    });
    final matched =
        CourseMatcher.apply([course], [canvasCourse('8', '编译原理')]).single;
    expect(matched.canvasCourseId, '8');
    expect(matched.sourceCourseId, course.sourceCourseId);
    expect(matched.name, course.name);
    expect(matched.teacher, course.teacher);
    expect(matched.location, course.location);
    expect(matched.time, course.time);
  });
}
