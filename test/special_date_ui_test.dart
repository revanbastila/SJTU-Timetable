import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/models/teaching_calendar.dart';
import 'package:jiaotong_course/pages/home_page.dart';
import 'package:jiaotong_course/pages/week_page.dart';
import 'package:jiaotong_course/services/notification_service.dart';
import 'package:jiaotong_course/state/app_controller.dart';
import 'teaching_calendar_test.dart' show lesson;

void main() {
  test('all seven civil weekdays match only their actual displayed week', () {
    final monday = DateTime(2026, 9, 28);
    for (var day = 1; day <= 7; day++) {
      final today = monday.add(Duration(days: day - 1, hours: 23));
      expect(weekdayInDisplayedWeek(today, monday), day);
      expect(
          weekdayInDisplayedWeek(
              today, monday.subtract(const Duration(days: 7))),
          isNull);
      expect(weekdayInDisplayedWeek(today, monday.add(const Duration(days: 7))),
          isNull);
    }
    expect(weekdayInDisplayedWeek(DateTime.utc(2026, 9, 27, 16), monday), 1);
  });

  testWidgets(
      'header today accent follows theme and disappears on another week',
      (tester) async {
    final today = calendarCivilDate(shanghaiNow());
    final app = AppController(NotificationService())
      ..termStart = today.subtract(Duration(days: today.weekday - 1 + 14))
      ..selectedWeek = 3;
    for (final brightness in Brightness.values) {
      for (final seed in [Colors.blue, Colors.red]) {
        final scheme =
            ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
        app.selectedWeek = 3;
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(colorScheme: scheme),
            home: Scaffold(body: WeekPage(app: app))));
        await tester.pumpAndSettle();
        for (var day = 1; day <= 7; day++) {
          expect(
              tester
                  .widget<Text>(find.byKey(ValueKey('week-header-day-$day')))
                  .style
                  ?.color,
              day == today.weekday ? scheme.primary : scheme.onSurfaceVariant);
        }
        app.selectWeek(2);
        await tester.pumpAndSettle();
        for (var day = 1; day <= 7; day++) {
          expect(
              tester
                  .widget<Text>(find.byKey(ValueKey('week-header-day-$day')))
                  .style
                  ?.color,
              scheme.onSurfaceVariant);
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });

  testWidgets(
      'makeup notes use JSON weekday, persist with no upcoming class, and handle missing weekday',
      (tester) async {
    final today = shanghaiNow();
    final app = AppController(NotificationService());
    const days = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    for (var day = 0; day <= 7; day++) {
      app.teachingCalendar = TeachingCalendar.parse(jsonEncode({
        'version': day + 1,
        'rules': [
          {
            'date': calendarDateKey(today),
            'type': 'makeup',
            if (day != 0) 'use_weekday': day
          }
        ]
      }));
      await tester
          .pumpWidget(MaterialApp(home: Scaffold(body: HomePage(app: app))));
      await tester.pump();
      final text = day == 0 ? '今日调休，请注意课程安排' : '今日调休，请按${days[day - 1]}课程安排上课';
      expect(find.text(text), findsOneWidget);
      expect(find.text('0 门课'), findsOneWidget);
      expect(find.text('今天'), findsOneWidget);
      final noteStyle = tester
          .widget<Text>(find.byKey(const Key('today-makeup-message')))
          .style;
      final countStyle = tester.widget<Text>(find.text('0 门课')).style;
      final todayTabStyle =
          DefaultTextStyle.of(tester.element(find.text('今日课程'))).style;
      final messageTabStyle =
          DefaultTextStyle.of(tester.element(find.text('消息'))).style;
      expect(noteStyle?.fontSize, todayTabStyle.fontSize);
      expect(noteStyle?.fontWeight, todayTabStyle.fontWeight);
      expect(noteStyle?.fontSize, messageTabStyle.fontSize);
      expect(noteStyle?.fontWeight, messageTabStyle.fontWeight);
      expect(noteStyle?.color, countStyle?.color);
      expect(countStyle?.fontSize, 13);
      expect(
          tester
              .widget<Text>(find.byKey(const Key('today-makeup-message')))
              .style
              ?.fontSize,
          lessThan(20));
      await tester.pump(const Duration(minutes: 1));
      expect(find.text(text), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    for (final type in ['holiday', 'no_class', null]) {
      app.teachingCalendar = TeachingCalendar.parse(jsonEncode({
        'version': 'normal',
        'rules': [
          if (type != null) {'date': calendarDateKey(today), 'type': type}
        ]
      }));
      await tester
          .pumpWidget(MaterialApp(home: Scaffold(body: HomePage(app: app))));
      await tester.pump();
      expect(find.byKey(const Key('today-makeup-message')), findsNothing);
      expect(find.text('今天'), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });

  testWidgets(
      'calendar banners share styles, reserve space above navigation and follow current week',
      (tester) async {
    final today = calendarCivilDate(shanghaiNow());
    var clock = today;
    final first = today.subtract(Duration(days: today.weekday - 1 + 14));
    TeachingCalendar calendar({bool makeup = true, bool exam = true}) =>
        TeachingCalendar.parse(jsonEncode({
          'version': 2,
          'academic_year': 'test',
          'semesters': {
            'fall': {
              'start_date': calendarDateKey(first),
              'end_date': calendarDateKey(first.add(const Duration(days: 27))),
              'first_week_start': calendarDateKey(first),
              'total_weeks': 4,
              'exam_weeks': exam ? [3] : []
            },
            'spring': null,
            'summer': null
          },
          'rules': [
            if (makeup)
              {
                'date': calendarDateKey(today),
                'type': 'makeup',
                'use_weekday': today.weekday
              }
          ]
        }));
    final app = AppController(NotificationService(), calendarClock: () => clock)
      ..courses = [
        for (var i = 0; i < 8; i++) lesson('Course $i', today.weekday, [3])
      ]
      ..teachingCalendar = calendar();
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final width in [320.0, 390.0]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      for (final brightness in Brightness.values) {
        for (final seed in [Colors.blue, Colors.red]) {
          final scheme =
              ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
          await tester.pumpWidget(MaterialApp(
              theme: ThemeData(colorScheme: scheme),
              home: Scaffold(
                  body: MediaQuery(
                      data: MediaQueryData(
                          size: Size(width, 724),
                          textScaler: TextScaler.linear(1.3)),
                      child: HomePage(app: app, isActive: false)),
                  bottomNavigationBar: const SizedBox(
                      key: Key('test-bottom-navigation'), height: 76))));
          await tester.pumpAndSettle();
          final banner = find.byKey(const Key('calendar-notice-banner'));
          final makeup = find.byKey(const Key('today-makeup-message'));
          final exam = find.byKey(const Key('today-exam-message'));
          expect(tester.widget<Text>(exam).data, '本周为考试周，请按安排准时参加考试，加油！');
          expect(tester.widget<Text>(makeup).style,
              tester.widget<Text>(exam).style);
          expect(tester.widget<Text>(exam).style!.color, scheme.primary);
          expect(tester.getRect(makeup).bottom,
              lessThan(tester.getRect(exam).top));
          expect(
              tester.getRect(banner).bottom,
              lessThanOrEqualTo(tester
                  .getRect(find.byKey(const Key('test-bottom-navigation')))
                  .top));
          expect(tester.getRect(find.byType(TabBarView)).bottom,
              lessThanOrEqualTo(tester.getRect(banner).top));
          final vertical = find
              .descendant(
                  of: find.byType(ListView).first,
                  matching: find.byType(Scrollable))
              .first;
          await tester.scrollUntilVisible(find.text('Course 7'), 200,
              scrollable: vertical);
          expect(tester.getRect(find.text('Course 7')).bottom,
              lessThan(tester.getRect(banner).top));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      }
    }
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: HomePage(app: app, isActive: false))));
    app.teachingCalendar = calendar(makeup: false);
    app.notifyListeners();
    await tester.pump();
    expect(find.byKey(const Key('today-makeup-message')), findsNothing);
    expect(find.byKey(const Key('today-exam-message')), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
    clock = today.add(const Duration(days: 7));
    app.notifyListeners();
    await tester.pump();
    expect(find.byKey(const Key('calendar-notice-banner')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });
}
