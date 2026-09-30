import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/models/canvas_data.dart';
import 'package:jiaotong_course/models/course.dart';
import 'package:jiaotong_course/services/announcement_feed.dart';

void main() {
  test('linked course announcements join dashboard items and deduplicate', () {
    final course = _course('portal-law', canvasCourseId: 'canvas-law');
    final shared = _item(
      'a1',
      '停课通知',
      createdAt: '2026-09-20T09:00:00Z',
      courseName: '刑事程序法',
    );
    final snapshot = CanvasSnapshot(
      dashboardItems: [shared, _item('d1', '平台通知')],
      courses: [
        CanvasCourseData(
          id: 'canvas-law',
          name: '刑事程序法',
          courseCode: 'LAW6548',
          syllabusHtml: '',
          announcements: [shared, _item('a2', '作业说明')],
          people: const [],
        ),
        CanvasCourseData(
          id: 'unlinked',
          name: '未关联课程',
          courseCode: '',
          syllabusHtml: '',
          announcements: [_item('hidden', '不应显示')],
          people: const [],
        ),
      ],
      syncedAt: DateTime(2026, 9, 20),
    );

    final feed = buildAnnouncementFeed(snapshot, [course]);

    expect(feed.map((entry) => entry.item.id).toSet(), {'a1', 'a2', 'd1'});
    expect(feed.where((entry) => entry.item.id == 'a1'), hasLength(1));
    expect(feed.first.courseName, '刑事程序法');
    expect(feed.first.timetableCourse?.id, 'portal-law');
    expect(feed.any((entry) => entry.item.id == 'hidden'), isFalse);
    expect(
      feed.singleWhere((entry) => entry.item.id == 'd1').courseName,
      'Canvas 控制面板',
    );
  });

  test('announcement course name falls back to linked Canvas course name', () {
    final snapshot = CanvasSnapshot(
      dashboardItems: const [],
      courses: [
        CanvasCourseData(
          id: 'canvas-law',
          name: '刑事程序法',
          courseCode: 'LAW6548',
          syllabusHtml: '',
          announcements: [_item('a1', '通知')],
          people: const [],
        ),
      ],
      syncedAt: DateTime(2026, 9, 20),
    );

    final feed = buildAnnouncementFeed(
      snapshot,
      [_course('portal-law', canvasCourseId: 'canvas-law')],
    );

    expect(feed.single.courseName, '刑事程序法');
  });

  test('dashboard announcement copies deduplicate by course asset identity',
      () {
    final courseAnnouncement = _item(
      'announcement-44',
      '课程群通知',
      createdAt: '2026-09-24T08:00:00Z',
      courseName: '民事程序法',
      assetId: '44',
      courseId: 'canvas-civil',
      htmlUrl:
          'https://oc.sjtu.edu.cn/courses/canvas-civil/discussion_topics/44',
    );
    final dashboardCopy = _item(
      'activity-900',
      '课程群通知',
      createdAt: '2026-09-24T08:00:00Z',
      courseName: '民事程序法',
      assetId: '44',
      courseId: 'canvas-civil',
      type: 'Announcement',
      htmlUrl:
          'https://oc.sjtu.edu.cn/courses/canvas-civil/discussion_topics/44',
    );
    final independent = _item('dashboard-1', '选课提醒');
    final snapshot = CanvasSnapshot(
      dashboardItems: [dashboardCopy, independent],
      courses: [
        CanvasCourseData(
          id: 'canvas-civil',
          name: '民事程序法',
          courseCode: '',
          syllabusHtml: '',
          announcements: [courseAnnouncement],
          people: const [],
        ),
      ],
      syncedAt: DateTime(2026, 9, 24),
    );

    final feed = buildAnnouncementFeed(
      snapshot,
      [_course('civil-time-slot', canvasCourseId: 'canvas-civil')],
    );

    expect(feed, hasLength(2));
    expect(feed.where((entry) => entry.item.title == '课程群通知'), hasLength(1));
    expect(
        feed
            .singleWhere((entry) => entry.item.title == '课程群通知')
            .timetableCourse
            ?.id,
        'civil-time-slot');
    expect(feed.any((entry) => entry.item.title == '选课提醒'), isTrue);
  });

  test('unique normalized course names include unmatched-ID announcements', () {
    final crimeCourse = _course(
      'criminal-law',
      canvasCourseId: null,
      name: '刑法总论',
    );
    final snapshot = CanvasSnapshot(
      dashboardItems: const [],
      courses: [
        CanvasCourseData(
          id: 'canvas-criminal',
          name: '刑法总论',
          courseCode: 'LAW',
          syllabusHtml: '',
          announcements: [_item('crime-1', '刑法总论课程公告')],
          people: const [],
        ),
      ],
      syncedAt: DateTime(2026, 9, 24),
    );

    final feed = buildAnnouncementFeed(snapshot, [crimeCourse]);

    expect(feed, hasLength(1));
    expect(feed.single.item.title, '刑法总论课程公告');
    expect(feed.single.timetableCourse?.id, 'criminal-law');
  });
}

CanvasItem _item(
  String id,
  String title, {
  String createdAt = '2026-09-19T09:00:00Z',
  String courseName = '',
  String assetId = '',
  String courseId = '',
  String htmlUrl = '',
  String type = '公告',
}) =>
    CanvasItem(
      id: id,
      title: title,
      messageHtml: '<p>$title</p>',
      type: type,
      courseName: courseName,
      createdAt: createdAt,
      htmlUrl: htmlUrl,
      assetId: assetId,
      courseId: courseId,
    );

Course _course(String id, {String? canvasCourseId, String name = '刑事程序法'}) =>
    Course(
      id: id,
      name: name,
      teacher: '教师',
      location: '新上院 N100',
      time: '08:00-08:45',
      weekday: 1,
      startHour: 8,
      startMinute: 0,
      endHour: 8,
      endMinute: 45,
      activeWeeks: const [1],
      rawWeekText: '第1周',
      courseIdentity: 'code:LAW6548',
      canvasCourseId: canvasCourseId,
    );
