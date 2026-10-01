import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jiaotong_course/models/canvas_data.dart';
import 'package:jiaotong_course/models/course.dart';
import 'package:jiaotong_course/models/app_theme.dart';
import 'package:jiaotong_course/models/week_rules.dart';
import 'package:jiaotong_course/services/notification_service.dart';
import 'package:jiaotong_course/services/course_normalizer.dart';
import 'package:jiaotong_course/services/credential_store.dart';
import 'package:jiaotong_course/state/app_controller.dart';

class MemoryCredentialStore implements CredentialStore {
  StoredCredentials? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<StoredCredentials?> read() async => value;

  @override
  Future<void> write(String username, String password) async {
    value = StoredCredentials(username: username, password: password);
  }
}

class SilentNotifications extends NotificationService {
  @override
  Future<bool> requestPermissions(ReminderMode mode) async => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<NotificationSyncReport> sync(List<Course> courses, ReminderMode mode,
          {DateTime? termStart,
          int totalWeeks = 18,
          int reminderMinutes = 15}) async =>
      const NotificationSyncReport([]);
}

class FailingNotifications extends SilentNotifications {
  @override
  Future<NotificationSyncReport> sync(List<Course> courses, ReminderMode mode,
      {DateTime? termStart,
      int totalWeeks = 18,
      int reminderMinutes = 15}) async {
    throw StateError('Missing type parameter');
  }
}

class CountingNotifications extends SilentNotifications {
  int syncCalls = 0;
  int lastReminderMinutes = 15;

  @override
  Future<NotificationSyncReport> sync(List<Course> courses, ReminderMode mode,
      {DateTime? termStart,
      int totalWeeks = 18,
      int reminderMinutes = 15}) async {
    syncCalls++;
    lastReminderMinutes = reminderMinutes;
    return const NotificationSyncReport([]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('unverified legacy profile cache is hidden until plan endpoint succeeds',
      () async {
    SharedPreferences.setMockInitialValues({
      'username': 'account-a',
      'studentNumber_account-a': '987654321012',
      'studentName_account-a': '旧姓名',
      'studentCollege_account-a': '旧学院',
    });
    final app = AppController(SilentNotifications(),
        credentialStore: MemoryCredentialStore());
    await app.bootstrap();
    expect(app.studentNumber, '');
    expect(app.studentName, '');
    expect(app.studentCollege, '');
    await app.saveSyncedData('account-a', [], CanvasSnapshot.empty());
    expect(app.studentNumber, '');
    await app.saveStudentProfileForSession(
        'account-a', '123456789012', '张三', app.sessionGeneration,
        college: '法学院');
    expect(app.studentName, '张三');
    expect(app.studentNumber, '123456789012');
    expect(app.studentCollege, '法学院');
    app.dispose();
  });

  test('student number is scoped to the portal account and cleared on logout',
      () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppController(SilentNotifications(),
        credentialStore: MemoryCredentialStore());
    await app.bootstrap();
    await app.saveSyncedData('account-a', [], CanvasSnapshot.empty(),
        studentNumber: '123456789012', studentName: '杨惠泽');
    expect(app.studentNumber, '123456789012');
    expect(app.studentName, '杨惠泽');
    await app.saveStudentProfileForSession(
        'account-a', '123456789012', '杨惠泽', app.sessionGeneration,
        college: '法学院');
    expect(app.studentCollege, '法学院');
    await app.saveSyncedData('account-b', [], CanvasSnapshot.empty());
    expect(app.studentNumber, '');
    expect(app.studentName, '');
    expect(app.studentCollege, '');
    await app.saveSyncedData('account-a', [], CanvasSnapshot.empty());
    expect(app.studentNumber, '123456789012');
    expect(app.studentName, '杨惠泽');
    expect(app.studentCollege, '法学院');
    await app.logout();
    expect(app.studentNumber, '');
    expect(app.studentName, '');
    expect(app.studentCollege, '');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('studentNumber_account-a'), isNull);
    expect(prefs.getString('studentName_account-a'), isNull);
    expect(prefs.getString('studentCollege_account-a'), isNull);
    app.dispose();
  });

  test('background profile result updates only the active login', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppController(SilentNotifications(),
        credentialStore: MemoryCredentialStore());
    await app.bootstrap();
    await app.saveSyncedData('account-a', [], CanvasSnapshot.empty());
    final generation = app.sessionGeneration;
    await app.saveStudentNumberForSession(
        'account-a', '123456789012', generation);
    expect(app.studentNumber, '123456789012');
    await app.logout();
    await app.saveStudentNumberForSession(
        'account-a', '987654321012', generation);
    expect(app.studentNumber, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('studentNumber_account-a'), isNull);
    app.dispose();
  });

  test('SJTU red selection persists without changing existing themes',
      () async {
    expect(AppThemeChoice.values.take(2),
        [AppThemeChoice.sjtuBlue, AppThemeChoice.sjtuRed]);
    SharedPreferences.setMockInitialValues({});
    final app = AppController(SilentNotifications(),
        credentialStore: MemoryCredentialStore());
    await app.bootstrap();
    await app.setThemeChoice(AppThemeChoice.sjtuRed);
    expect(app.themeChoice.label, '交大红');
    expect(app.themeChoice.soft, isNot(app.themeChoice.primary));
    final restored = AppController(SilentNotifications(),
        credentialStore: MemoryCredentialStore());
    await restored.bootstrap();
    expect(restored.themeChoice, AppThemeChoice.sjtuRed);
    expect(AppThemeChoice.sjtuBlue.primary, const Color(0xFF315F86));
    expect(AppThemeChoice.values.take(2),
        [AppThemeChoice.sjtuBlue, AppThemeChoice.sjtuRed]);
    expect(AppThemeChoice.sjtuBlue.label, '经典蓝');
    app.dispose();
    restored.dispose();
  });

  test('interface mode defaults to system and preserves explicit choice',
      () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppController(SilentNotifications(),
        credentialStore: MemoryCredentialStore());
    await app.bootstrap();
    expect(app.interfaceMode, InterfaceMode.system);
    expect(InterfaceMode.values, [
      InterfaceMode.system,
      InterfaceMode.light,
      InterfaceMode.dark,
    ]);
    expect(InterfaceModeStyle.fromStorage(null), InterfaceMode.system);
    expect(InterfaceModeStyle.fromStorage('light'), InterfaceMode.light);
    await app.setInterfaceMode(InterfaceMode.dark);

    final restored = AppController(SilentNotifications(),
        credentialStore: MemoryCredentialStore());
    await restored.bootstrap();
    expect(restored.interfaceMode, InterfaceMode.dark);
    expect(InterfaceMode.system.themeMode, ThemeMode.system);
    expect(AppThemeChoice.sjtuBlue.primaryFor(Brightness.dark),
        isNot(AppThemeChoice.sjtuBlue.primary));
    app.dispose();
    restored.dispose();
  });
  test('unknown schedules never become Monday at 8', () {
    final c = Course.fromMap({'name': '算法', 'time': '1-16周'});
    expect(c.weekday, 0);
    expect(c.hasSchedule, false);
  });
  test('weekdays and exact period mapping', () {
    for (var day = 1; day <= 7; day++) {
      final c = Course.fromMap(
          {'name': '算法', 'time': '星期${'一二三四五六日'[day - 1]} 第7-8节'});
      expect(c.weekday, day);
      expect(c.startMinutes, 14 * 60);
      expect(c.endMinutes, 15 * 60 + 40);
      expect(c.firstPeriod, 7);
      expect(c.lastPeriod, 8);
    }
  });
  test('grid rowspan and explicit clock ranges', () {
    final grid = Course.fromMap(
        {'name': '算法', 'weekday': 4, 'startPeriod': 3, 'endPeriod': 4});
    expect(grid.startMinutes, 600);
    expect(grid.endMinutes, 700);
    final clock = Course.fromMap({'name': '算法', 'time': '周天 18:00-20:20'});
    expect(clock.weekday, 7);
    expect(clock.endMinutes, 1220);
    expect(Course.fromMap(grid.toMap()).toMap(), grid.toMap());
  });
  test('current portal period fields become a valid scheduled course', () {
    final course = Course.fromMap({
      'name': '刑事程序法(LAW6548-19000-X01)',
      'teacher': '朱军，庄加园',
      'location': '新上院 N100',
      'weekday': '2',
      'startPeriod': '3',
      'endPeriod': '4',
      'weekText': '1-16周',
      'courseCode': 'LAW6548',
      'sourceCourseId': '19000-X01',
    });
    expect(course.hasSchedule, isTrue);
    expect(course.weekday, 2);
    expect(course.firstPeriod, 3);
    expect(course.lastPeriod, 4);
    expect(course.teacher, '朱军，庄加园');
    expect(course.location, '新上院 N100');
  });
  test('Canvas unread count is deduplicated and survives a restart', () async {
    SharedPreferences.setMockInitialValues({});
    const item = CanvasItem(
      id: 'notice-42',
      title: '课程公告',
      messageHtml: '<p>新通知</p>',
      type: '公告',
      courseName: '课程一',
      createdAt: '2026-09-23T08:00:00Z',
      htmlUrl: '',
    );
    final app = AppController(SilentNotifications(),
        credentialStore: MemoryCredentialStore());
    await app.bootstrap();
    app.canvas = CanvasSnapshot(
      dashboardItems: const [item, item],
      courses: const [],
      syncedAt: DateTime(2026, 9, 23),
    );
    await app.login('unread-test', [], remember: true);
    expect(app.unreadMessageCount, 1);
    await app.markCanvasItemRead(item);
    expect(app.unreadMessageCount, 0);
    final restored = AppController(SilentNotifications(),
        credentialStore: MemoryCredentialStore());
    await restored.bootstrap();
    expect(restored.unreadMessageCount, 0);
    app.dispose();
    restored.dispose();
  });
  test('remembered login survives restart and logout clears it', () async {
    SharedPreferences.setMockInitialValues({});
    final credentials = MemoryCredentialStore();
    final app = AppController(
      SilentNotifications(),
      credentialStore: credentials,
    );
    await app.bootstrap();
    app.retainSessionCredentials('test-account', 'memory-only-password');
    await app.login('test-account', [], remember: true);
    expect(app.sessionPassword, 'memory-only-password');
    final stored = await SharedPreferences.getInstance();
    expect(
        stored.getKeys().any((key) => key.toLowerCase().contains('password')),
        false);
    final restored = AppController(
      SilentNotifications(),
      credentialStore: credentials,
    );
    await restored.bootstrap();
    expect(restored.loggedIn, true);
    expect(restored.username, 'test-account');
    expect(restored.sessionPassword, 'memory-only-password');
    restored.retainSessionCredentials('test-account', 'temporary');
    final cleanup = restored.logout();
    expect(restored.loggedIn, false);
    expect(restored.courses, isEmpty);
    await cleanup;
    expect(restored.sessionPassword, isEmpty);
    expect(credentials.value, isNull);
    final afterLogout = AppController(
      SilentNotifications(),
      credentialStore: credentials,
    );
    await afterLogout.bootstrap();
    expect(afterLogout.loggedIn, false);
    app.dispose();
    restored.dispose();
    afterLogout.dispose();
  });
  test('unchecked remember does not restore session', () async {
    SharedPreferences.setMockInitialValues({});
    final credentials = MemoryCredentialStore();
    final app = AppController(
      SilentNotifications(),
      credentialStore: credentials,
    );
    await app.login('test-account', [], remember: false);
    expect(credentials.value, isNull);
    final restored = AppController(
      SilentNotifications(),
      credentialStore: credentials,
    );
    await restored.bootstrap();
    expect(restored.loggedIn, false);
    app.dispose();
    restored.dispose();
  });
  test('week parser supports discontinuous ranges and parity', () {
    expect(parseWeekRule('2-5周、7-13周').weeks,
        [2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13]);
    expect(parseWeekRule('1-16周（单周）').weeks, [1, 3, 5, 7, 9, 11, 13, 15]);
    expect(parseWeekRule('2-18双周').weeks, [2, 4, 6, 8, 10, 12, 14, 16, 18]);
    expect(parseWeekRule('没有周次').inferred, true);
  });
  test('academic week boundaries use Sep 14 as week one', () {
    final start = DateTime(2026, 9, 14);
    expect(academicWeekFor(DateTime(2026, 9, 14), start, 18), 1);
    expect(academicWeekFor(DateTime(2026, 9, 20), start, 18), 1);
    expect(academicWeekFor(DateTime(2026, 9, 21), start, 18), 2);
    expect(academicWeekInTerm(DateTime(2026, 9, 13), start, 18), isNull);
    expect(academicWeekInTerm(DateTime(2027, 1, 18), start, 18), isNull);
    expect(academicWeekFor(DateTime(2026, 9, 13), start, 18), 1);
    expect(academicWeekFor(DateTime(2027, 1, 18), start, 18), 18);
  });

  test('entering timetable selects today while manual selection remains', () {
    final app = AppController(SilentNotifications())
      ..termStart = DateTime(2026, 9, 14)
      ..totalWeeks = 18
      ..selectedWeek = 9;
    app.selectWeekForToday(now: DateTime(2026, 9, 28));
    expect(app.selectedWeek, 3);
    app.selectWeek(7);
    expect(app.selectedWeek, 7);
    app.selectWeekForToday(now: DateTime(2026, 9, 28));
    expect(app.selectedWeek, 3);
    app.selectWeekForToday(now: DateTime(2026, 9, 1));
    expect(app.selectedWeek, 1);
    app.dispose();
  });

  test('portal identity and course colors are stable and distinct', () {
    final app = AppController(
      SilentNotifications(),
      credentialStore: MemoryCredentialStore(),
    );
    final first = Course.fromMap({
      'sourceCourseId': '101',
      'name': '算法',
      'weekday': 1,
      'startPeriod': 1,
    });
    final same = Course.fromMap({
      'sourceCourseId': '101',
      'name': '算法',
      'weekday': 3,
      'startPeriod': 3,
    });
    final other = Course.fromMap({
      'sourceCourseId': '102',
      'name': '数据库',
      'weekday': 2,
      'startPeriod': 1,
    });
    app.courses = [first, same, other];
    expect(first.courseIdentity, same.courseIdentity);
    expect(first.courseIdentity, isNot(other.courseIdentity));
    expect(app.courseColorValue(first), app.courseColorValue(same));
    expect(app.courseColorValue(first), isNot(app.courseColorValue(other)));
    app.dispose();
  });

  test('duplicate portal fragments merge fields and weeks', () {
    final partialName = Course.fromMap({
      'sourceCourseId': 'c1',
      'name': '算法',
      'weekday': 1,
      'startPeriod': 1,
      'endPeriod': 2,
      'activeWeeks': [1, 3],
    });
    final partialDetails = Course.fromMap({
      'sourceCourseId': 'c1',
      'name': '算法',
      'teacher': '李老师',
      'location': '东上院101',
      'weekday': 1,
      'startPeriod': 1,
      'endPeriod': 2,
      'activeWeeks': [2, 4],
    });
    final result = normalizePortalCourses([partialName, partialDetails]);
    expect(result, hasLength(1));
    expect(result.single.teacher, '李老师');
    expect(result.single.location, '东上院101');
    expect(result.single.activeWeeks, [1, 2, 3, 4]);
  });

  test('legacy portal aliases and nested fields restore teacher and room', () {
    final course = Course.fromMap({
      '课程名称': '刑事程序法(LAW6548-19000-X01)',
      'SKJSXM': [
        {'xm': '张老师'}
      ],
      '上课教室': {'label': '东上院101'},
      '上课时间': '周二 第3-4节 1-16周',
    });
    expect(course.name, '刑事程序法');
    expect(course.courseCode, 'LAW6548-19000-X01');
    expect(course.teacher, '张老师');
    expect(course.location, '东上院101');
  });

  test('adjacent matching meetings merge but distinct meetings remain', () {
    Course meeting(int period,
            {String teacher = '赵老师',
            String location = '东上院101',
            List<int> weeks = const [1, 2]}) =>
        Course.fromMap({
          'sourceCourseId': 'lesson-1',
          'name': '刑事程序法',
          'courseCode': 'LAW6548-19000-X01',
          'teacher': teacher,
          'location': location,
          'weekday': 2,
          'startPeriod': period,
          'endPeriod': period,
          'activeWeeks': weeks,
          'weeksInferred': false,
        });

    final joined = normalizePortalCourses([meeting(3), meeting(4)]);
    expect(joined, hasLength(1));
    expect(joined.single.firstPeriod, 3);
    expect(joined.single.lastPeriod, 4);
    expect(joined.single.teacher, '赵老师');
    expect(joined.single.location, '东上院101');

    expect(normalizePortalCourses([meeting(3), meeting(4, teacher: '钱老师')]),
        hasLength(2));
    expect(normalizePortalCourses([meeting(3), meeting(4, location: '东中院201')]),
        hasLength(2));
    expect(
        normalizePortalCourses([
          meeting(3),
          meeting(4, weeks: const [2])
        ]),
        hasLength(2));
    expect(normalizePortalCourses([meeting(3), meeting(5)]), hasLength(2));
  });

  test('three adjacent sections merge by stable code across fragment IDs', () {
    Course fragment(int period, String sourceId, String code, String teacher) =>
        Course.fromMap({
          'sourceCourseId': sourceId,
          'name': '人工智能法学专题',
          'courseCode': code,
          'teacher': teacher,
          'location': '新上院 N100',
          'weekday': 3,
          'startPeriod': period,
          'endPeriod': period,
          'activeWeeks': [1, 2, 3, 4],
          'weeksInferred': period == 4,
        });

    final joined = normalizePortalCourses([
      fragment(3, 'arrange-3', 'LAW7001-01', '朱军，庄加园'),
      fragment(4, 'arrange-4', 'LAW7001', '庄加园、朱军'),
      fragment(5, 'arrange-5', 'LAW7001-X01', '朱军,庄加园'),
    ]);

    expect(joined, hasLength(1));
    expect(joined.single.firstPeriod, 3);
    expect(joined.single.lastPeriod, 5);
  });

  test('concurrent Canvas refresh requests share the active synchronization',
      () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppController(
      SilentNotifications(),
      credentialStore: MemoryCredentialStore(),
    );
    await app.bootstrap();
    await app.saveSyncedData(
      'student',
      [
        Course.fromMap({
          'name': '测试课程',
          'weekday': 1,
          'startPeriod': 1,
          'endPeriod': 2,
        })
      ],
      CanvasSnapshot.empty(),
    );
    final completer = Completer<SyncBundle?>();
    var calls = 0;
    app.registerLoader(() {
      calls++;
      return completer.future;
    });

    final first = app.refreshNow();
    final second = app.refreshNow();
    expect(calls, 1);
    completer.complete(null);
    await Future.wait([first, second]);
    expect(calls, 1);
    app.dispose();
  });

  test('automatic Canvas initialization waits for loader and saves matching',
      () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppController(
      SilentNotifications(),
      credentialStore: MemoryCredentialStore(),
    );
    await app.bootstrap();
    final portalCourse = Course.fromMap({
      'name': '人工智能法学专题',
      'courseCode': 'LAW7001',
      'weekday': 1,
      'startPeriod': 3,
      'endPeriod': 4,
    });
    await app.saveSyncedData(
      'student',
      [portalCourse],
      CanvasSnapshot.empty(),
    );

    final initialization = app.initializeCanvasAfterLogin();
    await Future<void>.delayed(Duration.zero);
    app.registerLoader(() async => SyncBundle(
          app.courses,
          CanvasSnapshot(
            dashboardItems: const [],
            courses: const [
              CanvasCourseData(
                id: 'canvas-law-7001',
                name: '人工智能法学专题',
                courseCode: 'LAW7001',
                syllabusHtml: '',
                announcements: [],
                people: [],
              ),
            ],
            syncedAt: DateTime(2026, 9, 21),
          ),
        ));

    expect(await initialization, isTrue);
    expect(app.canvas.courses, hasLength(1));
    expect(app.courses.single.canvasCourseId, 'canvas-law-7001');
    app.dispose();
  });

  test('term week count updates immediately without reminders', () async {
    SharedPreferences.setMockInitialValues({});
    final notifications = CountingNotifications();
    final app = AppController(notifications);
    final saved = app.setTerm(DateTime(2026, 9, 14), 20);
    expect(app.totalWeeks, 20);
    expect(app.termStart, DateTime(2026, 9, 14));
    await saved;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(notifications.syncCalls, 0);
    app.dispose();
  });

  test('changing reminder lead time persists and reschedules reminders',
      () async {
    SharedPreferences.setMockInitialValues({});
    final notifications = CountingNotifications();
    final app = AppController(notifications);
    await app.setReminderMode(ReminderMode.push);
    final previousCalls = notifications.syncCalls;

    await app.setReminderMinutes(30);

    expect(app.reminderMinutes, 30);
    expect(notifications.syncCalls, previousCalls + 1);
    expect(notifications.lastReminderMinutes, 30);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('reminderMinutes'), 30);
    app.dispose();
  });

  test('captured JSON metadata enriches a scheduled DOM course', () {
    final scheduled = Course.fromMap({
      'name': '知识产权法 LAW6001',
      'weekday': 2,
      'startPeriod': 3,
      'endPeriod': 4,
    });
    final metadata = Course.fromMap({
      '课程名称': '知识产权法',
      '课程代码': 'LAW6001',
      '教师姓名': '李老师',
      'SKDD': '东中院2-201',
    });
    final result = normalizePortalCourses([scheduled, metadata]);
    expect(result, hasLength(1));
    expect(result.single.teacher, '李老师');
    expect(result.single.location, '东中院2-201');
  });

  test('notification failure does not roll back synchronized data', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppController(
      FailingNotifications(),
      credentialStore: MemoryCredentialStore(),
    );
    final course = Course.fromMap({
      'name': '算法',
      'teacher': '李老师',
      'location': '东上院101',
      'time': '周一第1-2节',
    });
    final result = await app.saveSyncedData(
      'test-account',
      [course],
      CanvasSnapshot.empty(),
      remember: true,
    );
    expect(result.dataSaved, true);
    expect(result.notificationWarning, isNotNull);
    expect(app.courses.single.teacher, '李老师');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('courses'), contains('东上院101'));
    app.dispose();
  });
}
