import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jiaotong_course/models/attendance.dart';
import 'package:jiaotong_course/models/canvas_data.dart';
import 'package:jiaotong_course/pages/home_page.dart';
import 'package:jiaotong_course/pages/attendance_status_page.dart';
import 'package:jiaotong_course/services/attendance_controller.dart';
import 'package:jiaotong_course/services/attendance_native.dart';
import 'package:jiaotong_course/services/message_feed.dart';
import 'package:jiaotong_course/state/app_controller.dart';
import 'attendance_test.dart' show fixtureCourse;
import 'attendance_record_execution_test.dart' show ExecutionRecords;
import 'support/memory_database.dart';
import 'week_display_mode_test.dart' show QuietNotifications;

class InboxBackend extends ExecutionRecords
    implements AttendanceMessageBackend {
  List<AttendanceMessage> inbox = [];
  Completer<List<AttendanceMessage>>? inboxGate;
  @override
  Future<List<AttendanceMessage>> readRecordMessages(String account) async {
    final gate = inboxGate;
    inboxGate = null;
    return gate == null ? inbox : gate.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in {
      'InboxPreviewChinese': 'C:/Windows/Fonts/msyh.ttc',
      'MaterialIcons':
          'T:/work/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
    }.entries) {
      final file = File(entry.value);
      if (await file.exists()) {
        await (FontLoader(entry.key)
              ..addFont(
                  file.readAsBytes().then((b) => ByteData.view(b.buffer))))
            .load();
      }
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final start = DateTime.utc(2026, 10, 26, 2); // Monday, Shanghai 10:00
  final course = fixtureCourse(
      start: 600, end: 705, weeks: List.generate(18, (i) => i + 1));
  final meeting = AttendanceMeeting(
      course: course,
      start: start,
      end: start.add(const Duration(minutes: 105)));
  AttendanceRecord record(
          {String key = '91:early',
          String state = 'UNNORMAL',
          DateTime? at,
          String id = '91'}) =>
      AttendanceRecord(
          key: key,
          canvasId: id,
          createdAt: at ?? start.subtract(const Duration(minutes: 19)),
          state: state);
  AttendanceMessage message({String state = 'UNNORMAL'}) => AttendanceMessage(
      record: record(state: state),
      courseName: course.name,
      discoveredAt: start.subtract(const Duration(minutes: 19)),
      checkedAt: start,
      windowEnd: meeting.detectionEnd);
  Future<AttendanceController> setup(InboxBackend b,
      {bool autoDispose = true}) async {
    final c = AttendanceController(backend: b, clock: () => b.now);
    await c.restore();
    await c.updateSchedule('fixture', [meeting]);
    if (autoDispose) addTearDown(c.dispose);
    return c;
  }

  test(
      'early manual read enters inbox once without consent, sign or notification permission',
      () async {
    final b = InboxBackend()
      ..now = start.subtract(const Duration(minutes: 19))
      ..rows = [record()];
    final c = await setup(b);
    await c.inspectManually(meeting);
    expect(c.messagesFor('fixture'), hasLength(1));
    final key = c.messagesFor('fixture').single.key;
    await c.inspectManually(meeting);
    expect(c.messagesFor('fixture').single.key, key);
    expect(c.pendingRecord, isNull);
    expect(c.executing, false);
    expect(b.attempts, 0);
    expect(b.notices, 0);
    b.now = start;
    b.rows = [record(state: 'NORMAL')];
    await c.inspectManually(meeting);
    expect(c.messagesFor('fixture').single.key, key);
    expect(c.messagesFor('fixture').single.statusAt(b.now), '已签到');
    expect(c.messagesFor('someone-else'), isEmpty);
  });

  test(
      'historical, future, wrong-course and already-signed records create no new messages',
      () async {
    final b = InboxBackend()
      ..now = start
      ..rows = [
        record(at: start.subtract(const Duration(days: 7))),
        record(key: '91:future', at: start.add(const Duration(seconds: 1))),
        record(id: '92', key: '92:other'),
        record(key: '91:done', state: 'NORMAL')
      ];
    final c = await setup(b);
    await c.inspectManually(meeting);
    expect(c.messagesFor('fixture'), isEmpty);
    b.now = meeting.detectionEnd;
    b.rows = [record()];
    await c.inspectManually(meeting);
    expect(c.messagesFor('fixture'), isEmpty);
  });

  test(
      'background inbox restores after the window ends and survives restart; account switch hides it',
      () async {
    final b = InboxBackend()
      ..now = meeting.detectionEnd
      ..inbox = [message()];
    final c = await setup(b);
    expect(c.messagesFor('fixture').single.statusAt(b.now), '检测窗口已结束');
    final second = await setup(InboxBackend()..now = b.now);
    expect(second.messagesFor('fixture'), hasLength(1));
    b.inbox = [];
    await c.updateSchedule('other', [meeting]);
    expect(c.messagesFor('fixture'), isEmpty);
    expect(c.messagesFor('other'), isEmpty);
    await c.updateSchedule('fixture', [meeting]);
    expect(c.messagesFor('fixture'), hasLength(1));
  });

  test('late native inbox reply cannot leak across account change', () async {
    final b = InboxBackend()..now = start;
    final c = await setup(b);
    final gate = Completer<List<AttendanceMessage>>();
    b.inboxGate = gate;
    final reading = c.refreshMessages();
    await c.updateSchedule('other', [meeting]);
    gate.complete([message()]);
    await reading;
    expect(c.messagesFor('other'), isEmpty);
  });

  test(
      'mixed messages sort by time, use separate IDs, and reject a mismatched native account',
      () async {
    final canvas = CanvasSnapshot(dashboardItems: [
      CanvasItem(
          id: 'early',
          title: '公告',
          messageHtml: '',
          type: '公告',
          courseName: course.name,
          createdAt:
              start.subtract(const Duration(minutes: 20)).toIso8601String(),
          htmlUrl: '')
    ], courses: [], syncedAt: start);
    final feed = buildMessageFeed(canvas, [course],
        attendanceMessages: [message(), message()]);
    expect(feed, hasLength(2));
    expect(feed.first.attendanceMessage, isNotNull);
    expect(feed.last.canvasItem, isNotNull);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        NativeAttendanceBackend.channel,
        (_) async => {
              'status': 'ok',
              'account': 'other',
              'messages': [message().toMap()]
            });
    expect(
        await NativeAttendanceBackend().readRecordMessages('fixture'), isEmpty);
    messenger.setMockMethodCallHandler(
        NativeAttendanceBackend.channel,
        (_) async => {
              'status': 'ok',
              'account': 'fixture',
              'messages': [
                message().toMap(),
                {'bad': true}
              ]
            });
    expect(await NativeAttendanceBackend().readRecordMessages('fixture'),
        hasLength(1));
    messenger.setMockMethodCallHandler(NativeAttendanceBackend.channel, null);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'message arrival, unread badge, course navigation and theme switch in $brightness',
        (t) async {
      t.view.physicalSize = const Size(393, 852);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final b = InboxBackend()..now = start;
      final c = await setup(b, autoDispose: false);
      final app = AppController(QuietNotifications(),
          database: MemoryDatabase(), attendance: c)
        ..username = 'fixture'
        ..loggedIn = true
        ..courses = [course]
        ..termStart = DateTime(2026, 10, 26)
        ..totalWeeks = 18;
      final captureKey = GlobalKey();
      Widget page(Brightness mode) => MaterialApp(
          theme: ThemeData(brightness: mode, fontFamily: 'InboxPreviewChinese'),
          home: Scaffold(
              body:
                  RepaintBoundary(key: captureKey, child: HomePage(app: app))));
      await t.pumpWidget(page(brightness));
      b.rows = [record()];
      await c.inspectManually(meeting);
      await t.pump();
      expect(app.unreadMessageCount, 1);
      expect(find.text('1'), findsOneWidget);
      await t.tap(find.text('消息'));
      await t.pumpAndSettle();
      expect(find.text('发现课程签到'), findsOneWidget);
      expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
      await t.runAsync(() async {
        final boundary = captureKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final picture = await boundary.toImage();
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        final output =
            File('build/attendance-inbox-previews/${brightness.name}.png');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
      await t.pumpWidget(page(
          brightness == Brightness.light ? Brightness.dark : Brightness.light));
      await t.pumpAndSettle();
      expect(find.text('发现课程签到'), findsOneWidget);
      await t.tap(find.text('发现课程签到'));
      await t.pumpAndSettle();
      expect(find.byType(AttendanceStatusPage), findsOneWidget);
      expect(
          t
              .widget<AttendanceStatusPage>(find.byType(AttendanceStatusPage))
              .initialCanvasId,
          '91');
      expect(app.unreadMessageCount, 0);
      expect(b.attempts, 0);
      b.rows = [record(state: 'NORMAL')];
      await c.inspectManually(meeting);
      expect(app.messageFeed.where((m) => m.attendanceMessage != null),
          hasLength(1));
      expect(app.unreadMessageCount, 0);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.textContaining('签到 · 已签到'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      app.dispose();
    });
  }
}
