import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/models/course.dart';
import 'package:jiaotong_course/models/canvas_data.dart';
import 'package:jiaotong_course/models/semester_timetable.dart';
import 'package:jiaotong_course/models/teaching_calendar.dart';
import 'package:jiaotong_course/pages/week_page.dart';
import 'package:jiaotong_course/services/notification_service.dart';
import 'package:jiaotong_course/services/timetable_widget_bridge.dart';
import 'package:jiaotong_course/state/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_database.dart';

Course meeting(
  String id,
  List<int> weeks, {
  String name = '刑事程序法',
  int day = 1,
  int first = 1,
  int last = 2,
  String raw = '',
  String location = '新上院 N100',
}) =>
    Course.fromMap({
      'id': id,
      'courseIdentity': name,
      'name': name,
      'teacher': '张三',
      'location': location,
      'weekday': day,
      'startPeriod': first,
      'endPeriod': last,
      'activeWeeks': weeks,
      'rawWeekText': raw,
    });

class QuietNotifications extends NotificationService {
  int syncs = 0;
  @override
  Future<void> initialize() async {}

  @override
  Future<NotificationSyncReport> sync(
    List<Course> courses,
    ReminderMode mode, {
    DateTime? termStart,
    int totalWeeks = 18,
    int reminderMinutes = 15,
  }) async {
    syncs++;
    return const NotificationSyncReport([]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('week modes remain usable across light and dark theme changes',
      (tester) async {
    final app = AppController(QuietNotifications(), database: MemoryDatabase())
      ..selectedWeek = 1
      ..courses = [
        meeting('theme-course', [1, 2])
      ];
    for (final brightness in [
      Brightness.light,
      Brightness.dark,
      Brightness.light
    ]) {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
                seedColor:
                    brightness == Brightness.dark ? Colors.red : Colors.blue,
                brightness: brightness)),
        home: Scaffold(body: WeekPage(app: app)),
      ));
      await tester.pumpAndSettle();
      for (final dynamicDisplay in [false, true]) {
        await app.setDynamicWeekDisplay(dynamicDisplay);
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.calendar_month_rounded), findsOneWidget);
        expect(
            find.byIcon(
                dynamicDisplay ? Icons.schedule_rounded : Icons.layers_rounded),
            findsOneWidget);
        final label = find.byKey(Key(
            dynamicDisplay ? 'week-date-range' : 'semester-timetable-title'));
        final theme = Theme.of(tester.element(label));
        expect(theme.brightness, brightness);
        expect(
            tester.widget<Text>(label).style?.color, theme.colorScheme.primary);
        expect(
            tester
                .widget<IconButton>(
                    find.byKey(const Key('week-display-switch')))
                .color,
            theme.colorScheme.primary);
        expect(
            tester
                .widget<Material>(
                    find.byKey(const Key('week-display-floating-surface')))
                .color,
            theme.colorScheme.surfaceContainerLow);
        if (!dynamicDisplay) expect(find.text('1-2周'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });

  test(
    'semester labels preserve ranges, declared parity and discrete weeks',
    () {
      expect(
        semesterCourseWeeks(meeting('all', List.generate(16, (i) => i + 1))),
        '1-16周',
      );
      expect(
        semesterCourseWeeks(
          meeting('odd', List.generate(8, (i) => 2 * i + 1), raw: '1-16周（单周）'),
        ),
        '1-15周（单周）',
      );
      expect(
        semesterCourseWeeks(
          meeting('even', List.generate(8, (i) => 2 * i + 2), raw: '1-16周（双周）'),
        ),
        '2-16周（双周）',
      );
      expect(
        semesterCourseWeeks(meeting('list', [7, 1, 5, 3, 3], raw: '1,3,5,7周')),
        '1周，3周，5周，7周',
      );
      expect(
        semesterCourseWeeks(meeting('irregular', [1, 3, 7], raw: '单周')),
        '1周，3周，7周',
      );
      expect(semesterCourseWeeks(meeting('one', [6])), '第6周');
      expect(
          semesterCourseWeeks(meeting(
              'ranges', [2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13],
              name: '习近平法治思想')),
          '2-5周，7-13周');
      expect(semesterCourseWeeks(meeting('mixed', [9, 2, 1, 6, 5, 9, 0, -1])),
          '1-2周，5-6周，9周');
      expect(semesterCourseWeeks(meeting('missing-even', [2, 4, 8], raw: '双周')),
          '2周，4周，8周');
    },
  );

  testWidgets('floating mode control changes icons and stays in bottom right',
      (tester) async {
    final app = AppController(QuietNotifications(), database: MemoryDatabase());
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: WeekPage(app: app))));
    final button = find.byKey(const Key('week-display-switch'));
    final surface = find.byKey(const Key('week-display-floating-surface'));
    final area = tester.getRect(find.byKey(const Key('week-timetable-area')));
    final initial = tester.getRect(surface);
    expect(initial.size, const Size(48, 48));
    expect(area.right - initial.right, 12);
    expect(area.bottom - initial.bottom, 12);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('动态显示'), findsNothing);
    expect(find.text('静态显示'), findsNothing);
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(find.byTooltip('切换为静态课表'), findsOneWidget);
    expect(find.byIcon(Icons.sync_rounded), findsNothing);
    await tester.tapAt(initial.topLeft + const Offset(3, 24));
    await tester.pumpAndSettle();
    expect(app.dynamicWeekDisplay, isFalse);
    expect(find.byIcon(Icons.layers_rounded), findsOneWidget);
    expect(find.byTooltip('切换为动态课表'), findsOneWidget);
    expect(find.text('学期课表'), findsOneWidget);
    final staticArea =
        tester.getRect(find.byKey(const Key('week-timetable-area')));
    expect(staticArea.bottom - tester.getRect(surface).bottom, 12);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(app.dynamicWeekDisplay, isTrue);
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });

  test(
    'semester projection unions identical slots and retains merged sessions',
    () {
      final input = [
        meeting('odd', [1, 3], raw: '1,3周'),
        meeting('even', [2, 4], raw: '2,4周'),
        meeting('adjacent', [1, 2, 3, 4], first: 3, last: 4),
        meeting('other-day', [1, 2, 3, 4], day: 2),
        meeting('other-room', [1, 2, 3, 4], location: '新上院 N200'),
        meeting('later-weeks', [5, 6], first: 5, last: 6),
      ];
      final before = jsonEncode(input.map((course) => course.toMap()).toList());
      final output = semesterTimetableCourses(input);
      expect(output, hasLength(4));
      final joined = output.singleWhere((course) => course.lastPeriod == 4);
      expect(joined.firstPeriod, 1);
      expect(joined.activeWeeks, [1, 2, 3, 4]);
      expect(output.map((course) => course.id).toSet(), hasLength(4));
      for (final course in output) {
        expect(input.any((original) => original.id == course.id), isTrue);
      }
      expect(
        jsonEncode(input.map((course) => course.toMap()).toList()),
        before,
      );
    },
  );

  test(
    'mode persists on restart and switching cannot change other consumers',
    () async {
      final storage = MemoryDatabase();
      final notifications = QuietNotifications();
      final app = AppController(
        notifications,
        database: storage,
        calendarClock: () => DateTime(2030, 1, 16),
      )
        ..termStart = DateTime(2030, 1, 7)
        ..selectedWeek = 9
        ..courses = [
          meeting('original', [1, 2]),
        ];
      final input = app.courses;
      final canvas = app.canvas;
      final widgets = <Object?>[];
      const channel = MethodChannel('cn.sjtu.jiaotong_course/widget');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        widgets.add(call.arguments);
        return null;
      });
      final bridge = TimetableWidgetBridge()..attach(app);
      await bridge.syncNow();
      final snapshots = widgets.length;
      final effective = app.getEffectiveCoursesForDate(DateTime(2030, 1, 7));
      expect(app.dynamicWeekDisplay, isTrue);
      await app.setDynamicWeekDisplay(false);
      await bridge.syncNow();
      expect(app.selectedWeek, 9);
      expect(app.courses, same(input));
      expect(app.canvas, same(canvas));
      expect(app.getEffectiveCoursesForDate(DateTime(2030, 1, 7)), effective);
      expect(widgets, hasLength(snapshots));
      expect(notifications.syncs, 0);
      expect(storage.fullWrites, 0);
      expect(storage.canvasWrites, 0);
      final next = AppController(
        QuietNotifications(),
        database: MemoryDatabase(),
      );
      await next.bootstrap();
      expect(next.dynamicWeekDisplay, isFalse);
      next.dispose();
      await app.setDynamicWeekDisplay(true);
      expect(app.selectedWeek, 2);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('dynamicWeekDisplay'), isTrue);
      await bridge.syncNow();
      expect(widgets, hasLength(snapshots));
      bridge.detach();
      app.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );

  testWidgets(
    'static view bypasses week/calendar rules and dynamic restores them',
    (tester) async {
      final app = AppController(
        QuietNotifications(),
        database: MemoryDatabase(),
        calendarClock: () => DateTime(2030, 1, 9),
      )
        ..termStart = DateTime(2030, 1, 7)
        ..selectedWeek = 1
        ..courses = [
          meeting('monday', [1, 2], name: '星期一原课'),
          meeting('tuesday', [2], name: '第二周课程', day: 2),
          meeting('wednesday', [3], name: '第三周课程', day: 3),
        ]
        ..teachingCalendar = TeachingCalendar.parse(
          jsonEncode({
            'version': 1,
            'rules': [
              {'date': '2030-01-07', 'type': 'holiday'},
              {'date': '2030-01-08', 'type': 'no_class'},
              {'date': '2030-01-12', 'type': 'makeup', 'use_weekday': 1},
              {
                'date': '2030-01-13',
                'type': 'makeup',
                'use_weekday': 2,
                'use_week': 2,
              },
            ],
          }),
        );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WeekPage(app: app)),
        ),
      );
      expect(find.text('动态显示'), findsNothing);
      expect(find.text('第三周课程'), findsNothing);
      expect(find.byKey(const Key('week-header-label-1')), findsOneWidget);
      final dynamicMondayX = tester.getTopLeft(find.text('星期一原课')).dx;
      final date = tester.getRect(find.byKey(const Key('week-date-range')));
      final current = tester.getRect(
        find.byKey(const Key('week-current-marker')),
      );
      expect(current.left, greaterThanOrEqualTo(date.right));
      expect(current.center.dy, closeTo(date.center.dy, 2));
      expect(find.byIcon(Icons.sync_rounded), findsNothing);

      await tester.tap(find.byKey(const Key('week-display-switch')));
      await tester.pumpAndSettle();
      expect(find.text('动态显示'), findsNothing);
      expect(find.byIcon(Icons.layers_rounded), findsOneWidget);
      expect(find.text('学期课表'), findsOneWidget);
      expect(find.byType(DropdownButton<int>), findsNothing);
      expect(find.byKey(const Key('week-date-range')), findsNothing);
      expect(find.byKey(const Key('week-current-marker')), findsNothing);
      expect(find.byKey(const Key('week-header-label-1')), findsNothing);
      for (final name in ['星期一原课', '第二周课程', '第三周课程']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('1-2周'), findsOneWidget);
      expect(find.text('第2周'), findsOneWidget);
      expect(find.text('第3周'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('星期一原课')).dx,
        lessThan(dynamicMondayX),
      );
      expect(app.getEffectiveCoursesForDate(DateTime(2030, 1, 7)), isEmpty);

      app.selectWeek(3);
      await tester.tap(find.byKey(const Key('week-display-switch')));
      await tester.pumpAndSettle();
      expect(app.selectedWeek, 1);
      expect(find.text('第三周课程'), findsNothing);
      expect(tester.getTopLeft(find.text('星期一原课')).dx, dynamicMondayX);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
    },
  );

  testWidgets(
    'narrow screen handles large text and overlapping static blocks',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app =
          AppController(QuietNotifications(), database: MemoryDatabase())
            ..selectedWeek = 18
            ..courses = [
              for (var i = 0; i < 6; i++)
                meeting(
                  'block-$i',
                  [1, 3, 5, 7],
                  name: '同一时间的不同课程$i',
                  first: 1,
                  last: 1,
                  raw: '1,3,5,7周',
                ),
            ];
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(body: WeekPage(app: app)),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('week-display-switch')));
      await tester.pumpAndSettle();
      expect(find.text('1周，3周，5周，7周'), findsNWidgets(6));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
    },
  );

  testWidgets(
    'static course details still observe Canvas linking and unlinking',
    (tester) async {
      final original = meeting('source-course', [1, 2]);
      final app =
          AppController(QuietNotifications(), database: MemoryDatabase())
            ..dynamicWeekDisplay = false
            ..courses = [original]
            ..canvas = CanvasSnapshot.fromMap({
              'courses': [
                {'id': 'canvas-1', 'name': original.name},
              ],
              'dashboardItems': [],
            });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WeekPage(app: app)),
        ),
      );
      await tester.tap(find.text(original.name));
      await tester.pumpAndSettle();
      expect(find.text('选择课程'), findsOneWidget);
      await app.mapCourseToCanvas(original, 'canvas-1');
      await tester.pumpAndSettle();
      expect(find.text('选择课程'), findsNothing);
      await app.mapCourseToCanvas(original, null);
      await tester.pumpAndSettle();
      expect(find.text('选择课程'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
    },
  );
}
