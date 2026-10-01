import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jiaotong_course/models/canvas_data.dart';
import 'package:jiaotong_course/models/course.dart';
import 'package:jiaotong_course/services/canvas_announcement_sync.dart';
import 'package:jiaotong_course/services/message_feed.dart';
import 'package:jiaotong_course/services/notification_service.dart';
import 'package:jiaotong_course/state/app_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  final pending = <int, Map<String, dynamic>>{};
  var notificationAllowed = true;
  var exactAllowed = true;
  setUp(() {
    calls.clear();
    pending.clear();
    notificationAllowed = true;
    exactAllowed = true;
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'areNotificationsEnabled':
        case 'requestNotificationsPermission':
          return notificationAllowed;
        case 'canScheduleExactNotifications':
          return exactAllowed;
        case 'requestExactAlarmsPermission':
          exactAllowed = true;
          return true;
        case 'zonedSchedule':
          final value = Map<String, dynamic>.from(call.arguments as Map);
          pending[value['id'] as int] = {
            'id': value['id'],
            'title': value['title'],
            'body': value['body'],
            'payload': null
          };
          return null;
        case 'pendingNotificationRequests':
          return pending.values.toList();
        case 'cancel':
          pending.remove((call.arguments as Map)['id']);
          return null;
        case 'cancelAll':
          pending.clear();
          return null;
      }
      return null;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, null));

  const course = Course(
      id: 'c',
      name: 'Course',
      teacher: 'Teacher',
      location: 'Room',
      time: '',
      weekday: 1,
      startHour: 0,
      startMinute: 5,
      endHour: 1,
      endMinute: 0,
      activeWeeks: [1],
      rawWeekText: '1',
      courseIdentity: 'c');
  test('push and alarm use exact schedules and lead time crosses midnight',
      () async {
    final service = NotificationService();
    for (final mode in [ReminderMode.push, ReminderMode.alarm]) {
      final report = await service.sync([course], mode,
          termStart: DateTime(2030, 1, 7), reminderMinutes: 15);
      expect(report.succeeded, true);
      final schedule =
          calls.lastWhere((c) => c.method == 'zonedSchedule').arguments as Map;
      expect(schedule['scheduledDateTime'], startsWith('2030-01-06T23:50'));
      expect((schedule['platformSpecifics'] as Map)['scheduleMode'],
          'exactAllowWhileIdle');
    }
    expect(calls.where((c) => c.method.startsWith('request')), isEmpty);
    expect(calls.where((c) => c.method == 'initialize'), hasLength(1));
    expect(calls.where((c) => c.method == 'cancelAll'), isEmpty);
    expect(service.reminderDetails(ReminderMode.alarm).audioAttributesUsage,
        AudioAttributesUsage.alarm);
    expect(service.reminderDetails(ReminderMode.alarm).sound,
        isA<UriAndroidNotificationSound>());
    expect(service.reminderDetails(ReminderMode.alarm).additionalFlags,
        contains(4));
  });
  test('both modes request exact permission when explicitly enabled', () async {
    for (final mode in [ReminderMode.push, ReminderMode.alarm]) {
      exactAllowed = false;
      expect(await NotificationService().requestPermissions(mode), true);
    }
    expect(calls.where((c) => c.method == 'requestExactAlarmsPermission'),
        hasLength(2));
  });
  test('denied notifications are reported rather than silently scheduled',
      () async {
    notificationAllowed = false;
    final service = NotificationService();
    expect(
        await service
            .sync([course], ReminderMode.push, termStart: DateTime(2030, 1, 7)),
        isA<NotificationSyncReport>()
            .having((r) => r.succeeded, 'succeeded', false));
    expect(calls.where((c) => c.method == 'zonedSchedule'), isEmpty);
    await expectLater(
        service.requestPermissions(ReminderMode.alarm), throwsStateError);
  });
  test(
      'concurrent refreshes serialize; obsolete alarms removed before replacement',
      () async {
    pending[999] = {'id': 999, 'title': 'old', 'body': '', 'payload': null};
    final service = NotificationService();
    await Future.wait([
      service
          .sync([course], ReminderMode.push, termStart: DateTime(2030, 1, 7)),
      service
          .sync([course], ReminderMode.alarm, termStart: DateTime(2030, 1, 7)),
    ]);
    expect(pending.length, 1);
    expect(calls.indexWhere((c) => c.method == 'cancel'),
        lessThan(calls.indexWhere((c) => c.method == 'zonedSchedule')));
    await service.sync([], ReminderMode.off);
    expect(pending, isEmpty);
  });

  CanvasItem notice(String id, String date, {String title = 'Notice'}) =>
      CanvasItem(
          id: id,
          assetId: id,
          title: title,
          messageHtml: '',
          type: '公告',
          courseName: 'Canvas',
          courseId: '42',
          createdAt: date,
          htmlUrl: 'https://oc.sjtu.edu.cn/courses/42/discussion_topics/$id');
  final old = notice('1', '2026-09-01T00:00:00Z');
  CanvasSnapshot snapshot() => CanvasSnapshot(
      dashboardItems: [],
      syncedAt: DateTime(2026),
      courses: [
        CanvasCourseData(
            id: '42',
            name: 'Canvas',
            courseCode: 'C',
            syllabusHtml: 'Keep syllabus',
            announcements: [
              old
            ],
            people: const [
              CanvasPerson(
                  id: 'p',
                  name: 'Teacher',
                  role: 'TeacherEnrollment',
                  avatarUrl: 'keep-avatar')
            ]),
      ]);
  test(
      'announcement polling deduplicates, orders by publication and preserves detail data',
      () {
    final previous = snapshot();
    final newest = notice('2', '2026-10-01T00:00:00Z');
    final payload = {
      'courses': [
        {
          'id': '42',
          'announcements': [old.toMap(), newest.toMap(), newest.toMap()]
        }
      ]
    };
    final merged = CanvasAnnouncementSync.merge(previous, payload);
    expect(merged.courses.single.announcements.map((a) => a.id), ['2', '1']);
    expect(merged.courses.single.people, same(previous.courses.single.people));
    expect(merged.courses.single.syllabusHtml, 'Keep syllabus');
    expect(CanvasAnnouncementSync.merge(merged, payload), same(merged));
    expect(CanvasAnnouncementSync.merge(merged, {'courses': []}), same(merged));
  });
  test(
      'new notice increments unread bubble; previous read state survives edits and repeat polls',
      () async {
    final app = AppController(NotificationService())
      ..username = 'account'
      ..loggedIn = true
      ..canvas = snapshot()
      ..courses = [course.copyWith(canvasCourseId: '42')];
    await app
        .markMessageRead(buildMessageFeed(app.canvas, app.courses).single.key);
    expect(app.unreadMessageCount, 0);
    final payload = {
      'courses': [
        {
          'id': '42',
          'announcements': [
            notice('1', old.createdAt, title: 'Edited').toMap(),
            notice('2', '2026-10-01T00:00:00Z').toMap()
          ]
        }
      ]
    };
    app.canvas = CanvasAnnouncementSync.merge(app.canvas, payload);
    expect(app.unreadMessageCount, 1);
    app.canvas = CanvasAnnouncementSync.merge(app.canvas, payload);
    expect(app.unreadMessageCount, 1);
    expect(buildMessageFeed(app.canvas, app.courses).first.canvasItem!.id, '2');
    app.dispose();
  });
}
