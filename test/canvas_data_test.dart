import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/models/canvas_data.dart';

void main() {
  test('Canvas announcement context identifiers survive cached serialization',
      () {
    final item = CanvasItem.fromMap(const {
      'id': 'activity-1',
      'asset_id': 72,
      'asset_type': 'Announcement',
      'context_type': 'Course',
      'context_id': 9,
      'title': '通知',
    });

    expect(item.assetId, '72');
    expect(item.courseId, '9');
    expect(item.assetType, 'Announcement');
    expect(item.contextType, 'Course');
    expect(CanvasItem.fromMap(item.toMap()).courseId, '9');
  });

  test('course announcement cache excludes rows belonging to another course',
      () {
    final course = CanvasCourseData.fromMap({
      'id': 9,
      'name': '刑法总论',
      'announcements': [
        {'id': 10, 'title': '本课程公告', 'course_id': 9},
        {'id': 11, 'title': '其他课程公告', 'course_id': 88},
      ],
    });

    expect(course.announcements, hasLength(1));
    expect(course.announcements.single.courseId, '9');
    expect(course.announcements.single.title, '本课程公告');
  });

  test('Canvas avatars survive parsing and cache round-trip', () {
    final person = CanvasPerson.fromMap({
      'id': 17,
      'name': '教师甲',
      'avatar_url': 'https://oc.sjtu.edu.cn/images/profiles/17.png',
      'enrollments': [
        {'type': 'TeacherEnrollment'}
      ],
    });
    expect(person.avatarUrl, 'https://oc.sjtu.edu.cn/images/profiles/17.png');
    expect(CanvasPerson.fromMap(person.toMap()).avatarUrl, person.avatarUrl);
    expect(CanvasPerson.fromMap({'name': '学生乙'}).avatarUrl, isEmpty);
    expect(
        CanvasPerson.fromMap({
          'name': '学生丙',
          'avatar': {'url': '/images/profiles/19.png'},
        }).avatarUrl,
        '/images/profiles/19.png');
  });

  test('members group teacher, TA, student without reordering peers', () {
    CanvasPerson person(String id, String role) =>
        CanvasPerson(id: id, name: id, role: role);
    final members = [
      person('s1', 'StudentEnrollment'),
      person('ta1', 'TaEnrollment'),
      person('t1', 'TeacherEnrollment'),
      person('s2', 'StudentEnrollment'),
      person('t2', '教师'),
      person('ta2', '助教'),
    ];
    expect(canvasPeopleInRoleOrder(members).map((item) => item.id),
        ['t1', 't2', 'ta1', 'ta2', 's1', 's2']);
  });

  test('Canvas course accepts optional external identifiers', () {
    final course = CanvasCourseData.fromMap({
      'id': 9,
      'name': '知识产权法',
      'course_code': 'LAW6001',
      'sis_course_id': 'portal-42',
      'integration_id': null,
    });
    expect(course.id, '9');
    expect(course.sisCourseId, 'portal-42');
    expect(course.integrationId, '');
    expect(course.toMap()['sisCourseId'], 'portal-42');
  });

  test('Canvas models tolerate nulls, missing fields and malformed rows', () {
    final snapshot = CanvasSnapshot.fromMap({
      'dashboardItems': [
        {'id': 1, 'title': null, 'message': '内容'},
        null,
        'bad row',
      ],
      'courses': [
        {
          'id': 9,
          'name': null,
          'syllabus_body': null,
          'announcements': null,
          'people': [
            {'id': 3, 'name': '同学', 'enrollments': null},
            {
              'id': 4,
              'name': '老师',
              'enrollments': [
                null,
                {'role': '教师'}
              ]
            },
          ],
        },
        null,
      ],
    });
    expect(snapshot.dashboardItems, hasLength(1));
    expect(snapshot.dashboardItems.single.title, '内容');
    expect(snapshot.courses, hasLength(1));
    expect(snapshot.courses.single.syllabusHtml, isEmpty);
    expect(snapshot.courses.single.people, hasLength(2));
    expect(snapshot.courses.single.people.last.role, '教师');
  });

  test('chunked Canvas messages assemble without one bad row aborting sync',
      () {
    final accumulator = CanvasSyncAccumulator();
    expect(accumulator.add({'kind': 'start'}), isNull);
    accumulator.add({
      'kind': 'dashboard',
      'items': [
        {'id': 'n1', 'title': '通知一'}
      ],
    });
    accumulator.add({
      'kind': 'dashboard',
      'append': true,
      'items': [
        {'id': 'n2', 'title': '通知二'}
      ],
    });
    accumulator.add({
      'kind': 'course',
      'data': {'id': 'c1', 'name': '算法', 'courseCode': 'CS101'}
    });
    accumulator
        .add({'kind': 'syllabus', 'courseId': 'c1', 'text': '<p>第一段</p>'});
    accumulator.add({
      'kind': 'people',
      'courseId': 'c1',
      'items': [
        {'id': 'u1', 'name': '学生', 'enrollments': []},
        null,
      ]
    });
    final snapshot = accumulator
        .add({'kind': 'complete', 'syncedAt': '2026-09-19T10:00:00Z'});
    expect(snapshot, isNotNull);
    expect(snapshot!.dashboardItems, hasLength(2));
    expect(snapshot.courses.single.syllabusHtml, contains('第一段'));
    expect(snapshot.courses.single.people, hasLength(1));
  });

  test('Canvas fatal messages expose the real stage and endpoint', () {
    final accumulator = CanvasSyncAccumulator();
    expect(
      () => accumulator.add({
        'kind': 'fatal',
        'stage': 'Canvas 课程列表',
        'endpoint': '/api/v1/courses',
        'error': 'HTTP 401 Unauthorized',
      }),
      throwsA(isA<CanvasSyncException>()
          .having((error) => error.message, 'message', contains('401'))
          .having((error) => error.message, 'endpoint',
              contains('/api/v1/courses'))),
    );
  });

  test('catalog is available before detail messages complete', () {
    final accumulator = CanvasSyncAccumulator();
    accumulator.add({'kind': 'start'});
    accumulator.add({
      'kind': 'course',
      'data': {'id': 'c1', 'name': '算法', 'courseCode': 'CS101'}
    });
    final catalog = accumulator.add({'kind': 'catalogComplete'});
    expect(catalog, isNotNull);
    expect(catalog!.courses.single.name, '算法');
    expect(catalog.courses.single.people, isEmpty);
  });

  test('failed detail endpoint keeps the previous cached section', () {
    final previous = CanvasSnapshot.fromMap({
      'dashboardItems': [],
      'courses': [
        {
          'id': 'c1',
          'name': '算法',
          'announcements': [
            {'id': 'a1', 'title': '旧公告'}
          ],
          'people': [
            {'id': 'u1', 'name': '同学'}
          ],
        }
      ],
    });
    final refreshed = CanvasSnapshot.fromMap({
      'dashboardItems': [],
      'courses': [
        {
          'id': 'c1',
          'name': '算法',
          'announcements': [],
          'people': [],
          'errors': {'announcements': '请求超时'}
        }
      ],
    });
    final merged = previous.mergeRefresh(refreshed);
    expect(merged.courses.single.announcements.single.title, '旧公告');
    expect(merged.courses.single.people, isEmpty);
  });
}
