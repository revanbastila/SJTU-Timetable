import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/models/canvas_data.dart';
import 'package:jiaotong_course/models/course.dart';
import 'package:jiaotong_course/services/message_feed.dart';

void main() {
  test('today message feed keeps Canvas items and removes duplicates', () {
    const older = CanvasItem(
      id: 'canvas-1',
      title: '课程通知',
      messageHtml: '<p>内容</p>',
      type: '公告',
      courseName: '课程一',
      createdAt: '2026-09-20T08:00:00Z',
      htmlUrl: '',
    );
    const newer = CanvasItem(
      id: 'canvas-2',
      title: '控制面板消息',
      messageHtml: '<p>新内容</p>',
      type: '通知',
      courseName: 'Canvas 控制面板',
      createdAt: '2026-09-20T09:00:00Z',
      htmlUrl: '',
    );

    final feed = buildMessageFeed(
      CanvasSnapshot(
        dashboardItems: const [older, older, newer],
        courses: const [],
        syncedAt: DateTime(2026, 9, 20),
      ),
      const [],
    );

    expect(feed, hasLength(2));
    expect(feed.first.title, newer.title);
    expect(feed.first.sourceLabel, 'Canvas 控制面板');
    expect(feed.last.title, older.title);
    expect(feed.last.sourceLabel, '课程一');
  });

  test('a reused Canvas ID does not hide a later distinct message', () {
    const earlier = CanvasItem(
      id: 'reused',
      title: '旧消息',
      messageHtml: '',
      type: '通知',
      courseName: '课程一',
      createdAt: '2026-09-20T08:00:00Z',
      htmlUrl: '',
    );
    const later = CanvasItem(
      id: 'reused',
      title: '新消息',
      messageHtml: '',
      type: '通知',
      courseName: '课程一',
      createdAt: '2026-09-21T08:00:00Z',
      htmlUrl: '',
    );
    final feed = buildMessageFeed(
      CanvasSnapshot(
          dashboardItems: const [earlier, later],
          courses: const [],
          syncedAt: DateTime(2026, 9, 21)),
      const [],
    );
    expect(feed, hasLength(2));
    expect(feed.first.title, '新消息');
    expect(feed.first.key, isNot(feed.last.key));
  });

  test('course announcement identity is scoped by Canvas course ID', () {
    final feed = buildMessageFeed(
      CanvasSnapshot(
        dashboardItems: const [],
        courses: [
          _canvasCourse('canvas-criminal', '刑法总论', '课程通知'),
          _canvasCourse('canvas-civil', '民事程序法', '课程通知'),
        ],
        syncedAt: DateTime(2026, 9, 24),
      ),
      [
        _course('criminal', '刑法总论', 'canvas-criminal'),
        _course('civil', '民事程序法', 'canvas-civil'),
      ],
    );

    expect(feed, hasLength(2));
    expect(feed.map((entry) => entry.sourceLabel).toSet(), {'刑法总论', '民事程序法'});
    expect(feed.map((entry) => entry.key).toSet(), hasLength(2));
    expect(feed.first.key, contains('canvas:course:'));
  });

  test('announcement read key stays stable if its title/body are edited', () {
    final first = buildMessageFeed(
      CanvasSnapshot(
        dashboardItems: const [],
        courses: [
          _canvasCourse('canvas-1', '课程一', '旧标题', body: '旧内容'),
        ],
        syncedAt: DateTime(2026, 9, 24),
      ),
      [_course('portal-1', '课程一', 'canvas-1')],
    ).single;
    final edited = buildMessageFeed(
      CanvasSnapshot(
        dashboardItems: const [],
        courses: [
          _canvasCourse('canvas-1', '课程一', '新标题', body: '新内容'),
        ],
        syncedAt: DateTime(2026, 9, 25),
      ),
      [_course('portal-1', '课程一', 'canvas-1')],
    ).single;

    expect(edited.key, first.key);
    expect(first.legacyV2Key, contains('旧标题'));
    expect(edited.legacyV2Key, contains('新标题'));
  });
}

CanvasCourseData _canvasCourse(
  String id,
  String name,
  String title, {
  String? body,
}) =>
    CanvasCourseData(
      id: id,
      name: name,
      courseCode: '',
      syllabusHtml: '',
      announcements: [
        CanvasItem(
          id: '42',
          assetId: '42',
          courseId: id,
          title: title,
          messageHtml: '<p>${body ?? title}</p>',
          type: '公告',
          courseName: name,
          createdAt: '2026-09-24T08:00:00Z',
          htmlUrl: '',
        ),
      ],
      people: const [],
    );

Course _course(String id, String name, String canvasCourseId) => Course(
      id: id,
      name: name,
      teacher: '教师',
      location: '教室',
      time: '08:00-08:45',
      weekday: 1,
      startHour: 8,
      startMinute: 0,
      endHour: 8,
      endMinute: 45,
      activeWeeks: const [1],
      rawWeekText: '第1周',
      courseIdentity: id,
      canvasCourseId: canvasCourseId,
    );
