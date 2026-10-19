import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jiaotong_course/models/app_theme.dart';
import 'package:jiaotong_course/models/canvas_data.dart';
import 'package:jiaotong_course/models/course.dart';
import 'package:jiaotong_course/models/teaching_calendar.dart';
import 'package:jiaotong_course/pages/settings_page.dart';
import 'package:jiaotong_course/pages/week_page.dart';
import 'package:jiaotong_course/services/teaching_calendar_repository.dart';
import 'package:jiaotong_course/state/app_controller.dart';
import 'package:jiaotong_course/widgets/canvas_announcement_observer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_database.dart';
import 'semester_calendar_test.dart' show sample, semester;
import 'week_display_mode_test.dart' show QuietNotifications;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'static date uses matched season and refreshes only valid remote dates',
      (tester) async {
    var remote = jsonEncode({
      'version': 2,
      'rules': [],
      'semesters': {
        'fall': semester('2026-09-14', '2027-01-17', '2026-09-14', 18, []),
        'spring': semester('2027-02-22', '2027-06-27', '2027-02-22', 18, []),
        'summer': semester('2027-07-05', '2027-08-01', '2027-07-05', 4, []),
      },
    });
    for (final entry in {
      DateTime(2026, 10, 1): '9.14–1.17',
      DateTime(2027, 3, 1): '2.22–6.27',
      DateTime(2027, 7, 10): '7.5–8.1',
      DateTime(2027, 2, 1): null,
    }.entries) {
      final app = AppController(QuietNotifications(),
          database: MemoryDatabase(),
          calendarClock: () => entry.key,
          calendarRepository:
              TeachingCalendarRepository(fetch: () async => remote))
        ..teachingCalendar = TeachingCalendar.parse(remote)
        ..dynamicWeekDisplay = false;
      await tester
          .pumpWidget(MaterialApp(home: Scaffold(body: WeekPage(app: app))));
      if (entry.value == null) {
        expect(find.byKey(const Key('semester-date-range')), findsNothing);
      } else {
        expect(
            tester
                .widget<Text>(find.byKey(const Key('semester-date-range')))
                .data,
            entry.value);
      }
      expect(find.byIcon(Icons.sync_rounded), findsNothing);
      expect(find.byKey(const Key('week-current-marker')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
    }
    remote = sample();
    final app = AppController(QuietNotifications(),
        database: MemoryDatabase(),
        calendarClock: () => DateTime(2030, 1, 9),
        calendarRepository:
            TeachingCalendarRepository(fetch: () async => remote))
      ..teachingCalendar = TeachingCalendar.parse(remote)
      ..dynamicWeekDisplay = false;
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: WeekPage(app: app))));
    expect(find.text('1.7–1.27'), findsOneWidget);
    remote = sample(end: '2030-01-28');
    await app.refreshTeachingCalendar();
    await tester.pump();
    expect(find.text('1.7–1.28'), findsOneWidget);
    await app.setDynamicWeekDisplay(true);
    await tester.pumpAndSettle();
    expect(find.text('1.7–1.13'), findsOneWidget);
    expect(find.byKey(const Key('semester-date-range')), findsNothing);
    final marker = tester.getRect(find.byKey(const Key('week-current-marker')));
    expect(marker.center.dx,
        tester.view.physicalSize.width / tester.view.devicePixelRatio - 32);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
  });

  testWidgets(
      'static information has exactly one blank line between present fields',
      (tester) async {
    for (final fields in [
      {'location': '教室', 'teacher': '教师'},
      {'location': '', 'teacher': '教师'},
      {'location': '教室', 'teacher': ''},
      {'location': '', 'teacher': ''},
    ]) {
      final app =
          AppController(QuietNotifications(), database: MemoryDatabase())
            ..dynamicWeekDisplay = false
            ..courses = [
              Course.fromMap({
                'id': 'spacing',
                'name': '习近平法治思想',
                ...fields,
                'weekday': 1,
                'startPeriod': 1,
                'endPeriod': 4,
                'activeWeeks': [2, 3, 4, 5, 7, 8, 9, 10, 11, 12, 13],
              })
            ];
      await tester
          .pumpWidget(MaterialApp(home: Scaffold(body: WeekPage(app: app))));
      final weeks = find.text('2-5周，7-13周');
      expect(weeks, findsOneWidget);
      final column = tester.widget<Column>(
          find.ancestor(of: weeks, matching: find.byType(Column)).first);
      final texts = column.children.whereType<Text>().toList();
      final gaps = column.children.whereType<SizedBox>().toList();
      expect(gaps.length, texts.length - 1);
      for (var i = 0; i < texts.length - 1; i++) {
        final before = tester.getRect(find.byWidget(texts[i]));
        final after = tester.getRect(find.byWidget(texts[i + 1]));
        expect(after.top - before.bottom, closeTo(9.9, .01));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
    }
  });

  for (final choice in AppThemeChoice.values) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'all three settings menus share geometry ${choice.name} ${brightness.name}',
          (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app =
            AppController(QuietNotifications(), database: MemoryDatabase());
        final scheme = ColorScheme.fromSeed(
            seedColor: choice.primaryFor(brightness), brightness: brightness);
        await tester.pumpWidget(MaterialApp(
            theme: ThemeData(colorScheme: scheme),
            home: Scaffold(body: SettingsPage(app: app, advanced: true))));
        for (final name in ['refresh', 'interface', 'reminder']) {
          final trigger = find.byKey(Key('settings-$name-menu'));
          await tester.ensureVisible(trigger);
          await tester.pumpAndSettle();
          final anchor = tester.getRect(trigger);
          await tester.tap(trigger);
          await tester.pumpAndSettle();
          final options = name == 'interface'
              ? find.byType(PopupMenuItem<InterfaceMode>)
              : find.byType(PopupMenuItem<int>);
          final rows =
              tester.widgetList<PopupMenuItem<dynamic>>(options).toList();
          final rect = tester.getRect(options.first);
          expect(rect.width, 176);
          expect(rect.right, closeTo(anchor.right, .01));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(tester.getRect(options.last).bottom, lessThanOrEqualTo(844));
          for (final row in rows) {
            final bounds = tester.getRect(find.byWidget(row));
            expect(bounds.height, 48);
            final text = find.descendant(
                of: find.byWidget(row), matching: find.byType(Text));
            expect(tester.getRect(text).left - bounds.left, 16);
            final style = tester.widget<Text>(text).style!;
            expect(style.fontSize, 14);
            expect(style.fontWeight, FontWeight.w400);
            expect(style.color, scheme.onSurface);
          }
          final surface = tester
              .widgetList<Material>(find.ancestor(
                  of: options.first, matching: find.byType(Material)))
              .first;
          expect(
              surface.shape,
              isA<RoundedRectangleBorder>().having(
                  (s) => s.borderRadius, 'radius', BorderRadius.circular(12)));
          expect(surface.color, scheme.surfaceContainerLow);
          Navigator.of(tester.element(trigger)).pop();
          await tester.pumpAndSettle();
        }
        expect(find.text('15分'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        app.dispose();
      });
    }
  }

  testWidgets(
      'mock native bridge: foreground polling, background pause, offline recovery and read dedup',
      (tester) async {
    const channel = MethodChannel('cn.sjtu.jiaotong_course/announcements');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var offline = false;
    var refreshes = 0;
    final configurations = <Map>[];
    var rows = <Map<String, Object>>[];
    String data() => jsonEncode({
          'courses': [
            {'id': '42', 'announcements': rows}
          ]
        });
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'configure') {
        configurations.add(call.arguments as Map);
        return null;
      }
      if (call.method == 'refresh') {
        refreshes++;
        if (offline) throw PlatformException(code: 'network_unavailable');
      }
      return data();
    });
    final app = AppController(QuietNotifications(), database: MemoryDatabase())
      ..username = 'test-account'
      ..loggedIn = true
      ..canvas = CanvasSnapshot.fromMap({
        'courses': [
          {'id': '42', 'name': '测试课'}
        ]
      })
      ..courses = [
        Course.fromMap({'id': 'c', 'name': '测试课', 'canvasCourseId': '42'})
      ];
    await tester
        .pumpWidget(MaterialApp(home: CanvasAnnouncementObserver(app: app)));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(configurations.last['notificationsEnabled'], false);
    expect(configurations.last['account'], isNot('test-account'));
    rows = [
      {
        'id': '7',
        'assetId': '7',
        'title': '新公告',
        'createdAt': '2026-10-19T01:00:00Z'
      }
    ];
    await tester.pump(const Duration(minutes: 2));
    await tester.pumpAndSettle();
    expect(app.unreadMessageCount, 1);
    await app.markMessageRead(app.messageFeed.single.key);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final before = refreshes;
    await tester.pump(const Duration(minutes: 4));
    expect(refreshes,
        before); // Dart timer is never claimed as native background work.
    offline = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(app.messageFeed.length, 1);
    expect(app.unreadMessageCount, 0);
    offline = false;
    rows.add({
      'id': '8',
      'assetId': '8',
      'title': '恢复后公告',
      'createdAt': '2026-10-19T02:00:00Z'
    });
    rows.add(rows.last); // Repeated server item must not inflate unread counts.
    await tester.pump(const Duration(minutes: 2));
    await tester.pumpAndSettle();
    expect(app.messageFeed.length, 2);
    expect(app.unreadMessageCount, 1);
    expect(app.messageFeed.first.title, '恢复后公告');
    await tester.pump(const Duration(minutes: 2));
    await tester.pumpAndSettle();
    expect(app.unreadMessageCount, 1);
    final beforeNativeEvent = refreshes;
    rows.add({
      'id': '9',
      'assetId': '9',
      'title': '原生任务公告',
      'createdAt': '2026-10-19T03:00:00Z'
    });
    tester.binding.channelBuffers.push(
        channel.name,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('updated')),
        (_) {});
    await tester.pumpAndSettle();
    expect(refreshes, beforeNativeEvent);
    expect(app.messageFeed.length, 3);
    expect(app.unreadMessageCount, 2);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
}
