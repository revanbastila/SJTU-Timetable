import 'dart:collection';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/main.dart';
import 'package:jiaotong_course/models/course.dart';
import 'package:jiaotong_course/models/canvas_data.dart';
import 'package:jiaotong_course/services/notification_service.dart';
import 'package:jiaotong_course/services/timetable_widget_bridge.dart';
import 'package:jiaotong_course/state/app_controller.dart';

List<Course> probeCourses() => [
      for (var i = 0; i < 20; i++)
        Course(
            id: 'course$i',
            name: 'course$i',
            teacher: 'Teacher',
            location: 'Room',
            time: '08:00–09:40',
            weekday: i % 7 + 1,
            startHour: 8,
            startMinute: 0,
            endHour: 9,
            endMinute: 40,
            activeWeeks: [for (var week = 1; week <= 18; week++) week],
            rawWeekText: '1-18',
            courseIdentity: 'course$i',
            canvasCourseId: '$i')
    ];

// This same probe runs against the unchanged formal source and test source.
// Deterministic work counts, rather than noisy wall time, establish the gain.
class CountingCourses extends ListBase<Course> {
  CountingCourses(this.values);
  final List<Course> values;
  int reads = 0;
  @override
  int get length => values.length;
  @override
  set length(int value) => throw UnsupportedError('read only');
  @override
  Course operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, Course value) =>
      throw UnsupportedError('read only');
}

class CountingApp extends AppController {
  CountingApp() : super(NotificationService()) {
    courses = probeCourses();
  }
  int dayCalculations = 0;
  @override
  List<Course> getEffectiveCoursesForDate(DateTime date) {
    dayCalculations++;
    return super.getEffectiveCoursesForDate(date);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('count repeated message/color source reads', () {
    final source = CountingCourses(probeCourses());
    final app = AppController(NotificationService())
      ..courses = source
      ..canvas = CanvasSnapshot.fromMap({
        'courses': [
          for (var course = 0; course < 20; course++)
            {
              'id': '$course',
              'name': 'course$course',
              'announcements': [
                for (var item = 0; item < 3; item++)
                  {
                    'id': '$item',
                    'title': '公告$item',
                    'created_at': '2026-10-03T08:00:00Z'
                  }
              ]
            }
        ]
      });
    app.unreadMessageCount;
    source.reads = 0;
    for (var iteration = 0; iteration < 300; iteration++) {
      app.unreadMessageCount;
    }
    // ignore: avoid_print
    print(
        '[hot-path] message source reads, 300 unchanged reads: ${source.reads}');
    final course = source.values.first;
    final color = app.courseColorValue(course);
    source.reads = 0;
    for (var iteration = 0; iteration < 300; iteration++) {
      expect(app.courseColorValue(course), color);
    }
    // ignore: avoid_print
    print(
        '[hot-path] color source reads, 300 unchanged reads: ${source.reads}');
    app.dispose();
  });

  test('count unchanged full-term widget calculations', () async {
    const channel = MethodChannel('cn.sjtu.jiaotong_course/widget');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var sends = 0;
    var bytes = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      sends++;
      bytes = utf8.encode((call.arguments as Map)['snapshot'] as String).length;
      return null;
    });
    final app = CountingApp();
    final bridge = TimetableWidgetBridge()..attach(app);
    for (var iteration = 0; iteration < 20; iteration++) {
      await bridge.syncNow();
    }
    // ignore: avoid_print
    print(
        '[hot-path] 20 unchanged widget checks: ${app.dayCalculations} date calculations, $sends native sends');
    // ignore: avoid_print
    print('[hot-path] widget snapshot bytes: $bytes');
    bridge.detach();
    app.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('count application-root rebuilds for unrelated changes',
      (tester) async {
    final app = AppController(NotificationService());
    await tester.pumpWidget(JiaotongCourseApp(app: app));
    var previous = tester.widget<MaterialApp>(find.byType(MaterialApp));
    var rebuilds = 0;
    for (var week = 1; week <= 5; week++) {
      app.selectWeek(week);
      await tester.pump();
      final next = tester.widget<MaterialApp>(find.byType(MaterialApp));
      if (!identical(previous, next)) rebuilds++;
      previous = next;
    }
    // ignore: avoid_print
    print('[hot-path] root rebuilds, 5 week selections: $rebuilds');
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });
}
