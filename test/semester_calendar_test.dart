import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jiaotong_course/models/course.dart';
import 'package:jiaotong_course/models/teaching_calendar.dart';
import 'package:jiaotong_course/pages/settings_page.dart';
import 'package:jiaotong_course/pages/week_page.dart';
import 'package:jiaotong_course/services/notification_service.dart';
import 'package:jiaotong_course/services/teaching_calendar_repository.dart';
import 'package:jiaotong_course/services/timetable_widget_bridge.dart';
import 'package:jiaotong_course/state/app_controller.dart';
import 'teaching_calendar_test.dart' show lesson;

Map<String, Object?> semester(
        String start, String end, String first, int weeks, List<int> exams) =>
    {
      'start_date': start,
      'end_date': end,
      'first_week_start': first,
      'total_weeks': weeks,
      'exam_weeks': exams
    };
String sample(
        {String first = '2030-01-07',
        int weeks = 3,
        List<int> exams = const [2, 3],
        String end = '2030-01-27'}) =>
    jsonEncode({
      'version': 2,
      'academic_year': '2029-2030',
      'semesters': {
        'fall': semester('2030-01-07', end, first, weeks, exams),
        'spring': null,
        'summer': null
      },
      'rules': [
        {'date': '2030-01-14', 'type': 'holiday'},
        {
          'date': '2030-01-26',
          'type': 'makeup',
          'use_weekday': 1,
          'use_week': 3
        }
      ]
    });

class RecordingReminders extends NotificationService {
  DateTime? lastStart;
  int? lastWeeks;
  @override
  Future<void> initialize() async {}
  @override
  Future<NotificationSyncReport> sync(List<Course> courses, ReminderMode mode,
      {DateTime? termStart,
      int totalWeeks = 18,
      int reminderMinutes = 15}) async {
    lastStart = termStart;
    lastWeeks = totalWeeks;
    return const NotificationSyncReport([]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('cold offline bootstrap takes cached semester before selecting week',
      () async {
    SharedPreferences.setMockInitialValues({
      TeachingCalendarRepository.cacheKey: sample(),
      'termStart': '2025-09-01T00:00:00.000',
      'totalWeeks': 22
    });
    final app = AppController(RecordingReminders(),
        calendarClock: () => DateTime(2030, 1, 21),
        calendarRepository: TeachingCalendarRepository(
            fetch: () async => throw const SocketException('offline')));
    await app.bootstrap();
    expect(app.termStart, DateTime(2030, 1, 7));
    expect(app.totalWeeks, 3);
    expect(app.selectedWeek, 3);
    expect(app.examWeeks, [2, 3]);
    await app.refreshTeachingCalendar();
    expect(app.totalWeeks, 3);
    app.dispose();
  });

  test(
      'both reminder modes keep exam courses and cancel dates beyond updated end',
      () async {
    const channel = MethodChannel('dexterous.com/flutter/local_notifications');
    final pending = <int, Map>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'initialize':
        case 'areNotificationsEnabled':
        case 'canScheduleExactNotifications':
          return true;
        case 'pendingNotificationRequests':
          return pending.values
              .map((v) =>
                  {'id': v['id'], 'title': '', 'body': '', 'payload': null})
              .toList();
        case 'zonedSchedule':
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
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final service = NotificationService();
    final courses = [
      lesson('Monday', 1, [1, 2, 3])
    ];
    for (final mode in [ReminderMode.push, ReminderMode.alarm]) {
      pending.clear();
      service.calendar = TeachingCalendar.parse(sample());
      await service.sync(courses, mode,
          termStart: DateTime(2030, 1, 7), totalWeeks: 3);
      expect(
          pending.values
              .map((v) => (v['scheduledDateTime'] as String).substring(0, 10))
              .toSet(),
          {'2030-01-07', '2030-01-21', '2030-01-26'});
      service.calendar = TeachingCalendar.parse(sample(end: '2030-01-20'));
      await service.sync(courses, mode,
          termStart: DateTime(2030, 1, 7), totalWeeks: 3);
      expect(
          pending.values
              .map((v) => (v['scheduledDateTime'] as String).substring(0, 10))
              .toSet(),
          {'2030-01-07'});
    }
  });

  test(
      'actual downloaded v2 parses unpublished null semesters and cross-year fall',
      () {
    final text = File('test/fixtures/calendar_semesters_v2.json')
        .readAsStringSync()
        .replaceFirst('\ufeff', '');
    final calendar = TeachingCalendar.parse(text);
    expect(calendar.version, '2');
    expect(calendar.academicYear, '2026-2027');
    expect(calendar.semesters.keys, ['fall']);
    final fall = calendar.semesterFor(DateTime(2026, 10, 3))!;
    expect(fall.firstWeekStart, DateTime(2026, 9, 14));
    expect(fall.totalWeeks, 18);
    expect(fall.examWeeks, [17, 18]);
    expect(fall.weekFor(DateTime(2026, 9, 14)), 1);
    expect(fall.weekFor(DateTime(2026, 9, 20, 23)), 1);
    expect(fall.weekFor(DateTime(2026, 9, 21)), 2);
    expect(fall.weekFor(DateTime(2026, 10, 4)), 3);
    expect(calendar.semesterFor(DateTime(2027, 1, 17)), same(fall));
    expect(fall.weekFor(DateTime(2027, 1, 17, 23)), 18);
    expect(calendar.semesterFor(DateTime(2027, 1, 18)), isNull);
    expect(calendar.semesterFor(DateTime.utc(2026, 9, 13, 16)), same(fall));
    expect(calendar.ruleFor(DateTime(2026, 10, 1))!.type, 'holiday');
  });

  test('fall spring summer use date ranges and clamp to declared weeks', () {
    final calendar = TeachingCalendar.parse(jsonEncode({
      'version': 3,
      'academic_year': '2029-2030',
      'rules': [],
      'semesters': {
        'fall':
            semester('2029-09-10', '2030-01-13', '2029-09-10', 18, [17, 18]),
        'spring': semester('2030-02-18', '2030-06-23', '2030-02-18', 18, [18]),
        'summer': semester('2030-07-01', '2030-08-11', '2030-07-01', 4, [4])
      }
    }));
    expect(calendar.semesterFor(DateTime(2030, 1, 1))!.id, 'fall');
    expect(calendar.semesterFor(DateTime(2030, 2, 18))!.id, 'spring');
    expect(calendar.semesterFor(DateTime(2030, 6, 23))!.id, 'spring');
    expect(calendar.semesterFor(DateTime(2030, 7, 1))!.id, 'summer');
    expect(
        calendar
            .semesterFor(DateTime(2030, 8, 11))!
            .weekFor(DateTime(2030, 8, 11)),
        4);
    expect(calendar.semesterFor(DateTime(2030, 6, 24)), isNull);
  });

  test(
      'remote metadata wins over manual fallback and refresh updates all consumers',
      () async {
    var now = DateTime(2030, 1, 21);
    var remote = sample();
    final reminders = RecordingReminders();
    final app = AppController(reminders,
        calendarClock: () => now,
        calendarRepository:
            TeachingCalendarRepository(fetch: () async => remote))
      ..termStart = DateTime(2026, 9, 14)
      ..totalWeeks = 18
      ..loggedIn = true
      ..reminderMode = ReminderMode.push
      ..courses = [
        lesson('Monday', 1, [1, 2, 3])
      ];
    await app.refreshTeachingCalendar();
    expect(app.termStart, DateTime(2030, 1, 7));
    expect(app.totalWeeks, 3);
    expect(app.currentAcademicWeek, 3);
    expect(app.selectedWeek, 3);
    expect(app.examWeeks, [2, 3]);
    expect(app.getEffectiveCoursesForDate(now).single.name, 'Monday');
    expect(app.effectiveCoursesForWeek(3).where((c) => c.weekday == 1),
        hasLength(1));
    expect(app.getEffectiveCoursesForDate(DateTime(2030, 1, 14)), isEmpty);
    expect(app.getEffectiveCoursesForDate(DateTime(2030, 1, 26)), hasLength(1));
    await app.setTerm(DateTime(2035, 1, 1), 22);
    expect(app.termStart, DateTime(2030, 1, 7));
    remote = sample(first: '2030-01-14', weeks: 2, exams: [2]);
    await app.refreshTeachingCalendar();
    expect(app.termStart, DateTime(2030, 1, 14));
    expect(app.totalWeeks, 2);
    expect(app.currentAcademicWeek, 2);
    expect(app.selectedWeek, 2);
    expect(app.examWeeks, [2]);
    expect(reminders.lastStart, app.termStart);
    expect(reminders.lastWeeks, app.totalWeeks);
    now = DateTime(2030, 1, 28);
    await app.restoreReminders();
    expect(app.currentSemester, isNull);
    expect(app.termStart, DateTime(2026, 9, 14));
    app.dispose();
  });

  test('offline cache restores semesters; invalid metadata cannot replace it',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(TeachingCalendarRepository.cacheKey, sample());
    var response = '';
    var offline = true;
    final repo = TeachingCalendarRepository(fetch: () async {
      if (offline) throw const SocketException('offline');
      return response;
    });
    final cached = repo.readCache(prefs);
    expect(cached.semesterFor(DateTime(2030, 1, 21))!.examWeeks, [2, 3]);
    expect(await repo.refresh(cached), isNull);
    offline = false;
    final invalid = jsonDecode(sample()) as Map;
    invalid['semesters']['fall']['exam_weeks'] = [99];
    response = jsonEncode(invalid);
    expect(await repo.refresh(cached), isNull);
    expect(prefs.getString(TeachingCalendarRepository.cacheKey), sample());
    response = sample(exams: [3]);
    final updated = await repo.refresh(cached);
    expect(updated!.semesters['fall']!.examWeeks, [3]);
    expect(repo.readCache(prefs).semesters['fall']!.examWeeks, [3]);
  });

  test('widget receives remote term and exact dated week/course results',
      () async {
    final app = AppController(NotificationService(),
        calendarClock: () => DateTime(2030, 1, 21))
      ..teachingCalendar = TeachingCalendar.parse(sample())
      ..courses = [
        lesson('Monday', 1, [1, 2, 3])
      ];
    Map? snapshot;
    const channel = MethodChannel('cn.sjtu.jiaotong_course/widget');
    testerChannel(MethodCall call) async {
      snapshot =
          jsonDecode((call.arguments as Map)['snapshot'] as String) as Map;
      return null;
    }

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, testerChannel);
    final bridge = TimetableWidgetBridge()..attach(app);
    await bridge.syncNow();
    bridge.detach();
    expect(snapshot!['termStart'], '2030-01-07');
    expect(snapshot!['totalWeeks'], 3);
    expect(snapshot!['academicYear'], '2029-2030');
    expect(snapshot!['semesterEnd'], '2030-01-27');
    final days = snapshot!['effectiveDays'] as Map;
    expect(days['2030-01-21']['academicWeek'], 3);
    expect(days['2030-01-21']['courses'].single['name'], 'Monday');
    expect(days['2030-01-14']['courses'], isEmpty);
    expect(days['2030-01-26']['courses'].single['name'], 'Monday');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    app.dispose();
  });

  testWidgets(
      'semester editing UI is removed while remote metadata remains active',
      (tester) async {
    final app = AppController(NotificationService(),
        calendarClock: () => DateTime(2030, 1, 21))
      ..teachingCalendar = TeachingCalendar.parse(sample());
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SettingsPage(app: app, advanced: true))));
    expect(find.byKey(const ValueKey('setting-surface-学期设置')), findsNothing);
    expect(find.text('第 1 周周一'), findsNothing);
    expect(find.text('学期总周数'), findsNothing);
    expect(app.termStart, DateTime(2030, 1, 7));
    expect(app.totalWeeks, 3);
    expect(app.currentAcademicWeek, 3);
    expect(app.examWeeks, [2, 3]);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });

  testWidgets(
      'exam/current columns align and use the same existing marker style',
      (tester) async {
    var date = DateTime(2030, 1, 21);
    final app = AppController(NotificationService(), calendarClock: () => date)
      ..teachingCalendar = TeachingCalendar.parse(sample())
      ..selectedWeek = 3;
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: WeekPage(app: app))));
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    final exam2 = find.byKey(const ValueKey('week-exam-2')).last;
    final exam3 = find.byKey(const ValueKey('week-exam-3')).last;
    final current3 = find.byKey(const ValueKey('week-current-3')).last;
    expect(tester.getTopLeft(exam2).dx, tester.getTopLeft(exam3).dx);
    final currentX = tester.getTopLeft(current3).dx;
    expect(currentX, greaterThan(tester.getTopLeft(exam3).dx));
    expect(
        tester.widget<Text>(exam3).style, tester.widget<Text>(current3).style);
    expect(tester.widget<Text>(exam3).style!.fontSize, 12);
    expect(tester.widget<Text>(exam3).style!.fontWeight, FontWeight.w600);
    await tester.tap(find.text('第 2 周').last);
    await tester.pumpAndSettle();
    date = DateTime(2030, 1, 14);
    app.teachingCalendar = TeachingCalendar.parse(sample(exams: [3]));
    app.notifyListeners();
    await tester.pump();
    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    expect(
        tester.getTopLeft(find.byKey(const ValueKey('week-current-2')).last).dx,
        currentX);
    expect(find.byKey(const ValueKey('week-exam-2')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });
}
