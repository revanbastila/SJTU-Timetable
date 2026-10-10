import 'support/memory_database.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jiaotong_course/main.dart';
import 'package:jiaotong_course/models/app_theme.dart';
import 'package:jiaotong_course/models/canvas_data.dart';
import 'package:jiaotong_course/models/course.dart';
import 'package:jiaotong_course/models/teaching_calendar.dart';
import 'package:jiaotong_course/pages/home_shell.dart';
import 'package:jiaotong_course/pages/login_page.dart';
import 'package:jiaotong_course/services/notification_service.dart';
import 'package:jiaotong_course/services/app_database.dart';
import 'package:jiaotong_course/services/timetable_widget_bridge.dart';
import 'package:jiaotong_course/state/app_controller.dart';
import 'hot_path_benchmark_test.dart' show CountingApp;
import 'teaching_calendar_test.dart' show lesson;

CanvasSnapshot notices(String title) => CanvasSnapshot.fromMap({
      'courses': [
        {
          'id': 'c1',
          'name': '测试课程',
          'announcements': [
            {'id': '10', 'title': title, 'created_at': '2026-10-03T08:00:00Z'}
          ]
        }
      ],
      'dashboardItems': [],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('SQLite owns snapshots; announcement poll saves only Canvas', () async {
    final storage = MemoryDatabase();
    final app = AppController(NotificationService(), database: storage);
    final course = lesson('测试课程', 1, [1, 2, 3]).copyWith(canvasCourseId: 'c1');
    await app.saveSyncedData('test', [course], notices('旧公告'));
    final fullWrites = storage.fullWrites;
    final canvasWrites = storage.canvasWrites;
    await app.applyAnnouncementUpdates({
      'courses': [
        {
          'id': 'c1',
          'announcements': [
            {'id': '11', 'title': '新公告', 'created_at': '2026-10-03T09:00:00Z'}
          ]
        }
      ]
    }, app.sessionGeneration);
    expect(storage.fullWrites, fullWrites);
    expect(storage.canvasWrites, canvasWrites + 1);
    expect(
        storage.savedCanvas!.courses.single.announcements.first.title, '新公告');
    final prefs = await SharedPreferences.getInstance();
    for (final key in ['courses', 'canvas', 'courseColors']) {
      expect(prefs.getString(key), isNull);
    }
    expect(storage.savedCourses!.single.id, course.id);
    app.dispose();
  });

  test(
      'legacy data migrates once, and stale preferences cannot restore removed courses',
      () async {
    final old = lesson('旧课程', 1, [1, 2, 3]);
    final encoded = jsonEncode([old.toMap()]);
    SharedPreferences.setMockInitialValues({
      'courses': encoded,
      'courseSchema': 5,
      'canvas': jsonEncode(notices('旧公告').toMap()),
      'courseColors': jsonEncode({old.courseIdentity: 0xFF112233})
    });
    final storage = MemoryDatabase();
    final app = AppController(NotificationService(), database: storage);
    await app.bootstrap();
    expect(storage.savedCourses!.single.name, old.name);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('sqliteCacheMigrated'), true);
    expect(prefs.getString('courses'), isNull);
    expect(prefs.getString('canvas'), isNull);
    expect(prefs.getString('courseColors'), isNull);
    app.dispose();
    // An empty real snapshot is authoritative; an old mirror is not a fallback.
    await storage.saveCourses([]);
    await prefs.setString('courses', encoded);
    final next = AppController(NotificationService(), database: storage);
    await next.bootstrap();
    expect(next.courses, isEmpty);
    next.dispose();
  });

  test('unavailable SQL does not falsely report a successful save', () async {
    final app = AppController(NotificationService(), database: AppDatabase());
    await expectLater(
        app.saveSyncedData(
            'test',
            [
              lesson('课程', 1, [1])
            ],
            CanvasSnapshot.empty()),
        throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('username'), isNull);
    expect(prefs.getString('courses'), isNull);
    app.dispose();
  });

  test(
      'one feed survives reads, but updates on announcements/link changes/logout',
      () async {
    final course = lesson('测试课程', 1, [1, 2, 3]).copyWith(canvasCourseId: 'c1');
    final app = AppController(NotificationService(), database: MemoryDatabase())
      ..username = 'test'
      ..courses = [course]
      ..canvas = notices('新公告');
    final feed = app.messageFeed;
    expect(app.unreadMessageCount, 1);
    expect(app.messageFeed, same(feed));
    expect(() => feed.clear(), throwsUnsupportedError);
    await app.markMessageRead(feed.single.key);
    expect(app.unreadMessageCount, 0);
    expect(app.messageFeed, same(feed));
    app.canvas = notices('更新后的公告');
    expect(app.messageFeed.single.title, '更新后的公告');
    expect(app.unreadMessageCount, 0); // Stable ID preserves read flag.
    final afterUpdate = app.messageFeed;
    app.courses = [
      Course.fromMap({...course.toMap(), 'name': '修改课程名称'})
    ];
    expect(app.messageFeed, isNot(same(afterUpdate)));
    await app.logout();
    expect(app.messageFeed, isEmpty);
    app.dispose();
  });

  test('widget reuses calculations, retries delivery, invalidates real inputs',
      () async {
    const channel = MethodChannel('cn.sjtu.jiaotong_course/widget');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var fail = true;
    final sent = <Map<String, dynamic>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (fail) {
        fail = false;
        throw PlatformException(code: 'temporary');
      }
      sent.add(jsonDecode((call.arguments as Map)['snapshot'] as String)
          as Map<String, dynamic>);
      return null;
    });
    final app = CountingApp();
    final bridge = TimetableWidgetBridge()..attach(app);
    await bridge.syncNow();
    final calculations = app.dayCalculations;
    await bridge.syncNow();
    expect(app.dayCalculations, calculations);
    expect(sent.length, 1);
    app.selectWeek(2);
    await bridge.syncNow();
    expect(app.dayCalculations, calculations);
    final first = app.courses.first;
    app.courseColorValues[first.courseIdentity] = 0xFF112233;
    await bridge.syncNow();
    expect(sent.length, 2);
    app.courses = [
      Course.fromMap({...first.toMap(), 'teacher': '新的教师'})
    ];
    await bridge.syncNow();
    expect((sent.last['courses'] as List).single['teacher'], '新的教师');
    app.teachingCalendar = TeachingCalendar.parse(jsonEncode({
      'version': 2,
      'rules': [
        {'date': '2026-10-01', 'type': 'holiday'}
      ]
    }));
    await bridge.syncNow();
    expect(sent.last['effectiveDays']['2026-10-01']['courseRefs'], isEmpty);
    expect(sent.length, 4);
    bridge.detach();
    app.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets(
      'root ignores progress but responds to theme, mode and authentication',
      (tester) async {
    final app =
        AppController(NotificationService(), database: MemoryDatabase());
    const announcements =
        MethodChannel('cn.sjtu.jiaotong_course/announcements');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        announcements, (call) async => call.method == 'configure' ? null : '');
    await tester.pumpWidget(JiaotongCourseApp(app: app));
    MaterialApp root() => tester.widget<MaterialApp>(find.byType(MaterialApp));
    final initial = root();
    app.selectWeek(3);
    await tester.pump();
    expect(root(), same(initial));
    await app.setThemeChoice(AppThemeChoice.sjtuRed);
    await tester.pump();
    expect(root().theme!.colorScheme.primary,
        AppThemeChoice.sjtuRed.primaryFor(Brightness.light));
    await app.setInterfaceMode(InterfaceMode.dark);
    await tester.pump();
    expect(root().themeMode, ThemeMode.dark);
    app.loggedIn = true;
    app.selectWeek(4);
    await tester.pump();
    expect(root().home, isA<HomeShell>());
    app.loggedIn = false;
    app.selectWeek(5);
    await tester.pump();
    expect(root().home, isA<LoginPage>());
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 9));
    app.dispose();
    messenger.setMockMethodCallHandler(announcements, null);
  });
}
