import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jiaotong_course/models/course.dart';
import 'package:jiaotong_course/models/teaching_calendar.dart';
import 'package:jiaotong_course/pages/home_page.dart';
import 'package:jiaotong_course/pages/week_page.dart';
import 'package:jiaotong_course/services/notification_service.dart';
import 'package:jiaotong_course/services/teaching_calendar_repository.dart';
import 'package:jiaotong_course/services/timetable_widget_bridge.dart';
import 'package:jiaotong_course/state/app_controller.dart';

Course lesson(String id, int weekday, List<int> weeks) => Course(
    id: id,
    name: id,
    teacher: 'Teacher',
    location: 'Room',
    time: '08:00–09:40',
    weekday: weekday,
    startHour: 8,
    startMinute: 0,
    endHour: 9,
    endMinute: 40,
    activeWeeks: weeks,
    rawWeekText: weeks.join(','),
    courseIdentity: id);

String document(int version, List<Map<String, Object>> rules) =>
    jsonEncode({'version': version, 'rules': rules});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final term = DateTime(2030, 1, 7);
  final mon = lesson('Monday', 1, [1, 2]);
  final tue = lesson('Tuesday week 2', 2, [2]);
  final original = [mon, tue];
  final text = document(1, [
    {'date': '2030-01-07', 'type': 'holiday'},
    {'date': '2030-01-08', 'type': 'no_class'},
    {'date': '2030-01-12', 'type': 'makeup', 'use_weekday': 1},
    {'date': '2030-01-13', 'type': 'makeup', 'use_weekday': 2, 'use_week': 2},
  ]);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'ordinary dates preserve original courses; holiday and no_class suppress',
      () {
    const empty = TeachingCalendar.empty();
    expect(empty.getEffectiveCoursesForDate(term, original, term, 2), [mon]);
    final calendar = TeachingCalendar.parse(text);
    expect(
        calendar.getEffectiveCoursesForDate(term, original, term, 2), isEmpty);
    expect(
        calendar.getEffectiveCoursesForDate(
            DateTime(2030, 1, 8),
            [
              lesson('Tuesday', 2, [1])
            ],
            term,
            2),
        isEmpty);
    expect(
        calendar.getEffectiveCoursesForDate(
            DateTime(2030, 1, 14), original, term, 2),
        [mon]);
    expect(
        calendar.getEffectiveCoursesForDate(DateTime(2029), original, term, 2),
        isEmpty);
  });

  test(
      'makeup uses actual week by default and explicit source week when present',
      () {
    final calendar = TeachingCalendar.parse(text);
    expect(
        calendar.getEffectiveCoursesForDate(
            DateTime(2030, 1, 12), original, term, 2),
        [mon]);
    expect(
        calendar.getEffectiveCoursesForDate(
            DateTime(2030, 1, 13), original, term, 2),
        [tue]);
    final otherTerm = TeachingCalendar.parse(document(1, [
      {'date': '2030-02-01', 'type': 'makeup', 'use_weekday': 1, 'use_week': 1}
    ]));
    expect(
        otherTerm.getEffectiveCoursesForDate(
            DateTime(2030, 2, 1), original, term, 2),
        isEmpty);
    expect(mon.weekday, 1);
    expect(mon.activeWeeks, [1, 2]);
  });

  test(
      'strict validation rejects malformed dates/types/weekdays/duplicate rules',
      () {
    for (final rule in [
      {'date': '2030-02-30', 'type': 'holiday'},
      {'date': '2030-01-01', 'type': 'unknown'},
      {'date': '2030-01-01', 'type': 'makeup', 'use_weekday': 8},
      {'date': '2030-01-01', 'type': 'makeup', 'use_weekday': 1, 'use_week': 0},
    ]) {
      expect(() => TeachingCalendar.parse(document(2, [rule])),
          throwsFormatException);
    }
    expect(
        () => TeachingCalendar.parse(document(2, [
              {'date': '2030-01-01', 'type': 'holiday'},
              {'date': '2030-01-01', 'type': 'no_class'}
            ])),
        throwsFormatException);
    expect(() => TeachingCalendar.parse('{"rules":[]}'), throwsFormatException);
  });

  test(
      'offline or malformed remote data retains cache; version change commits valid JSON',
      () async {
    SharedPreferences.setMockInitialValues(
        {TeachingCalendarRepository.cacheKey: text});
    final prefs = await SharedPreferences.getInstance();
    var response = '';
    var offline = true;
    final repo = TeachingCalendarRepository(fetch: () async {
      if (offline) throw const SocketException('offline');
      return response;
    });
    final cached = repo.readCache(prefs);
    expect(cached.version, '1');
    expect(await repo.refresh(cached), isNull);
    offline = false;
    response = '{"version":2,"rules":[{"date":"invalid","type":"holiday"}]}';
    expect(await repo.refresh(cached), isNull);
    expect(prefs.getString(TeachingCalendarRepository.cacheKey), text);
    response = document(1, []);
    expect((await repo.refresh(cached))?.rules, isEmpty);
    expect(prefs.getString(TeachingCalendarRepository.cacheKey), response);
    response = document(2, []);
    expect((await repo.refresh(cached))?.version, '2');
    expect(prefs.getString(TeachingCalendarRepository.cacheKey), response);
  });

  test(
      'widget dated snapshot and week view share effective courses without mutating source',
      () async {
    final app = AppController(NotificationService())
      ..termStart = term
      ..totalWeeks = 2
      ..courses = original
      ..teachingCalendar = TeachingCalendar.parse(text);
    final bridge = TimetableWidgetBridge();
    Map<String, dynamic>? captured;
    const channel = MethodChannel('cn.sjtu.jiaotong_course/widget');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      captured = jsonDecode((call.arguments as Map)['snapshot'] as String)
          as Map<String, dynamic>;
      return null;
    });
    bridge.attach(app);
    await bridge.syncNow();
    bridge.detach();
    final days = captured!['effectiveDays'] as Map;
    expect(days['2030-01-07']['courses'], isEmpty);
    expect(days['2030-01-07']['emptyMessage'], '今日放假，暂无课程');
    expect(days['2030-01-08']['emptyMessage'], '今日停课');
    expect(days['2030-01-12']['courses'].single['id'], mon.id);
    expect(days['2030-01-13']['courses'].single['id'], tue.id);
    expect(days['2030-01-12']['courses'].single['teacher'], mon.teacher);
    final week = app.effectiveCoursesForWeek(1);
    expect(week.map((c) => c.weekday), [6, 7]);
    expect(app.courses, same(original));
    expect(app.getEffectiveCoursesForDate(DateTime(2030, 1, 12)).single,
        same(mon));
    app.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
      'both reminder modes cancel holiday alarms and schedule makeup actual dates',
      () async {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final pending = <int, Map>{};
    final calls = <MethodCall>[];
    var failSchedule = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'initialize':
        case 'areNotificationsEnabled':
        case 'canScheduleExactNotifications':
          return true;
        case 'pendingNotificationRequests':
          return pending.values
              .map((value) =>
                  {'id': value['id'], 'title': '', 'body': '', 'payload': null})
              .toList();
        case 'zonedSchedule':
          if (failSchedule) throw PlatformException(code: 'test failure');
          final value = call.arguments as Map;
          pending[value['id'] as int] = value;
          return null;
        case 'cancel':
          pending.remove((call.arguments as Map)['id']);
          return null;
        case 'cancelAll':
          pending.clear();
          return null;
      }
      return null;
    });
    final service = NotificationService();
    for (final mode in [ReminderMode.push, ReminderMode.alarm]) {
      pending.clear();
      service.calendar = const TeachingCalendar.empty();
      await service.sync(original, mode, termStart: term, totalWeeks: 2);
      final oldHoliday = pending.entries
          .singleWhere((e) =>
              (e.value['scheduledDateTime'] as String).startsWith('2030-01-07'))
          .key;
      service.calendar = TeachingCalendar.parse(text);
      calls.clear();
      await service.sync(original, mode, termStart: term, totalWeeks: 2);
      expect(pending.containsKey(oldHoliday), false);
      expect(
          pending.values
              .map((v) => (v['scheduledDateTime'] as String).substring(0, 16))
              .toSet(),
          {
            '2030-01-12T07:45',
            '2030-01-13T07:45',
            '2030-01-14T07:45',
            '2030-01-15T07:45'
          });
      expect(calls.indexWhere((c) => c.method == 'cancel'),
          lessThan(calls.indexWhere((c) => c.method == 'zonedSchedule')));
    }
    service.calendar = const TeachingCalendar.empty();
    await service.sync(original, ReminderMode.alarm,
        termStart: term, totalWeeks: 2);
    final oldId = pending.entries
        .singleWhere((e) =>
            (e.value['scheduledDateTime'] as String).startsWith('2030-01-07'))
        .key;
    service.calendar = TeachingCalendar.parse(text);
    failSchedule = true;
    expect(
        (await service.sync(original, ReminderMode.alarm,
                termStart: term, totalWeeks: 2))
            .succeeded,
        false);
    expect(pending.containsKey(oldId), false);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
      'holiday UI suppresses current/upcoming cards and marks week header',
      (tester) async {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - now.weekday + 1);
    final course = lesson('Must not display', now.weekday, [1]);
    final app = AppController(NotificationService())
      ..termStart = monday
      ..courses = [course]
      ..selectedWeek = 1
      ..teachingCalendar = TeachingCalendar.parse(document(1, [
        {'date': calendarDateKey(now), 'type': 'holiday'}
      ]));
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: HomePage(app: app))));
    expect(find.text('今日放假，暂无课程'), findsOneWidget);
    expect(find.text(course.name), findsNothing);
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: WeekPage(app: app))));
    expect(find.text(course.name), findsNothing);
    expect(find.textContaining('放假'), findsOneWidget);
    final weekday = find.byKey(ValueKey('week-header-day-${now.weekday}'));
    final holiday = find.byKey(ValueKey('week-header-label-${now.weekday}'));
    final weekdayRect = tester.getRect(weekday);
    final header =
        find.ancestor(of: weekday, matching: find.byType(Container)).first;
    final headerRect = tester.getRect(header);
    expect(weekdayRect.center.dy, closeTo(headerRect.center.dy, 0.6));
    final holidayStyle = tester.widget<Text>(holiday).style!;
    final weekdayStyle = tester.widget<Text>(weekday).style!;
    expect(holidayStyle.fontSize, lessThan(weekdayStyle.fontSize!));
    expect(holidayStyle.color, weekdayStyle.color);
    final sliderRect =
        tester.getRect(find.byKey(const Key('week-scroll-hint')));
    expect(
        sliderRect.center.dx,
        closeTo(
            tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
            0.1));
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });
}
